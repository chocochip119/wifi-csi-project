# ML — 자세·위치 모델 학습과 배포 준비

이 폴더는 **수집한 Wi-Fi CSI로 모델을 학습하고, 실제 실행 경로에서 사용할 가중치·정수 입력·검증 데이터를 만드는 곳**입니다. 모델 학습 코드와 FPGA/PC에서 실제로 추론하는 코드는 분리되어 있습니다.

## 구현 기능

| 영역 | 입력과 처리 | 출력·연결 |
|---|---|---|
| [`pose/`](pose/README.md) | CSI CSV 확인·전처리 → **RX5 15채널 Pose CNN 학습** → INT8 calibration/export | FPGA용 가중치 blob, 입력·출력 golden, 12관절 24좌표 |
| [`localization/`](localization/README.md) | RX5의 CSI 진폭·RSSI에서 **2초 윈도우 955특징** 추출 → kNN/Ridge/MLP 비교·학습·평가 | 9개 구역 + P10 앉기 + 사람 없음의 11클래스, PC용 Portable Ridge 모델 |
| `respiration/` | 호흡 분석 아이디어 관련 디렉터리 | 현재 기본 Motion/Location 실행에는 포함하지 않음 |

### Pose — 추론용 INT8 데이터 만들기

```text
CSI 데이터셋 → base/delta/mask [15,128,10] → CNN 학습
           → INT8 calibration → 가중치 blob + golden
           → pl/cnn + ps 앱에서 FPGA Pose 추론
```

학습은 [Colab v5 notebook](pose/training/wifi_csi_6people_5rx_colab_zip_v5_finer_training.ipynb)을 기준으로 하고, INT8 반올림·포화·Pool 규칙은 [INT8 계약](pose/INT8.md)을 사용합니다. 실제 모델과 FPGA 출력의 비교를 위해 **동일한 체크포인트에서 가중치·scale·golden을 함께** 생성합니다.

### Location — 구역 분류 모델 만들기

```text
RX5 CSI/RSSI 데이터셋 → 2초 통계 특징(955개)
                   → 모델 학습·평가 → Portable Ridge NPZ/JSON
                   → ps/src/loc_ridge.c 에서 실시간 구역 분류
```

위치는 연속적인 X/Y 추정이 아니라 **P01~P09 + P10(중앙 앉기) + empty** 분류입니다. 학습·평가/데이터 형식은 [Location README](localization/README.md), 실제 실행·RX 확인은 [PS](../ps/README.md) 및 [PC Backend](../pc/backend/README.md)에 있습니다.

## 모델 적용·검증 문서

- **자세 전처리·학습·golden:** [`pose/README.md`](pose/README.md) / [`pose/INT8.md`](pose/INT8.md)
- **위치 학습·모델 내보내기:** [`localization/README.md`](localization/README.md)
- **RTL 연산 구성:** [FPGA CNN](../pl/cnn/README.md)
- **PS·PC 실제 실행:** [PS](../ps/README.md) / [Backend](../pc/backend/README.md)

CSV 원본과 학습 run/cache는 로컬·팀 공유 환경에서 관리하며, 이 저장소의 실행 NPZ·JSON과 golden/테스트 자료를 원본 데이터셋 전체로 간주하지 않습니다.
