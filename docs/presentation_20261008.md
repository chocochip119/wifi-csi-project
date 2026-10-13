# WiSensing 발표자료 기반 기술 해설 및 확인 사항

> 기준: `2조_PPT_1008_제본용.pptx` (2026-10-08 발표본, 63장). 발표 자료의 주장과 저장소 문서가 서로 다른 경우에는 둘을 구분합니다. 이 문서는 실행 코드나 실보드 재검증 결과를 대신하지 않습니다.

## 1. 프로젝트 소개
WiSensing은 Wi-Fi CSI(Channel State Information)의 시간·공간적 변화를 이용해 사람의 동작과 실내 구역을 추정하는 시스템입니다. **최종 추론 단계에서 카메라 영상은 사용하지 않으며**, 12개 관절의 2D 좌표(Motion)와 9개 위치 구역(Location)을 화면에 보여주는 것을 목표로 합니다. 자세 모델의 학습 라벨은 촬영 영상과 동기화하여 마련했습니다.

**과장 주의:** 벽/장애물 뒤 감지를 모든 환경에서 보장하거나 영상 기반 인식보다 언제나 우수하다고 단정하면 안 됩니다. 설치 환경·배치·학습 분포에 영향을 받는 시스템입니다.

## 2. 발표본의 전체 흐름
1. ESP32 송신기(TX)가 수집을 조정하고 복수 수신기(RX)가 채널 정보를 관측합니다.
2. TX가 수집 사이클을 정리하고 USB CDC ACM을 통해 Zynq PS로 전달합니다. `/dev/ttyACM0`는 Linux 장치 이름이며 이 구간 전체를 UART라고 부르면 부정확합니다.
3. PS가 프레임 길이/checksum 검사, 누락 처리, 입력 특징 및 시간 윈도우를 구성합니다.
4. PL(FPGA) CNN은 12개 관절 (x,y) 24개 값을 추론합니다.
5. **현재 루트 `ps/`·`pc/backend/` 기준:** PS가 CSI를 TCP 5000, Pose를 TCP 5001로 전송하고 PC의 Portable Ridge가 위치를 분류합니다.
6. **별도 시험판 `ps_location/`:** 위치 모델을 PS C로 옮기고 TCP 5000 단일 포트(type 5 Location 포함)를 시험합니다. 루트 구현에 적용된 것으로 혼동하지 않습니다.
7. PC가 Motion/Location을 통합해 표시합니다.

![시스템 아키텍처](assets/wisensing-architecture.svg)

## 3. Motion: CSI → 12관절
- 발표본 입력: RX 5대 × (base, delta, mask) → INT8 `[15, 128, 10]` = 19,200 bytes.
- 각 RX의 3채널을 CNN Encoder에 제공. Conv1 `3→16` (5×3), Conv2 `16→32` (3×3), Adaptive pooling 결과 RX당 1,024특징.
- Flatten `5×1,024=5,120` → FC1 128 → FC2 128 → FC3 24. 마지막 24개는 12관절의 x/y.
- RTL: Encoder, FC, Loader, AXI와 Top은 `pl/cnn/rtl/`; 실제 배포 IP는 `integration/`의 패키지 소스와 버전을 맞춰야 합니다.
- 발표 자료는 Conv에 16병렬 MAC, FC에 8병렬 MAC을 사용한다고 설명합니다.
- INT8 출력은 학습 모델과 연동된 `output_scale`로 복원하며, UI 좌표계와 자동으로 같은 값이라고 가정하지 않습니다.
- 학습 때 카메라 라벨을 사용하지만 실행할 때는 영상을 입력하지 않는다는 점을 설명에 유지합니다.

### 발표 시 제시한 평가·최적화 수치
| 항목 | 발표 자료 수치 | 해석·주의 |
|---|---:|---|
| Motion 검증 Balanced MAE | 0.016581 (Epoch 2) | 학습 실행/평가 기준과 함께 읽을 것 |
| RX Encoder 직렬→병렬 처리 | 22.5ms → 5.5ms | 특정 개선 비교, 최종 시스템 end-to-end 지연과 다름 |
| 타이밍 WNS | -3.583ns → +1.191ns | 발표 당시 조건(100MHz)에서 제시 |
| PS 1코어 대비 가속 | 29.7배 | 동일 입력·측정 조건이 필요 |
| PS 2코어 대비 가속 | 약 18배 | 동일 입력·측정 조건이 필요 |
| FPGA 추론 시간 | 6.52ms | 발표본 비교 수치, CSI 수집/전송/UI 지연 제외 |
| 추론 처리량 | 초당 약 153윈도우 | 6.52ms 역수와 대체로 일치 |
| Requant 숫자 불일치 | 2,000건 중 785→0 | 65→66bit 확장, 극단 shift 처리 |
| Encoder UVM | 98개 시나리오 PASS | 발표본 검증 기록: Directed 88, Random 10 |

**중요:** `ps/README.md`의 2026-09-30 보드 측정(약 23~24ms/윈도우)은 다른 시점/구성입니다. 6.52ms와 동일 실험으로 취급하거나 현재 보드에서 재현됐다고 주장하지 않습니다. 최신 RTL bitstream/XSA·ARM/PetaLinux 전체 빌드의 적용 여부도 별도로 검증해야 합니다.

## 4. Location: CSI → 9개 구역
- 발표본: 6명, 9개 위치·앉기·빈 공간 데이터를 수집하고 시간대 단위로 학습/검증/시험을 분리했습니다.
- RX별 CSI 진폭과 RSSI를 2초 윈도우에 요약해 955개 특징을 만듭니다.
- 규칙 기반 방식과 MLP/kNN/Ridge 등을 비교하고 Ridge를 채택한 것으로 발표했습니다.
- 분류 대상은 9개 위치, 앉기, 빈 공간이며 **연속적인 좌표 회귀가 아닌 클래스 분류**입니다.
- 발표본의 Balanced Accuracy 97.78%는 지정된 검증 시간대 수치입니다. 다른 날짜/공간에서의 일반화 성능을 보장하지 않습니다.
- `ps_location/`의 2026-10-12 Ridge 모델은 발표 당시 사용 모델과 버전이 다릅니다. 당시 수치와 이 시험판의 동작 결과를 직접 혼합하지 않습니다.

## 5. 통신·배포
| 경계 | 루트 구현 | 별도 시험판 |
|---|---|---|
| ESP32 → PS | USB CDC ACM / CSI cycle | 동일 |
| PS → PC 위치 | TCP 5000 CSI/STATUS/ACK | TCP 5000 Location/STATUS/ACK, CSI는 옵션 |
| PS → PC 자세 | TCP 5001 Pose | TCP 5000 Pose |
| 위치 연산 | PC Portable Ridge | PS C Ridge |
| 자세 연산 | FPGA CNN | FPGA CNN |

루트의 WISE 헤더는 24바이트·wire version 2이며, 자세 페이로드는 40바이트입니다. 두 구현의 패킷 규격/연결 방식은 호환된다고 가정하지 마세요. 각각 `docs/ps_pc_protocol.md`와 `ps_location/docs/ps_pc_protocol.md`를 참조합니다.

## 6. 발표 그림·사진 사용 가이드
발표의 실제 촬영 장면, CSI 수신기 배치, 신호 흐름, CNN 내부 경로, 모션/위치 UI 결과는 설명력이 높습니다. 원본 PPT에 사진·스크린샷이 다수 포함되어 있지만 **자동으로 공개 저장소에 재배포하지 않았습니다.** 사진 저작권과 팀원의 얼굴/개인정보를 검토한 뒤 `docs/assets/`에 선별한 파일을 올리고 README에서 상대 경로로 링크하세요. 현재 README의 SVG는 원본 사진이 아니라 설명용 도식입니다.

- 우선 추천: 전체 설치 환경 사진(민감 요소 확인), 수신기 배치 사진, Motion/Location 실제 UI 캡처, Encoder/FC 구조도.
- 측정 성능 그래프에는 측정 일자, 장치, 클록, 모델 버전을 함께 표기합니다.
- 발표본의 CCTV 범죄 통계 등 외부 수치는 원출처·표본/정의를 재검증하기 전까지 README 대표 성과로 사용하지 않습니다.

## 7. 코드·문서 탐색
- [메인 README](../README.md)
- [프로젝트 구조](repository_structure.md) · [아키텍처](architecture.md) · [인터페이스](interface.md)
- [ESP32](../esp32/README.md) · [PS](../ps/README.md) · [PL](../pl/README.md)
- [ML](../ml/README.md) · [PC](../pc/README.md) · [Integration](../integration/README.md)
- [PS 위치 시험판](../ps_location/README.md)
- [통합 실행](bringup.md) · [통신 규격](ps_pc_protocol.md) · [INT8](../ml/pose/INT8.md)

## 8. 남은 사실 확인
1. 발표본 6.52ms/29.7배에 해당하는 보드·bitstream·테스트 로그 연결.
2. 최종 배포 이미지와 코드 리비전이 일치하는지 확인.
3. PS 자동 시작 서비스가 실제 rootfs에 설치되어 있는지 확인(소스 머지 여부와 별개).
4. PPT의 실물 사진/시연 이미지를 공개 가능한 것만 선별.
5. 발표본과 이후 `ps_location/`의 모델/통신 차이를 통합하려면 별도 마이그레이션 PR 필요.
