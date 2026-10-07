# Pose 학습·전처리·INT8

현재 RX5는 base/delta/mask 15채널, subcarrier 128개, window 10개를 입력으로 사용합니다. 출력은 12관절의 x/y 24개입니다.

| 파일 | 역할 |
|---|---|
| [prepare.py](prepare.py) / [PREPARE.md](PREPARE.md) | CSV 검사, HT-LTF remap, base/delta/mask NPZ 생성 |
| [int8_reference.py](int8_reference.py) / [INT8.md](INT8.md) | RTL과 같은 requant/Pool 정수 규칙, CPU 기준 추론 |
| [export_golden.py](export_golden.py) | RX5 window 하나의 19,200-byte 입력·24-byte 기대 출력·중간값·manifest 생성 |
| [v5 notebook](training/wifi_csi_6people_5rx_colab_zip_v5_finer_training.ipynb) | 현재 ZIP 기반 학습, calibration/export, blob pack, golden 생성 |
| [v4 notebook](training/wifi_csi_6people_5rx_colab_zip_v4.ipynb) | 이전 학습 버전 보관; 현재 팀 INT8 계약 적용은 v5 기준 |
| `tests/` | CSI/trigger/mask/CLI와 정수 경계·Pool·IP 소스 회귀 |

## 시작 순서

1. 수집 CSV/ZIP의 RX 순서·형식과 세션/사람/동작 이름을 확인합니다.
2. Colab v5의 경로와 학습 설정을 입력하고 셀 순서대로 실행합니다.
3. 빈/손상 CSI mask 수정은 기존 NPZ에 소급되지 않으므로 CSV에서 cache를 다시 생성합니다.
4. 학습한 best checkpoint를 calibration/export하고 RX5 blob을 pack합니다.
5. 비어 있지 않은 test split이 있을 때 golden 셀을 실행합니다. test split이 없으면 golden 실행 조건을 먼저 맞춰야 합니다.
6. [RTL/보드 비교](INT8.md)와 [PS 실행](../../ps/README.md)에 동일한 모델·scale을 적용합니다.

v5는 모델/학습/calibration 코드를 외부 `ziziccc/wifi-csi-pose` commit `4ee1a900bbd8c22fc9d3dc4c2c01845d82ab7fee`에서, 팀 prepare/INT8/golden을 commit `c0dedf23f785c0346b6e6ec4edd2c5b94880a22d`에서 고정 로드합니다. main의 파일을 바꿨다고 notebook이 자동으로 새 commit을 쓰지는 않습니다.

Standalone `prepare.py` 기본 RX는 3입니다. RX5 직접 전처리에는 `--node-count 5`를 지정합니다. 기본 HT-LTF 출력은 프레임별 `[N,15,128]`이며 window를 묶으면 `[B,15,128,10]`입니다. v5 Dataset은 forward_fill/max_gap=3을 사용합니다. PS의 윈도우 연속성 정책과 최종 데이터 분할은 [점검 기록](../../docs/reviews/2026-10-07-pc-integration.md)을 참고하세요.

## 검증 실행

저장소 루트에서 NumPy와 pytest가 필요합니다.

```bash
python -m pytest ml/pose/tests -q
```

이 검증은 합성 CSV/정수 입력을 사용합니다. 학습 완료, 최종 모델 정확도 또는 새 장소의 일반화 성능을 확인한 것으로 해석하지 않습니다.
