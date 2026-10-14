# PC — PS 위치·Pose 결과 통합과 2D/3D 시각화

PC 프로그램은 **Zynq PS에서 계산된 위치와 FPGA 관절 결과를 받아 하나의 화면에 보여주는 부분**입니다. Python Backend와 Three.js Frontend가 모두 구현되어 있습니다.

## 구현 구성

| 폴더 | 담당 기능 | 자세한 문서 |
|---|---|---|
| [`backend/`](backend/README.md) | PS 단일 TCP 연결, RX 배치 확인, **PS Ridge 위치 분류 결과 수신**, FPGA 12관절 수신, HTTP/WebSocket 스냅샷 | [Backend 기능·API·실행](backend/README.md) |
| [`frontend/`](frontend/README.md) | 실내 공간 **3D 캐릭터**, **2D 스켈레톤**, 위치/모션 보기, 관리자 설정·테스트·관절 편집·재생 | [Frontend 화면·조작·실행](frontend/README.md) |

```text
PS (C Ridge Location + FPGA Pose)
              │ TCP 5000 (Location/Pose/STATUS/ACK)
              ▼
    Backend 결과 검증·스냅샷 통합
                                                       ↓
                                HTTP/WebSocket 8000 스냅샷
                                                       ↓
                            Three.js Frontend (기본 5173)
                            3D 공간 + 2D 관절 + 관리자 창
```

## 화면에서 할 수 있는 일

- **Location:** P01~P09 구역 위치와 P10(중앙 앉기), 사람 없음 상태를 표시합니다.
- **Motion:** 12관절을 스켈레톤과 캐릭터 본에 전달하여 팔·다리 동작을 표현합니다.
- **설정/검증:** RX 연결·배치, 추론 상태, 관절 샘플, 저장된 추론 결과의 재생을 확인합니다.
- **보기 전환:** 시연 화면의 위치 모드와 중앙 모션 모드를 전환하고, 좌우 동작 방향을 직접 바꿀 수 있습니다.

## 실행·연결

Windows 개발 PC에서는 저장소 루트의 `WiSensing_Start.bat`로 Backend와 Frontend를 함께 시작할 수 있습니다. [원클릭 실행 안내](../docs/oneclick_launcher.md)에 초기 설정, 종료 방법, 보드 IP 주의 사항이 있습니다.

개별 실행·테스트는 [Backend README](backend/README.md), [Frontend README](frontend/README.md)를 참고합니다. Backend의 `--fake`는 UI/연결 흐름 확인용이며 실보드나 모델 정확도 검증이 아닙니다. 실제 연동 때는 PS 앱과 RX 물리 배치를 먼저 확인해야 합니다.
