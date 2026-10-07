# ML — 학습과 정수 참고 구현

| 위치 | 역할 / 상태 |
|---|---|
| [pose](pose/README.md) | CSI CSV 전처리, Pose 학습 notebook, INT8 reference/golden, 회귀 테스트 |
| [localization](localization/README.md) | 위치 모델 학습/검증/분석용 자리; 전체 학습 원본은 현재 미포함 |
| `respiration/` | 호흡 학습 코드가 없는 자리 |

Pose 모델 학습은 Colab v5, 실제 Pose 추론은 FPGA에서 수행합니다. 위치 실시간 실행은 [pc/backend/localization](../pc/backend/README.md)에 있습니다. 학습/분석 파일을 Backend의 실행 진입점으로 사용하지 않습니다.

## 모델을 보드에 반영할 때

Pose export는 weights NPZ·metadata JSON·RX5 blob·input/pose golden을 같은 학습 모델에서 생성합니다. PS의 input_scale과 PL의 output_scale을 함께 맞추고 새 RTL/가중치로 실제 보드 비교를 진행하세요. 현재 규칙과 파일 계약은 [INT8](pose/INT8.md), 전체 순서는 [통합 실행](../docs/bringup.md)에 있습니다.

CSV 및 새 학습 runs/cache는 실행 환경에 저장합니다. 저장소의 PC Portable Ridge NPZ/JSON과 회귀 fixture는 전달된 모델 계약을 확인하기 위한 실행 자료입니다.
