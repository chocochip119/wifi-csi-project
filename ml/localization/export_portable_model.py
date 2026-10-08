"""Export a trained run's selected Ridge model for the PC backend (numpy-only).

    python export_portable_model.py --run <runs/run_...> [--replace]

Writes   pc/backend/localization/models/ridge_portable.{npz,json}
         pc/backend/tests/fixtures/selfcheck_fixture.npz  (validation windows only)
and checks that the npz gives the same features/scores/labels as the saved
scikit-learn bundle on every validation window of the run. Run it with the
training environment (exact versions; the joblib loader checks them).
The held-out test split is never read. The run folder is only read.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

import numpy as np
import pandas as pd

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))

from location_core import make_features  # noqa: E402
from location_data import _read_record, file_sha256  # noqa: E402
from location_model import load_model, predict_windows  # noqa: E402

SCHEMA = "wise_portable_ridge_v1"   # must match pc/backend/localization/portable_ridge.py
MODEL_DIR = REPO / "pc" / "backend" / "localization" / "models"
FIXTURE = REPO / "pc" / "backend" / "tests" / "fixtures" / "selfcheck_fixture.npz"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validation_windows(run: Path, config: dict):
    """Windows of the run's validation files, read exactly as in training (no test rows)."""
    manifest = pd.read_csv(run / "manifest.csv", encoding="utf-8-sig").fillna("")
    rows = manifest[(manifest["split"] == "validation") & (manifest["enabled"].astype(str).str.lower() == "true")]
    windows, labels = [], []
    for i, row in enumerate(rows.itertuples(index=False)):
        path = (run / str(row.path).replace("\\", "/")).resolve()
        if file_sha256(path) != row.sha256:
            raise SystemExit(f"validation file changed since training: {row.path}")
        record = {"resolved_path": str(path), "sha256": row.sha256, "path": row.path, "source_id": i,
                  "split": "validation", "point_id": row.point_id, "participant": row.person,
                  "block": row.session, "repeat": row.repeat}
        _, found = _read_record(record, config)
        windows += found
        labels += [row.point_id] * len(found)
    return windows, labels


def raw_fixture(windows, drop):
    width = 192 - drop
    max_cycles = max(len(w) for w in windows)
    raw = np.zeros((len(windows), max_cycles, 5, 384), dtype=np.int8)
    rssi = np.zeros((len(windows), max_cycles, 5), dtype=np.float64)
    for w, window in enumerate(windows):
        for c, cycle in enumerate(window):
            for rx in range(5):
                pairs = np.zeros((192, 2), dtype=np.int8)   # dropped leading pairs never reach features
                pairs[drop:, 0] = cycle["imag"][rx * width:(rx + 1) * width].astype(np.int8)
                pairs[drop:, 1] = cycle["real"][rx * width:(rx + 1) * width].astype(np.int8)
                raw[w, c, rx] = pairs.reshape(-1)
            rssi[w, c] = cycle["rssi"]
    return raw, rssi, np.asarray([len(w) for w in windows])


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--run", required=True, help="training run folder (contains fit/selected_model.json)")
    parser.add_argument("--fixture-windows", type=int, default=40)
    parser.add_argument("--replace", action="store_true", help="overwrite the existing backend model/fixture")
    args = parser.parse_args()
    run = Path(args.run).resolve()
    selected = json.loads((run / "fit" / "selected_model.json").read_text(encoding="utf-8"))
    model_path = run / "fit" / selected["model_path"]
    bundle = load_model(model_path)
    estimator, scaler = bundle["estimator"], bundle["scaler"]
    if type(estimator).__name__ != "RidgeClassifier" or bundle["variant"] != "amp_rssi":
        raise SystemExit("portable export supports the amp_rssi RidgeClassifier only")
    targets = [MODEL_DIR / "ridge_portable.npz", MODEL_DIR / "ridge_portable.json", FIXTURE]
    if any(p.exists() for p in targets) and not args.replace:
        raise SystemExit("backend model/fixture exists; pass --replace to overwrite")

    npz = MODEL_DIR / "ridge_portable.npz"
    np.savez(npz, coef=np.asarray(estimator.coef_, dtype=np.float64),
             intercept=np.asarray(estimator.intercept_, dtype=np.float64),
             scaler_mean=np.asarray(scaler.mean_, dtype=np.float64),
             scaler_scale=np.asarray(scaler.scale_, dtype=np.float64),
             estimator_classes=np.asarray([str(c) for c in estimator.classes_], dtype="<U8"))
    meta = {
        "schema": SCHEMA, "npz_sha256": sha256(npz),
        "source_run": run.name, "source_model": f"{run.name}/fit/{selected['model_path']}",
        "source_model_sha256": sha256(model_path), "source_versions": bundle["versions"],
        "studio_schema": bundle["schema"], "family": bundle["family"], "variant": bundle["variant"],
        "task": bundle["task"], "empty_label": bundle["empty_label"],
        "location_classes": list(bundle["location_classes"]), "bundle_classes": list(bundle["classes"]),
        "estimator_classes_order": [str(c) for c in estimator.classes_],
        "points_cm": bundle["points_cm"], "config": bundle["config"], "feature_contract": bundle["feature_contract"],
        "test_evaluated": bool(selected.get("test_evaluated")),
        "math": "z=(x-scaler_mean)/scaler_scale; score=z@coef.T+intercept; label=estimator_classes[argmax(score)]",
        "note": "decision column j = estimator_classes[j] (empty first), not bundle_classes[j]",
    }
    (MODEL_DIR / "ridge_portable.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n",
                                                   encoding="utf-8", newline="\n")

    # Check every validation window, then keep evenly spaced ones as the fixture.
    windows, truth = validation_windows(run, bundle["config"])
    features = make_features(windows, bundle["config"])
    sk_scores = estimator.decision_function(scaler.transform(features))
    sk_labels = predict_windows(bundle, windows)
    data = np.load(npz, allow_pickle=False)
    z = (features - data["scaler_mean"]) / data["scaler_scale"]
    np_scores = z @ data["coef"].T + data["intercept"]
    np_labels = data["estimator_classes"][np.argmax(np_scores, axis=1)]
    mismatches = int((np_labels != sk_labels).sum())
    pick = np.unique(np.linspace(0, len(windows) - 1, args.fixture_windows).astype(int))
    chosen = [windows[i] for i in pick]
    raw, rssi, counts = raw_fixture(chosen, bundle["config"]["drop_pairs"])
    np.savez(FIXTURE, raw_csi=raw, rssi=rssi, cycle_counts=counts, features=features[pick],
             sklearn_scores=sk_scores[pick], sklearn_labels=np.asarray(sk_labels[pick], dtype="<U8"))
    report = {"run": run.name, "model": selected["model_path"], "validation_windows": len(windows),
              "score_max_abs_diff": float(np.abs(np_scores - sk_scores).max()), "label_mismatches": mismatches,
              "validation_accuracy": round(float(np.mean(np.asarray(sk_labels) == np.asarray(truth))), 4),
              "fixture_windows": int(len(pick)), "fixture_classes": sorted(set(map(str, sk_labels[pick]))),
              "npz_sha256": meta["npz_sha256"]}
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if mismatches or report["score_max_abs_diff"] > 1e-9:
        raise SystemExit("portable model does not match the saved model")


if __name__ == "__main__":
    main()
