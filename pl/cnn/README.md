# CNN RTL 구성

기본 통합 top `rtl/top/pose_cnn.v`의 `RX=5`, FC `RX_NUM=5`를 기준으로 설명합니다. 일부 하위 블록/단위 TB의 기본 RX=3은 상위 모듈에서 전달한 파라미터로 바뀝니다. 실제 모델과 PS는 RX5를 사용합니다.

## 연산과 입력

입력은 batch를 제외한 INT8 `[15,128,10]`입니다. 채널은 `ch=rx+5*ic`, `ic=0/1/2`가 base/delta/mask입니다. 각 RX에서 해당 세 채널을 뽑아 같은 Encoder 가중치로 계산합니다.

| 단계 | 크기 / 연산 | 원본 위치 |
|---|---|---|
| Conv1 | `3→16`, kernel `5×3`, padding `2×1` | `rtl/CNN_Encoder/Conv_MAC.v` |
| Requant + GELU | INT8 포화 후 LUT | `requant_stage.v`, `gelu_stage.v` |
| Conv2 | `16→32`, kernel `3×3`, padding `1×1` | `rtl/CNN_Encoder/Conv_MAC.v` |
| Requant + GELU + Pool | Pool 출력 `8×4`, RX당 1024 bytes | `rtl/CNN_Encoder/Pool.v` |
| Flatten / FC1 | RX5의 5120개 특징 → 128 | `rtl/FC/fc_top.v`, `rtl/FC/Flatten/flatten.v` |
| FC2 / FC3 | `128→128→24`, FC1/2 뒤 GELU | `rtl/FC/controller/fc_controller.v`, `rtl/FC/Common/` |
| 출력 | INT8 24 bytes, 별도 output_scale | `rtl/FC/RAM/pose_buffer.v` |

학습 모델의 BN은 export에서 folding된 가중치/bias로 반영하며 RTL에 별도 BN 단계가 없습니다. Pool/FC 정수 반올림은 [팀 INT8 계약](../../ml/pose/INT8.md)을 사용합니다.

## 제어와 가중치

`rtl/Loader/`가 RX5 v2 blob(685,136 bytes)의 가중치·bias·multiplier·shift·LUT를 로드합니다. `rtl/top/pose_cnn_ctrl.v`는 LOAD/INFER와 DDR DMA를 제어합니다. AXI-Lite CSR 정의는 [PS 레지스터 헤더](../../ps/include/pose_cnn_regs.h), 외부 연결은 [Integration](../../integration/README.md)을 참조합니다.

`pose_cnn`은 내부 core입니다. 패키지 IP top은 `integration/pose_cnn_1.1/src/pose_cnn_v1_0.v`이며 module 이름의 v1_0과 패키지 버전 1.1을 혼동하지 마세요.

## 검증

- [Encoder 단위/통합 TB](testbench/CNN_Encoder/README.md)
- [반올림 회귀 및 RX5 전체 golden TB](testbench/rounding/README.md)
- FC requant 단위 검증과 FC/controller/loader를 포함한 전체 경로 검증은 `rounding/`의 TB에 포함됩니다. 별도 FC/top testbench 디렉터리는 현재 없습니다.

소스와 golden의 일치는 실제 Vivado 타이밍/자원·보드 정확도 확인과 구분합니다. 기존 XSA/시험 벡터의 상태는 [통합 자료](../../integration/README.md), 실제로 수행한 검사는 [점검 기록](../../docs/reviews/2026-10-07-pc-integration.md)에 기록합니다.
