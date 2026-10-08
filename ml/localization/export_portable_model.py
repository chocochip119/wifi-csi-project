"""Export a trained run's selected Ridge model for the PC backend (numpy-only).

    python export_portable_model.py --run <runs/run_...> [--replace]

First checks, in memory, that the exported arrays give the same scores/labels as
the saved scikit-learn bundle on every validation window of the run (files are
identified by the hashes frozen in the bundle). Only then writes
         pc/backend/localization/models/ridge_portable.{npz,json}
         pc/backend/tests/fixtures/selfcheck_fixture.npz  (validation windows only)
via temporary files; on any failure the backend files are left unchanged.
Run it with the training environment (exact versions; the joblib loader checks
them). The held-out test split is never read. The run folder is only read.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys

import numpy as np
import pandas as pd

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))

from location_core import make_features  # noqa: E402
from location_data import _enabled, _read_record, file_sha256  # noqa: E402
from location_model import load_model, predict_windows  # noqa: E402

SCHEMA = "wise_portable_ridge_v1"   # must match pc/backend/localization/portable_ridge.py
MODEL_DIR = REPO / "pc" / "backend" / "localization" / "models"
FIXTURE = REPO / "pc" / "backend" / "tests" / "fixtures" / "selfcheck_fixture.npz"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validation_windows(run: Path, config: dict, trusted_hashes):
    """Windows of the run's validation files, read exactly as in training (no test rows).

    File identity is checked against the hashes frozen in the model bundle, not the
    editable manifest sha256 column; `enabled` is parsed like training (_enabled)."""
    trusted = set(trusted_hashes)
    manifest = pd.read_csv(run / "manifest.csv", encoding="utf-8-sig").fillna("")
    rows = manifest[(manifest["split"] == "validation") & manifest["enabled"].map(_enabled)]
    windows, labels, seen = [], [], set()
    for i, row in enumerate(rows.itertuples(index=False)):
        path = (run / str(row.path).replace("\\", "/")).resolve()
        digest = file_sha256(path)
        if digest not in trusted:
            raise SystemExit(f"not a validation file of this run (or changed since training): {row.path}")
        seen.add(digest)
        record = {"resolved_path": str(path), "sha256": digest, "path": row.path, "source_id": i,
                  "split": "validation", "point_id": row.point_id, "participant": row.person,
                  "block": row.session, "repeat": row.repeat}
        _, found = _read_record(record, config)
        windows += found
        labels += [row.point_id] * len(found)
    if seen != trusted:
        raise SystemExit(f"{len(trusted - seen)} validation files used in training are missing from the manifest")
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

    # 1) Everything in memory; nothing in pc/backend is touched until the parity check passes.
    arrays = {"coef": np.asarray(estimator.coef_, dtype=np.float64),
              "intercept": np.asarray(estimator.intercept_, dtype=np.float64),
              "scaler_mean": np.asarray(scaler.mean_, dtype=np.float64),
              "scaler_scale": np.asarray(scaler.scale_, dtype=np.float64),
              "estimator_classes": np.asarray([str(c) for c in estimator.classes_], dtype="<U8")}
    windows, truth = validation_windows(run, bundle["config"], bundle["validation_raw_hashes"])
    features = make_features(windows, bundle["config"])
    sk_scores = estimator.decision_function(scaler.transform(features))
    sk_labels = predict_windows(bundle, windows)
    np_scores = ((features - arrays["scaler_mean"]) / arrays["scaler_scale"]) @ arrays["coef"].T + arrays["intercept"]
    np_labels = arrays["estimator_classes"][np.argmax(np_scores, axis=1)]
    mismatches = int((np_labels != sk_labels).sum())
    pick = np.unique(np.linspace(0, len(windows) - 1, args.fixture_windows).astype(int))
    report = {"run": run.name, "model": selected["model_path"], "validation_windows": len(windows),
              "score_max_abs_diff": float(np.abs(np_scores - sk_scores).max()), "label_mismatches": mismatches,
              "validation_accuracy": round(float(np.mean(np.asarray(sk_labels) == np.asarray(truth))), 4),
              "fixture_windows": int(len(pick)), "fixture_classes": sorted(set(map(str, sk_labels[pick])))}
    if mismatches or report["score_max_abs_diff"] > 1e-9:
        print(json.dumps(report, ensure_ascii=False, indent=2))
        raise SystemExit("portable model does not match the saved model; backend files left unchanged")

    # 2) Write to temporary files, re-read the NPZ, then swap all three into place.
    raw, rssi, counts = raw_fixture([windows[i] for i in pick], bundle["config"]["drop_pairs"])
    tmp_npz, tmp_json, tmp_fixture = (MODEL_DIR / "ridge_portable.tmp.npz", MODEL_DIR / "ridge_portable.tmp.json",
                                      FIXTURE.with_name(FIXTURE.stem + ".tmp.npz"))
    np.savez(tmp_npz, **arrays)
    with np.load(tmp_npz, allow_pickle=False) as written:
        if any(not np.array_equal(written[k], v) for k, v in arrays.items()):
            raise SystemExit("NPZ round-trip mismatch; backend files left unchanged")
    meta = {
        "schema": SCHEMA, "npz_sha256": sha256(tmp_npz),
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
    tmp_json.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    np.savez(tmp_fixture, raw_csi=raw, rssi=rssi, cycle_counts=counts, features=features[pick],
             sklearn_scores=sk_scores[pick], sklearn_labels=np.asarray(sk_labels[pick], dtype="<U8"))
    for tmp, final in ((tmp_npz, MODEL_DIR / "ridge_portable.npz"), (tmp_json, MODEL_DIR / "ridge_portable.json"),
                       (tmp_fixture, FIXTURE)):
        os.replace(tmp, final)
    report["npz_sha256"] = meta["npz_sha256"]
    print(json.dumps(report, ensure_ascii=False, indent=2))

if __name__ == "__main__":
    main()
