"""Presence plus nine-point + p05-seated models with explicitly held-out evaluation.

The joblib bundle includes every fitted transform and the acquisition/feature
contract needed by live inference. Load only joblib files from a trusted source.
"""
from __future__ import annotations

from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import importlib.metadata
import time
import warnings

import joblib
import numpy as np
import pandas as pd
import sklearn
from sklearn.linear_model import RidgeClassifier
from sklearn.metrics import accuracy_score, balanced_accuracy_score, confusion_matrix, f1_score, precision_score
from sklearn.neighbors import KNeighborsClassifier
from sklearn.neural_network import MLPClassifier
from sklearn.preprocessing import StandardScaler
from threadpoolctl import threadpool_limits

from .fivepoint_core import fit_phase, make_features, validate_config, inference_config
from .labels import CLASSES as LABEL_CLASSES, LOCATION_CLASSES, EMPTY_LABEL, POINTS_CM, TASK

CLASSES = list(LABEL_CLASSES)


SCHEMA = "csi_studio_model_v2_presence"
RETRAIN_MESSAGE = ("빈 공간(empty)과 9지점·p10(p05 앉기)을 함께 학습한 새 11클래스 모델이 필요합니다. "
                   "기존 5클래스/Python 3.11 모델은 사용할 수 없으므로 새로 학습하세요.")
FAMILIES = ("knn", "ridge", "mlp")
VARIANTS = ("amp_rssi", "amp_phase_rssi")


def _require(condition, message):
    if not condition:
        raise ValueError(message)


def _json_default(value):
    if isinstance(value, np.ndarray):
        return value.tolist()
    if isinstance(value, np.generic):
        return value.item()
    if isinstance(value, Path):
        return str(value)
    raise TypeError(type(value).__name__)


def _write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2,
                                    allow_nan=False, default=_json_default), encoding="utf-8")


def _new_estimator(family, seed, params):
    defaults = {
        "knn": {"n_neighbors": 5, "weights": "distance", "n_jobs": 1},
        "ridge": {"alpha": 10.0},
        "mlp": {"hidden_layer_sizes": (64, 32), "random_state": seed, "max_iter": 300, "alpha": 1e-3,
                "early_stopping": False, "n_iter_no_change": 25, "solver": "adam"},
    }
    constructors = {"knn": KNeighborsClassifier, "ridge": RidgeClassifier, "mlp": MLPClassifier}
    return constructors[family](**{**defaults[family], **params})


def _samples(dataset, split):
    selected = [s for s in dataset["samples"] if s["split"] == split]
    _require(bool(selected), f"{split} 데이터가 없습니다.")
    _require({s["point_id"] for s in selected} == set(CLASSES), f"{split}에는 9지점·p10·empty, 총 11클래스 모두 필요합니다.")
    return selected


def _check_dataset(dataset):
    _require(dataset.get("schema") == "csi_presence_dataset_v2", "11클래스(9지점+p10+empty)를 포함해 load_dataset으로 새로 만든 데이터가 필요합니다.")
    config = validate_config(dataset["config"])
    _require(bool(dataset.get("samples")), "학습할 입력이 없습니다.")
    source_splits, hash_splits, source_labels = {}, {}, {}
    for sample in dataset["samples"]:
        split, ident, digest = sample["split"], sample["source_id"], sample["sha256"]
        _require(split in {"train", "validation", "test"}, f"알 수 없는 split: {split}")
        _require(sample["point_id"] in CLASSES, "알 수 없는 지점 라벨")
        source_splits.setdefault(ident, set()).add(split)
        hash_splits.setdefault(digest, set()).add(split)
        source_labels.setdefault(ident, set()).add(sample["point_id"])
    _require(all(len(v) == 1 for v in source_splits.values()), "같은 원본 파일의 입력이 split 사이에 섞였습니다.")
    _require(all(len(v) == 1 for v in hash_splits.values()), "같은 원본 내용이 split 사이에 섞였습니다.")
    _require(all(len(v) == 1 for v in source_labels.values()), "같은 원본 파일에 서로 다른 지점 라벨이 있습니다.")
    return config


def _metrics(samples, prediction):
    truth, prediction = np.asarray([s["point_id"] for s in samples]), np.asarray(prediction)
    _require(len(truth) == len(prediction) and len(truth) > 0, "예측 길이가 맞지 않습니다.")
    _require(set(truth) == set(CLASSES), "평가에는 9지점·p10·empty, 총 11클래스 모두 필요합니다.")
    _require(set(prediction).issubset(CLASSES), "모델이 알 수 없는 지점을 출력했습니다.")
    file_predictions = []
    for ident in sorted({s["source_id"] for s in samples}):
        indices = np.asarray([i for i, s in enumerate(samples) if s["source_id"] == ident])
        votes = Counter(map(str, prediction[indices]))
        guess = min(CLASSES, key=lambda p: (-votes[p], CLASSES.index(p)))
        file_predictions.append({"source_id": ident, "path": samples[int(indices[0])]["path"],
                                 "truth": str(truth[indices[0]]), "prediction": guess,
                                 "sample_count": len(indices), "votes": dict(votes),
                                 "sample_accuracy": float(np.mean(prediction[indices] == truth[indices]))})
    true_empty = truth == EMPTY_LABEL
    predicted_empty = prediction == EMPTY_LABEL
    occupied_count, empty_count = int(np.sum(~true_empty)), int(np.sum(true_empty))
    tn = int(np.sum(true_empty & predicted_empty))
    fp = int(np.sum(true_empty & ~predicted_empty))
    fn = int(np.sum(~true_empty & predicted_empty))
    tp = int(np.sum(~true_empty & ~predicted_empty))
    # Empty has no spatial coordinate. Report location distance only where
    # both labels denote occupied points; missed occupancy remains wrong in
    # occupied_location_accuracy and is visible in the distance coverage.
    distances = [float(np.linalg.norm(np.asarray(POINTS_CM[str(a)]) - POINTS_CM[str(b)]))
                 for a, b in zip(truth, prediction) if a != EMPTY_LABEL and b != EMPTY_LABEL]
    return {"sample_count": len(samples), "correct": int(np.sum(truth == prediction)),
            "accuracy": float(accuracy_score(truth, prediction)),
            "balanced_accuracy": float(balanced_accuracy_score(truth, prediction)),
            "macro_f1": float(f1_score(truth, prediction, labels=CLASSES, average="macro", zero_division=0)),
            "macro_precision": float(precision_score(truth, prediction, labels=CLASSES, average="macro", zero_division=0)),
            "per_point_precision": dict(zip(CLASSES, map(float, precision_score(truth, prediction, labels=CLASSES, average=None, zero_division=0)))),
            "precision_zero_division": 0,
            "confusion_labels": list(CLASSES), "confusion_matrix": confusion_matrix(truth, prediction, labels=CLASSES).tolist(),
            "per_point_recall": {p: float(np.mean(prediction[truth == p] == p)) for p in CLASSES},
            "empty_sample_count": empty_count, "occupied_sample_count": occupied_count,
            "empty_false_positive_rate": fp / empty_count,
            "occupied_miss_rate": fn / occupied_count,
            "occupancy_accuracy": (tn + tp) / len(samples),
            "occupied_location_accuracy": float(np.sum((truth == prediction) & ~true_empty)) / occupied_count,
            "occupancy_binary_counts": {"true_empty_pred_empty": tn, "true_empty_pred_occupied": fp,
                                        "true_occupied_pred_empty": fn, "true_occupied_pred_occupied": tp},
            "occupancy_confusion_labels": [EMPTY_LABEL, "occupied"],
            "occupancy_confusion_matrix": [[tn, fp], [fn, tp]],
            "occupancy_positive_label": "occupied",
            "mean_nominal_point_error_cm": float(np.mean(distances)) if distances else None,
            "nominal_point_error_sample_count": len(distances),
            "nominal_point_error_coverage": len(distances) / occupied_count,
            "nominal_point_error_coverage_denominator": "all true occupied samples",
            "nominal_point_error_condition": "truth and prediction are both nonempty; nominal point coordinates only",
            "file_count": len(file_predictions),
            "file_majority_accuracy": float(np.mean([r["truth"] == r["prediction"] for r in file_predictions])),
            "file_predictions": file_predictions, "file_vote_tie_break": list(CLASSES)}


def _validate_bundle(bundle):
    _require(isinstance(bundle, dict) and bundle.get("schema") == SCHEMA, RETRAIN_MESSAGE)
    required = {"config", "variant", "family", "estimator", "scaler", "phase_contract", "classes", "points_cm", "feature_count",
                "task", "empty_label", "location_classes"}
    _require(required.issubset(bundle), f"모델 필수 항목 누락: {sorted(required - set(bundle))}")
    config = validate_config(bundle["config"])
    _require(bundle["classes"] == CLASSES and bundle["points_cm"] == POINTS_CM, "모델 지점/좌표 계약 불일치")
    _require(bundle["task"] == TASK and bundle["empty_label"] == EMPTY_LABEL
             and bundle["location_classes"] == list(LOCATION_CLASSES), "모델 재실/빈 공간 라벨 계약 불일치")
    _require(bundle["variant"] in VARIANTS and bundle["family"] in FAMILIES, "모델 종류/특징 종류 오류")
    _require(config["variant"] == bundle["variant"], "모델 특징 설정 불일치")
    n_amplitude = len(config["rx_ids"]) * (config["csi_len"] // 2 - config["drop_pairs"])
    expected = n_amplitude * (3 if bundle["variant"] == "amp_phase_rssi" else 1) + len(config["rx_ids"])
    _require(bundle["feature_count"] == expected, "모델 특징 개수 계약 불일치")
    _require(int(getattr(bundle["scaler"], "n_features_in_", -1)) == expected, "scaler 차원 불일치")
    _require(int(getattr(bundle["estimator"], "n_features_in_", -1)) == expected, "분류기 차원 불일치")
    _require(set(getattr(bundle["estimator"], "classes_", [])) == set(CLASSES), "분류기가 9지점·p10·empty, 11클래스로 학습되지 않았습니다.")
    _require(bundle["variant"] != "amp_phase_rssi" or bundle["phase_contract"] is not None, "위상 전처리 계약 누락")
    return bundle


def load_model(path):
    """Check the environment and digest before unpickling a trusted Studio model."""
    path = Path(path)
    sidecar = path.with_suffix(path.suffix + '.metadata.json')
    _require(sidecar.is_file(), "모델의 .joblib.metadata.json이 없습니다. 학습 결과 폴더 전체를 선택하세요.")
    meta = json.loads(sidecar.read_text(encoding='utf-8'))
    _require(meta.get('schema') == SCHEMA, RETRAIN_MESSAGE)
    _require(meta.get('classes') == CLASSES and meta.get('task') == TASK
             and meta.get('empty_label') == EMPTY_LABEL, RETRAIN_MESSAGE)
    _require(hashlib.sha256(path.read_bytes()).hexdigest() == meta.get('sha256'), '모델 SHA-256 불일치')
    current = runtime_versions()
    _require(meta.get('versions') == current,
             f"학습과 추론 환경이 다릅니다. 학습 환경={meta.get('versions')}, 현재={current}. 같은 .venv를 사용하세요.")
    bundle = joblib.load(path)
    _require(bundle.get('versions') == current, '모델 내부 버전 기록 불일치')
    return _validate_bundle(bundle)


def runtime_versions():
    return {'python': platform.python_version(),
            **{name: importlib.metadata.version(distribution) for name, distribution in (
                ('numpy', 'numpy'), ('scipy', 'scipy'), ('pandas', 'pandas'),
                ('sklearn', 'scikit-learn'), ('joblib', 'joblib'))}}


def predict_windows(bundle, windows):
    """Use the exact saved transforms for offline or live windows."""
    _validate_bundle(bundle)
    if not windows:
        return np.asarray([], dtype=str)
    features = make_features(windows, bundle["config"], phase_contract=bundle["phase_contract"])
    _require(features.ndim == 2 and features.shape[1] == bundle["feature_count"] and np.isfinite(features).all(),
             "예측 입력 차원 또는 유효값 검사 실패")
    with threadpool_limits(limits=1):
        return bundle["estimator"].predict(bundle["scaler"].transform(features))


def train_compare(dataset, output_dir, *, families=FAMILIES, variants=("amp_rssi",),
                  seed=17, model_params=None):
    """Fit selected candidates on train; compare on validation; never score test.

    model_params may override normal scikit-learn constructor arguments per
    family, e.g. {'knn': {'n_neighbors': 7}, 'mlp': {'max_iter': 400}}.
    No train+validation refit is performed; the selected saved bundle is exactly
    the one evaluated on validation. Use a new output directory for each run.
    """
    config = _check_dataset(dataset)
    families, variants = tuple(families), tuple(variants)
    _require(bool(families) and len(families) == len(set(families)) and set(families).issubset(FAMILIES), "families 설정 오류")
    _require(bool(variants) and len(variants) == len(set(variants)) and set(variants).issubset(VARIANTS), "variants 설정 오류")
    model_params = model_params or {}
    _require(set(model_params).issubset(FAMILIES), "알 수 없는 model_params family")
    train, validation = _samples(dataset, "train"), _samples(dataset, "validation")
    train_windows, validation_windows = [s["window"] for s in train], [s["window"] for s in validation]
    train_labels = np.asarray([s["point_id"] for s in train])
    output_dir = Path(output_dir).resolve()
    _require(not output_dir.exists() or not any(output_dir.iterdir()), f"기존 학습 결과 보존: 새 출력 폴더를 지정하세요 ({output_dir})")
    # Validate constructors before creating files.
    estimators = {f: _new_estimator(f, seed, model_params.get(f, {})) for f in families}
    if "knn" in estimators:
        _require(estimators["knn"].n_neighbors <= len(train), "kNN 이웃 수보다 학습 입력이 적습니다.")
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "models").mkdir()
    phase_contract = fit_phase(train_windows, config) if "amp_phase_rssi" in variants else None
    provenance = [{k: r[k] for k in ("path", "sha256", "split", "point_id", "participant", "block", "repeat")}
                  for r in dataset["records"].to_dict("records") if r["split"] in {"train", "validation"}]
    models, fits, predictions = {}, [], []
    for variant in variants:
        variant_config = {**config, "variant": variant}
        fitted_phase = phase_contract if variant == "amp_phase_rssi" else None
        train_features = make_features(train_windows, variant_config, phase_contract=fitted_phase)
        validation_features = make_features(validation_windows, variant_config, phase_contract=fitted_phase)
        _require(np.isfinite(train_features).all() and np.isfinite(validation_features).all(), "유한하지 않은 특징값")
        scaler = StandardScaler().fit(train_features)
        train_x, validation_x = scaler.transform(train_features), scaler.transform(validation_features)
        for family in families:
            candidate = f"{config['mode']}__{variant}__{family}"
            estimator = _new_estimator(family, seed, model_params.get(family, {}))
            begin = time.perf_counter()
            with warnings.catch_warnings(record=True) as caught, threadpool_limits(limits=1):
                warnings.simplefilter("always")
                estimator.fit(train_x, train_labels)
                prediction = estimator.predict(validation_x)
            score = _metrics(validation, prediction)
            bundle = {"schema": SCHEMA, "config": variant_config, "variant": variant, "family": family,
                      "task": TASK, "empty_label": EMPTY_LABEL, "location_classes": list(LOCATION_CLASSES),
                      "candidate": candidate, "estimator": estimator, "scaler": scaler,
                      "phase_contract": fitted_phase, "classes": list(CLASSES), "points_cm": dict(POINTS_CM),
                      "feature_count": train_x.shape[1], "train_sample_count": len(train),
                      "train_raw_hashes": sorted({s["sha256"] for s in train}),
                      "validation_raw_hashes": sorted({s["sha256"] for s in validation}),
                      "provenance": provenance, "test_data_used_in_fit_or_selection": False,
                      "created_utc": datetime.now(timezone.utc).isoformat(),
                      "versions": runtime_versions(),
                      "feature_contract": {"rx_order": list(config["rx_ids"]), "layout_id": config["layout_id"],
                                           "csi_bytes_per_rx": config["csi_len"], "drop_pairs": config["drop_pairs"],
                                           "iq_order": "imaginary_then_real", "amplitude": "hypot(imag, real)",
                                           "rssi": "arithmetic mean of dBm values",
                                           "order": "amplitude, RSSI, optional relative cosine then relative sine",
                                           "phase_fit_split": "train", "scaler_fit_split": "train",
                                           "phase_aggregation": "cycle cos/sin then window mean",
                                            "coordinate_source": "nine nominal points; p10 (p05 seated) shares p05 coordinate; empty has no coordinate",
                                            "empty_label": EMPTY_LABEL, "task": TASK}}
            _validate_bundle(bundle)
            relative_path = f"models/{candidate}.joblib"
            joblib.dump(bundle, output_dir / relative_path, compress=3)
            _write_json((output_dir / relative_path).with_suffix('.joblib.metadata.json'),
                         {'schema': SCHEMA, 'candidate': candidate, 'versions': runtime_versions(),
                          'task': TASK, 'classes': CLASSES, 'empty_label': EMPTY_LABEL,
                         'sha256': hashlib.sha256((output_dir / relative_path).read_bytes()).hexdigest(),
                         'feature_count': int(train_x.shape[1])})
            reloaded = load_model(output_dir / relative_path)
            _require(np.array_equal(prediction, predict_windows(reloaded, validation_windows)), "모델 저장/불러오기 예측 불일치")
            models[candidate] = relative_path
            fits.append({"candidate": candidate, "model_path": relative_path, "variant": variant,
                         "family": family, "feature_count": int(train_x.shape[1]),
                         "train_samples": len(train), "validation_samples": len(validation),
                         "validation_accuracy": score["accuracy"],
                         "validation_balanced_accuracy": score["balanced_accuracy"],
                         "validation_macro_f1": score["macro_f1"],
                         "validation_file_majority_accuracy": score["file_majority_accuracy"],
                         "fit_seconds": time.perf_counter() - begin, "validation": score,
                         "parameters": estimator.get_params(), "selection_order": len(fits),
                         "warnings": [{"category": w.category.__name__, "message": str(w.message)} for w in caught],
                         "reload_prediction_parity": True})
            predictions.extend({"candidate": candidate, "source_id": s["source_id"], "path": s["path"],
                                "sample_index": s["sample_index"], "truth": s["point_id"], "prediction": str(p)}
                               for s, p in zip(validation, prediction))
            print(f"{candidate}: validation BA={score['balanced_accuracy']:.3f}, F1={score['macro_f1']:.3f}", flush=True)
    ranked = sorted(fits, key=lambda r: (-r["validation_balanced_accuracy"], -r["validation_macro_f1"], r["selection_order"]))
    winner = ranked[0]
    columns = ["candidate", "model_path", "feature_count", "train_samples", "validation_samples",
               "validation_accuracy", "validation_balanced_accuracy", "validation_macro_f1",
               "validation_file_majority_accuracy", "fit_seconds"]
    leaderboard = pd.DataFrame([{k: entry[k] for k in columns} for entry in ranked])
    leaderboard.to_csv(output_dir / "leaderboard.csv", index=False, encoding="utf-8-sig")
    pd.DataFrame(predictions).to_csv(output_dir / "validation_predictions.csv", index=False, encoding="utf-8-sig")
    report = {"schema": "fivepoint_training_report_v2_presence", "complete": True, "config": config,
              "task": TASK, "empty_label": EMPTY_LABEL, "location_classes": list(LOCATION_CLASSES),
              "classes": CLASSES, "points_cm": POINTS_CM, "selected_candidate": winner["candidate"],
              "selected_model": winner["model_path"], "models": models, "fits": fits,
              "selection_rule": "validation balanced accuracy, macro F1, declared candidate order",
              "test_scores_accessed": False, "refit_train_plus_validation": False,
              "train_recording_count": len({s["source_id"] for s in train}),
              "validation_recording_count": len({s["source_id"] for s in validation}),
              "provenance": provenance,
              "limitations": ["Correlated windows are not independent recording counts.",
                               "Five known points plus labelled empty room; no unseen-position or multi-person count claim.",
                              "Holding out time blocks does not establish generalization to an unseen person.",
                              "Relative cos/sin is not calibrated physical phase or frequency slope removal."]}
    _write_json(output_dir / "training_report.json", report)
    _write_json(output_dir / "selected_model.json", {"candidate": winner["candidate"], "model_path": winner["model_path"],
                                                   "test_evaluated": False, "config": config})
    return {"output_dir": str(output_dir), "leaderboard": leaderboard, "models": models,
            "selected_candidate": winner["candidate"], "selected_model": winner["model_path"],
            "report_path": "training_report.json"}


def evaluate_saved(model_path, dataset, *, split="test", output_dir=None, inference_stride_s=None):
    """Explicitly unseal one saved model's held-out evaluation.

    Choosing another model after reading test scores turns that test into
    development data. Keep a fresh time block for the next final evaluation.
    """
    config = _check_dataset(dataset)
    _require(split in {"validation", "test"}, "학습 샘플은 독립 평가로 사용할 수 없습니다.")
    bundle = load_model(model_path)
    # Explicit cadence experiments may change stride alone. All feature,
    # window-length, radio, RX and quality requirements remain locked.
    expected_config = inference_config(bundle["config"], stride_s=inference_stride_s)
    saved_config = {k: v for k, v in expected_config.items() if k != "variant"}
    data_config = {k: v for k, v in config.items() if k != "variant"}
    _require(saved_config == data_config, "데이터와 저장 모델의 수집/윈도우 설정이 다릅니다.")
    samples = _samples(dataset, split)
    hashes = {s["sha256"] for s in samples}
    _require(not hashes.intersection(bundle.get("train_raw_hashes", [])), "평가 데이터가 학습 원본과 겹칩니다.")
    if split == "test":
        _require(not hashes.intersection(bundle.get("validation_raw_hashes", [])), "test 데이터가 모델 선택용 validation 원본과 겹칩니다.")
    prediction = predict_windows(bundle, [s["window"] for s in samples])
    metrics = {"candidate": bundle["candidate"], "split": split,
               "model_sha256": hashlib.sha256(Path(model_path).read_bytes()).hexdigest(),
               "model_training_stride_s": bundle["config"]["stride_s"],
               "inference_stride_s": config["stride_s"], "window_s": config["window_s"],
               "stride_override_explicit": inference_stride_s is not None,
               "evaluated_utc": datetime.now(timezone.utc).isoformat(), **_metrics(samples, prediction)}
    if output_dir is not None:
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)
        metrics_path, predictions_path = output_dir / f"{split}_metrics.json", output_dir / f"{split}_predictions.csv"
        _require(not metrics_path.exists() and not predictions_path.exists(), "기존 평가 결과 보존: 새 평가 출력 폴더를 지정하세요.")
        _write_json(metrics_path, metrics)
        pd.DataFrame([{k: s[k] for k in ("source_id", "path", "sample_index", "point_id")}
                      | {"prediction": str(p)} for s, p in zip(samples, prediction)]).to_csv(
                          predictions_path, index=False, encoding="utf-8-sig")
    return metrics
