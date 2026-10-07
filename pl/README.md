# PL — FPGA CNN

현재 하드웨어 원본은 [cnn](cnn/README.md) 아래에 있습니다. 자세 추론을 담당하며 위치 추론은 PC Backend에서 실행합니다.

| 위치 | 내용 |
|---|---|
| `cnn/rtl/CNN_Encoder/` | Conv1/Conv2, requant, GELU, Pool, buffer |
| `cnn/rtl/FC/` | Flatten, FC1/2/3, FIFO, 공통 연산, 결과 RAM |
| `cnn/rtl/Loader/` | 가중치 blob decoder/loader와 RAM |
| `cnn/rtl/axi/` | AXI4-Lite CSR와 AXI master wrapper |
| `cnn/rtl/top/` | pose_cnn core, LOAD/INFER controller |
| `cnn/testbench/` | 블록/통합 testbench와 Python 벡터 생성 |
| `fft/rtl/test.v` | 이전 FFT 실험 코드; 현재 통합 경로에 포함되지 않음 |
| `localization/` | 이전 PL 위치 실험용 골격 |

원본 RTL 수정은 `cnn/rtl/`에서 시작하고 [패키지 IP](../integration/README.md)의 소스 복사본과 함께 맞춥니다. 보드 적용에는 Vivado IP 재패키징·합성/구현·bitstream/XSA 재생성이 필요합니다.

현재 통합 기준은 RX5, 입력 INT8 `[15,128,10]`, Flatten 5120, 출력 24좌표입니다. [INT8 계약](../ml/pose/INT8.md), [인터페이스](../docs/interface.md), [검증 기록](../docs/reviews/2026-10-07-pc-integration.md)을 참고하세요.
