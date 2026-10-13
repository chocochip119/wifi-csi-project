# PL — FPGA 연산 RTL

Zynq의 PL(Programmable Logic)은 **PS에서 준비한 INT8 CSI 특징을 병렬 처리하여 사람의 12관절 Pose를 추론**하는 하드웨어 연산부입니다. 현재 저장소에는 Pose CNN 원본 RTL뿐 아니라 **Location Ridge IP 관련 RTL과 테스트벤치**도 있습니다. 실제 기본 PC 위치 모델과 하드웨어 Ridge 통합 버전은 별개의 실행 구성이므로 구분합니다.

## 구현된 연산 블록

| 폴더 | 기능 | 상세 설명 |
|---|---|---|
| [`cnn/rtl/CNN_Encoder/`](cnn/README.md) | Conv1/Conv2, requantization, GELU LUT, Pool 및 중간 버퍼 | [CNN 처리 흐름](cnn/README.md) |
| [`cnn/rtl/FC/`](cnn/README.md) | Flatten, FIFO, FC1/FC2/FC3, 활성화, 24좌표 결과 RAM | [CNN 처리 흐름](cnn/README.md) |
| `cnn/rtl/Loader/` | INT8 모델 가중치·파라미터·LUT용 blob decoder와 메모리 | [CNN 제어](cnn/README.md) |
| `cnn/rtl/axi/` | AXI4-Lite 제어 레지스터 및 AXI master 인터페이스 | [인터페이스](../docs/interface.md) |
| `cnn/rtl/top/` | Pose CNN LOAD/INFER controller와 Top 연결 | [CNN 모듈](cnn/README.md) |
| `cnn/testbench/` | 개별 연산/전체 경로에 대한 Verilog 테스트 및 정수 벡터 | [검증 문서](cnn/README.md) |
| [`localization/rtl/`](localization/README.md) | Ridge 구역 분류용 **AXI4-Lite IP 원본 RTL** | [Ridge RTL](localization/README.md) |
| [`localization/testbench/`](localization/README.md) | Ridge 가중치·특징 입력 및 분류 결과 테스트벤치 | [Ridge RTL](localization/README.md) |
| `fft/` | 이전 CSI FFT 실험 코드 | 기본 Motion/Location 실행 경로 외 |

## CNN이 처리하는 데이터

```text
PS: RX5 INT8 [15,128,10]
           ↓
PL: RX별 공유 Encoder → 5,120개 특징
           ↓
    FC1(128) → FC2(128) → FC3(24)
           ↓
PS: 12관절의 24개 INT8 좌표 + output_scale
```

현재 Pose CNN 기준은 **RX 5대**, 입력 **19,200 bytes**, 출력 **24 bytes**입니다. 자세한 연산 단계, 파라미터 전달과 검증은 [`cnn/README.md`](cnn/README.md)에 정리했습니다.

## Vivado 통합과 소스 관리

- **수정 기준 RTL**: `pl/cnn/rtl/` 및 `pl/localization/rtl/`
- **Vivado 패키지 IP·XSA**: [`integration/`](../integration/README.md) — 원본 RTL과 별도의 통합용 소스 복사본입니다.
- **정수 기준**: [ML Pose INT8 계약](../ml/pose/INT8.md)
- **PS/PL 데이터·제어 레지스터**: [인터페이스](../docs/interface.md)

RTL을 바꾼 뒤에는 관련 IP 패키지·테스트·bitstream/XSA 적용 여부를 확인해야 합니다. 파일이 저장소에 있다는 사실만으로 보드에 해당 버전이 로드됐다고 단정하지 않습니다.
