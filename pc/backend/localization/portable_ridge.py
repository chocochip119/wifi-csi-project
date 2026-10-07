"""Version-independent Ridge inference from the exported .npz (numpy only).

Same math as the saved Studio bundle (StandardScaler -> RidgeClassifier):
    z = (x - mean) / scale ;  score = z @ coef.T + intercept ;  label = classes_[argmax]
Features follow fivepoint_core (amp_rssi): per cycle, RX 0..4 in order, 384 CSI
bytes = 192 (imag, real) int8 pairs, drop the first 2 pairs, amplitude =
hypot(imag, real); window feature = [mean amplitude (950), mean RSSI (5)].

Windowing (2 s, 10 Hz selection, >= 10 cycles, >= 1 s span) is NOT here; it is
the live engine's job (fivepoint_core.make_windows / LiveInferenceEngine).
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np

SCHEMA = "wise_portable_ridge_v1"


class PortableRidge:
    def __init__(self, path):
        path = Path(path)
        meta_path = path.with_suffix(".json")
        self.meta = json.loads(meta_path.read_text(encoding="utf-8"))
        if self.meta.get("schema") != SCHEMA:
            raise ValueError("not a portable ridge export")
        if hashlib.sha256(path.read_bytes()).hexdigest() != self.meta["npz_sha256"]:
            raise ValueError("npz SHA-256 mismatch")
        with np.load(path, allow_pickle=False) as data:
            self.coef = data["coef"].astype(np.float64)
            self.intercept = data["intercept"].astype(np.float64)
            self.mean = data["scaler_mean"].astype(np.float64)
            self.scale = data["scaler_scale"].astype(np.float64)
            self.classes_ = [str(c) for c in data["estimator_classes"]]
        self.config = self.meta["config"]
        self.classes = self.meta["bundle_classes"]
        self.points_cm = self.meta["points_cm"]
        self.n_features = self.coef.shape[1]
        n_rx = len(self.config["rx_ids"])
        self.pairs_per_rx = self.config["csi_len"] // 2 - self.config["drop_pairs"]
        if self.n_features != n_rx * self.pairs_per_rx + n_rx or self.config["variant"] != "amp_rssi":
            raise ValueError("feature contract mismatch")

    # -- features -------------------------------------------------------
    def cycle_arrays(self, records):
        """records: {rx_id: (rssi, csi_bytes)} for one complete cycle.
        Returns (imag[950], real[950], rssi[5]) in contract order. Missing RX raises."""
        imag, real, rssi = [], [], []
        for rx in self.config["rx_ids"]:
            value, csi = records[rx]
            if len(csi) != self.config["csi_len"]:
                raise ValueError(f"RX{rx}: CSI must be {self.config['csi_len']} bytes")
            iq = np.frombuffer(bytes(csi), dtype=np.int8).astype(np.float64).reshape(-1, 2)
            iq = iq[self.config["drop_pairs"]:]
            imag.append(iq[:, 0])
            real.append(iq[:, 1])
            rssi.append(float(value))
        return np.concatenate(imag), np.concatenate(real), np.asarray(rssi)

    def window_features(self, cycles):
        """cycles: list of (imag, real, rssi) for one window -> feature vector (955,)."""
        imag = np.stack([c[0] for c in cycles])
        real = np.stack([c[1] for c in cycles])
        rssi = np.stack([c[2] for c in cycles])
        return np.concatenate([np.hypot(imag, real).mean(axis=0), rssi.mean(axis=0)])

    # -- model ----------------------------------------------------------
    def decision_function(self, features):
        x = np.atleast_2d(np.asarray(features, dtype=np.float64))
        if x.shape[1] != self.n_features or not np.isfinite(x).all():
            raise ValueError("feature shape/finite check failed")
        return ((x - self.mean) / self.scale) @ self.coef.T + self.intercept

    def predict(self, features):
        """Labels (strings). Column j of decision_function is classes_[j], NOT classes[j]."""
        return np.asarray(self.classes_)[np.argmax(self.decision_function(features), axis=1)]

    # -- optional: plug into the unchanged Studio live engine -------------
    def as_studio_bundle(self):
        """Duck-typed bundle for fivepoint_live/fivepoint_model.predict_windows
        (needs those modules importable, but not the training library versions)."""
        owner = self

        class _Scaler:
            n_features_in_ = owner.n_features

            def transform(self, x):
                return (np.asarray(x, dtype=np.float64) - owner.mean) / owner.scale

        class _Estimator:
            n_features_in_ = owner.n_features
            classes_ = np.asarray(owner.classes_)

            def predict(self, z):
                scores = np.asarray(z, dtype=np.float64) @ owner.coef.T + owner.intercept
                return self.classes_[np.argmax(scores, axis=1)]

        m = self.meta
        return {"schema": m["studio_schema"], "config": dict(self.config), "variant": m["variant"],
                "family": m["family"], "estimator": _Estimator(), "scaler": _Scaler(), "phase_contract": None,
                "classes": list(self.classes), "points_cm": {k: list(v) for k, v in self.points_cm.items()},
                "feature_count": self.n_features, "task": m["task"], "empty_label": m["empty_label"],
                "location_classes": list(m["location_classes"])}
