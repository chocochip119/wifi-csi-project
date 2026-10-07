from pathlib import Path
import numpy as np
from localization.portable_ridge import PortableRidge
from localization.fivepoint_live import LiveInferenceEngine

BASE = Path(__file__).resolve().parents[1]

def test_all_40_fixture_windows_features_scores_and_labels():
    model = PortableRidge(BASE/'localization/models/ridge_portable.npz')
    with np.load(BASE/'tests/fixtures/selfcheck_fixture.npz', allow_pickle=False) as data:
        features = []
        for i, count in enumerate(data['cycle_counts']):
            cycles = [model.cycle_arrays({rx:(data['rssi'][i,j,rx],data['raw_csi'][i,j,rx].tobytes())
                      for rx in range(5)}) for j in range(int(count))]
            features.append(model.window_features(cycles))
        np.testing.assert_allclose(features,data['features'],atol=1e-12,rtol=1e-12)
        np.testing.assert_allclose(model.decision_function(features),data['sklearn_scores'],atol=1e-9,rtol=1e-9)
        np.testing.assert_array_equal(model.predict(features),data['sklearn_labels'])
    engine = LiveInferenceEngine(model.as_studio_bundle())
    assert engine.config['window_s'] == 2 and engine.config['stride_s'] == 0.5
