# 2026-10-19 전체 GitHub 저장소 점검 기록

> 기준: `main` 커밋 `944785aefbbb59f269e5e5c5220433630cd985b7` (PR #80·#81·#82 병합 후). 이 문서는 **소스/설정/문서 및 호스트 환경 검토 결과**입니다. 실보드에서 신규 rootfs를 설치하거나 측정한 보고서가 아닙니다.

## 점검 범위

- ESP32 TX/RX 펌웨어, USB CSI 프레이밍, RX RUN/STATUS 처리
- `ps/` C 수신/위치 Ridge/FPGA 제어/TCP 전송, `petalinux/` recipe·init 스크립트
- `pl/` CNN 및 Ridge RTL, `integration/` IP 패키지/XSA, `ml/` 학습·양자화·Portable Ridge 메타데이터
- `pc/backend/` 프로토콜·FastAPI·위치 안정화·RX 배치 및 `pc/frontend/` 메인 화면·관리자·3D 정책·테스트
- 이전 비교판 `ps_location/`, `ps_onlysw/`, `scripts/`, 저장소의 기존 **Markdown 50개** 및 발표 PPTX의 시각자료 적합성

## 기본 동작과 PR 반영 확인

| 항목 | 현행 구현 | 근거 |
|---|---|---|
| 수집 | TX 1 + RX 5, RX→TX UDP 3333, TX→PS USB CDC ACM | [ESP32](../../esp32/README.md) |
| 위치 | PS C Ridge, RX5 955특징·11클래스, `run_20261013_122537_33a43334` 원본 모델 | [PS](../../ps/README.md) · [모델 메타데이터](../../pc/backend/localization/models/localization/ridge_portable.json) |
| Pose | FPGA INT8 CNN, 15×128×10 입력·12관절 x/y 24값 | [CNN](../../pl/cnn/README.md) |
| PC 입력 | PS 단일 TCP 5000에 Location/Pose/STATUS/ACK | [프로토콜](../ps_pc_protocol.md) |
| #80 | TX RUN 4/5 상황에서 RX0~4 준비 후 PS 자동 WAIT→RUN 복구, Backend RUN/LIVE/SAVED 진단 | [Backend](../../pc/backend/README.md) |
| #81 | `wisensing-autostart`·`update-rc.d`, PetaLinux의 기존 SD FAT 마운트 재사용/재시도 | [자동실행](../../ps/petalinux/AUTOSTART.md) |
| #82 | Backend **서로 다른 위치 윈도우 2회 연속 확인**, Frontend 위치 보기와 P05 고정 모션 보기 분리 | [Backend](../../pc/backend/README.md) · [Frontend](../../pc/frontend/README.md) |

## 이 점검에서 실행한 검증

| 검증 | 결과 | 범위·한계 |
|---|---|---|
| `cd pc/frontend && npm test` | **154/154 통과** | 호스트 Node 테스트, 실제 GLTF/보드 육안 점검 아님 |
| `cd pc/frontend && npm run build` | **PASS** | Vite 8.3.3, 메인 JS 약 **722KB** 크기 경고 |
| Markdown 상대 링크 검사 | 최종 문서 **349개 링크 중 누락 0개** | 저장소 추적 경로 기준, 외부 URL 도달성 검사 아님 |
| PS C 호스트 구문 검사 | **PASS** | GCC `-std=c11 -O2 -Wall -Wextra -fsyntax-only`, `loc_ridge`/replay·CSI 파서·TCP 서버; 보드 링크/실행 아님 |
| Python Backend `pytest` | **미실행** | 임시 점검 환경에 `pytest` 미설치 |
| PetaLinux/ESP-IDF/Vivado·실보드 | **미실행** | 타깃 빌드 도구·Zybo·ESP32 실물 없음 |

## 남아 있는 위험과 후속 개선

1. **부팅 자동실행 실제 검증이 최우선.** #81 수정은 저장소 코드에 있지만 사용 중인 `image.ub`/INITRD가 교체되지 않았다면 적용되지 않습니다. 실제 부팅 후 `/etc/init.d/wisensing-autostart status`, `/tmp/wisensing-autostart.log`, `ps`, `/proc/mounts`를 확인하세요. 기존 SD 전체 재작성 대신 **현재 이미지에 수정본이 포함됐는지** 먼저 확인합니다.
2. **RX5 자동 복구의 장비 검증.** RX 네 대로 RUN 시작 → 다섯 번째 늦게 접속 → STATUS LIVE/SAVED 5/5 → `RX5 RECOVERY` → RUN 5/5 → 유효 cycle → 위치 확정 2회 순서와 지연 시간을 실제 ESP32로 기록해야 합니다.
3. **위치 모델 일반화.** 현재 PS 모델의 원본 run은 10/13이지만, 저장된 메타데이터에는 `test_evaluated=false`입니다. 10/08 학습 결과를 배포 모델 성능으로 혼용하거나 사람·날짜·환경 전체로 확대 해석하면 안 됩니다. 학습 RX MAC도 모델에 고정되지 않아 운영자 배치 승인이 필요합니다.
4. **FPGA Ridge v1.1 실보드 미검증.** `pl/localization/`의 XSim/구현 기록과 `integration/`의 XSA는 기본 PS C Ridge의 실행 증거가 아닙니다. IP 모듈 버전과 XSA 안 Bitstream 일치, 보드 MMIO·`MODEL_COMMIT`·CNN 동시 실행을 별도 검증해야 합니다.
5. **3D 시각화 한계.** 실제 GLTF 네 모델과 텍스처는 라이선스/용량 이유로 Git에 없으며, 2D 12관절만으로 정확한 3D 깊이를 복원할 수 없습니다. 구동 PC에서 팔·다리 좌우·스쿼트/걷기 연속성을 직접 확인하세요.
6. **Frontend 초기 다운로드 최적화.** 빌드는 통과하지만 약 722KB의 메인 JS 번들 경고가 있습니다. 테스트 상태를 유지하면서 관리자/편집 도구의 지연 로딩을 별도 PR에서 검토할 수 있습니다.
7. **주석/시험 설명 정리.** `pc/backend/app/service.py`의 `LocationStabilizer` 기본 인자·docstring 및 일부 테스트 주석에는 **3회** 기준이 남아 있습니다. 실제 Backend 객체는 `confirmations=2`로 생성됩니다. 기능에는 영향이 없지만 코드 주석과 테스트 설명을 다음 코드 PR에서 맞추는 것이 좋습니다.
8. **보존 자료 분리.** `ps_location/`·`ps_onlysw/`의 과거 2포트 인터페이스, 이전 CNN/Ridge IP 패키지, 백업 `.bak_*` 파일은 현재 배포 파일과 혼동하지 않도록 유지 정책을 정하세요. 삭제·이동은 별도 승인 후 진행합니다.

## 문서 변경 원칙

- 실행 경로는 `ps/` + `pc/backend/` + `pc/frontend/`을 기준으로 설명합니다.
- 위치 결과의 **2회 확인**과 Frontend의 **관절 자세 확인 프레임**을 명확히 구분합니다.
- 이전 시험판·검증 일지·외부 고지·담당자 미기입 팀 템플릿은 원래 사실을 보존합니다.
- 제공된 발표 PPTX는 35장으로, 내장 이미지 상당수가 슬라이드 장식/제목 분할 요소입니다. 구현을 설명하는 기존 [아키텍처 SVG](../assets/wisensing-architecture.svg)가 더 정확하므로 발표 미디어를 무분별하게 복사하지 않았습니다.
