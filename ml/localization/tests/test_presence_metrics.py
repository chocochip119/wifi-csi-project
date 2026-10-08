"""Six-class metrics and persistence contracts; synthetic labels only."""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from labels import CLASSES, LOCATION_CLASSES, EMPTY_LABEL, POINTS_CM, TASK
from location_core import DEFAULT_CONFIG
from location_model import (_metrics, _samples, _validate_bundle, load_model,
                             runtime_versions, SCHEMA)
from live_catalog import ModelCatalog, CATALOG_SCHEMA


def samples(labels):
    return [dict(point_id=label, source_id=i, path=f'synthetic_{i}.csv', split='test')
            for i, label in enumerate(labels)]


def bundle():
    """No estimator fit: only the persisted shape/label contract is exercised."""
    return dict(schema=SCHEMA, config=copy.deepcopy(DEFAULT_CONFIG), variant='amp_rssi',
                family='ridge', estimator=SimpleNamespace(n_features_in_=955, classes_=list(CLASSES)),
                scaler=SimpleNamespace(n_features_in_=955), phase_contract=None, feature_count=955,
                task=TASK, empty_label=EMPTY_LABEL, location_classes=list(LOCATION_CLASSES),
                classes=list(CLASSES), points_cm=copy.deepcopy(POINTS_CM))


class PresenceMetricsChecks(unittest.TestCase):
    def test_empty_false_positive_miss_and_location_have_distinct_denominators(self):
        truth = list(LOCATION_CLASSES) + ['empty', 'empty']
        # p02 missed as empty, p04 -> p01 (60 cm), p10 (p05 seated) -> p05 (same coordinate: 0 cm).
        prediction = ['p01', 'empty', 'p03', 'p01', 'p05', 'p06', 'p07', 'p08', 'p09', 'p05', 'empty', 'p01']
        result = _metrics(samples(truth), prediction)
        self.assertEqual(result['occupancy_binary_counts'],
                         dict(true_empty_pred_empty=1, true_empty_pred_occupied=1,
                              true_occupied_pred_empty=1, true_occupied_pred_occupied=9))
        self.assertEqual(result['occupancy_confusion_matrix'], [[1, 1], [1, 9]])
        self.assertEqual(result['empty_false_positive_rate'], .5)
        self.assertAlmostEqual(result['occupied_miss_rate'], .1)
        self.assertAlmostEqual(result['occupied_location_accuracy'], .7)
        self.assertEqual(result['occupancy_accuracy'], 10/12)
        self.assertEqual(result['nominal_point_error_sample_count'], 9)
        self.assertAlmostEqual(result['nominal_point_error_coverage'], .9)
        self.assertAlmostEqual(result['mean_nominal_point_error_cm'], 60/9)
        self.assertEqual(result['per_point_recall']['p10'], 0.)
        self.assertEqual(result['confusion_labels'], list(CLASSES))
        self.assertEqual(np.asarray(result['confusion_matrix']).shape, (11, 11))
        self.assertNotIn('empty', POINTS_CM)

    def test_all_empty_predictions_have_no_distance_and_occupied_misses_stay_wrong(self):
        result = _metrics(samples(CLASSES), ['empty']*len(CLASSES))
        self.assertEqual(result['occupied_miss_rate'], 1.)
        self.assertEqual(result['occupied_location_accuracy'], 0.)
        self.assertEqual(result['empty_false_positive_rate'], 0.)
        self.assertIsNone(result['mean_nominal_point_error_cm'])
        self.assertEqual(result['nominal_point_error_sample_count'], 0)
        self.assertEqual(result['nominal_point_error_coverage'], 0.)
        # JSON reports must not contain NaN or invented zero-centimetre error.
        json.dumps(result, allow_nan=False)

    def test_empty_recall_and_six_class_balanced_accuracy_include_empty(self):
        prediction = list(LOCATION_CLASSES) + ['p01']
        result = _metrics(samples(CLASSES), prediction)
        self.assertEqual(result['occupied_location_accuracy'], 1.)
        self.assertEqual(result['occupied_miss_rate'], 0.)
        self.assertEqual(result['empty_false_positive_rate'], 1.)
        self.assertAlmostEqual(result['balanced_accuracy'], 10/11)
        self.assertEqual(result['per_point_recall']['empty'], 0.)

    def test_missing_empty_is_not_silently_scored_as_five_class(self):
        with self.assertRaisesRegex(ValueError, '11클래스'):
            _metrics(samples(LOCATION_CLASSES), LOCATION_CLASSES)
        with self.assertRaisesRegex(ValueError, '11클래스'):
            _samples({'samples': samples(LOCATION_CLASSES)}, 'test')

    def test_bundle_requires_all_six_classes_and_empty_has_no_coordinate(self):
        _validate_bundle(bundle())
        bad = bundle(); bad['estimator'].classes_ = list(LOCATION_CLASSES)
        with self.assertRaisesRegex(ValueError, '11클래스'):
            _validate_bundle(bad)
        bad = bundle(); bad['points_cm']['empty'] = [90, 90]
        with self.assertRaisesRegex(ValueError, '좌표 계약'):
            _validate_bundle(bad)
        bad = bundle(); bad['schema'] = 'csi_studio_model_v1'
        with self.assertRaisesRegex(ValueError, '새로 학습'):
            _validate_bundle(bad)

    def test_legacy_sidecar_rejected_before_deserialization(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'old.joblib'; path.write_bytes(b'no pickle is needed')
            path.with_suffix('.joblib.metadata.json').write_text(json.dumps({
                'schema': 'csi_studio_model_v1', 'versions': runtime_versions(),
                'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}), encoding='utf-8')
            with patch('location_model.joblib.load', side_effect=AssertionError('must not unpickle')) as loader:
                with self.assertRaisesRegex(ValueError, '새로 학습'):
                    load_model(path)
                loader.assert_not_called()

    def test_catalog_and_sidecar_require_six_class_metadata(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); (root/'models').mkdir()
            model = root/'models'/'new.joblib'; model.write_bytes(b'synthetic model bytes')
            digest = hashlib.sha256(model.read_bytes()).hexdigest()
            entry = dict(id='candidate', path='models/new.joblib', sha256=digest, selected=True)
            catalog = dict(schema=CATALOG_SCHEMA, versions=runtime_versions(), task=TASK,
                           classes=list(CLASSES), location_classes=list(LOCATION_CLASSES),
                           empty_label=EMPTY_LABEL, points_cm=POINTS_CM, models=[entry], default_id='candidate')
            sidecar = dict(schema=SCHEMA, versions=runtime_versions(), task=TASK,
                           classes=list(CLASSES), empty_label=EMPTY_LABEL, sha256=digest)
            (root/'model_catalog.json').write_text(json.dumps(catalog), encoding='utf-8')
            model.with_suffix('.joblib.metadata.json').write_text(json.dumps(sidecar), encoding='utf-8')
            result = ModelCatalog(root).verify_all()
            self.assertTrue(result['hashes_match'])
            sidecar['classes'] = list(LOCATION_CLASSES)
            model.with_suffix('.joblib.metadata.json').write_text(json.dumps(sidecar), encoding='utf-8')
            with self.assertRaisesRegex(ValueError, '11클래스'):
                ModelCatalog(root).verify_all()
            catalog['schema'] = 'csi_studio_catalog_v1'
            (root/'model_catalog.json').write_text(json.dumps(catalog), encoding='utf-8')
            with self.assertRaisesRegex(ValueError, '새로 학습'):
                ModelCatalog(root)


if __name__ == '__main__':
    unittest.main(verbosity=2)
