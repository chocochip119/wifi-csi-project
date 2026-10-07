# PC — 실시간 Backend와 화면 연결

| 위치 | 상태 / 역할 |
|---|---|
| [backend](backend/README.md) | 실행 코드. TCP CSI/Pose 입력, 위치 추론, 상태 통합, HTTP/WebSocket |
| [frontend](frontend/README.md) | README만 있는 구현 예정 위치. Frontend/GLB/텍스처 미포함 |

Backend는 PS TCP 서버의 클라이언트입니다. CSI/STATUS/ACK는 5000, Pose는 5001로 받고 웹 API는 기본 8000에서 제공합니다. 위치는 PC에서 계산하며 Pose는 FPGA 결과를 읽습니다.

## 빠른 확인

저장소 루트에서 Python 3.10 이상과 Backend 의존성을 준비합니다.

```bash
python -m pip install -r pc/backend/requirements.txt
python pc/backend/run_backend.py --fake
```

`http://127.0.0.1:8000/api/snapshot` 또는 `/docs`를 확인합니다. 실제 PS 연결에는 `python pc/backend/run_backend.py --ps-host <PS_IP>`를 사용합니다. 이 실행 전에 PS 앱과 네트워크를 준비하고 실제 RX index↔MAC/배치 순서를 확인하세요.

세부 옵션·API·RX 확인 절차는 [Backend README](backend/README.md), 보드까지의 순서는 [통합 실행](../docs/bringup.md), 패킷 규격은 [PS↔PC](../docs/ps_pc_protocol.md)에 있습니다. 연결 종료/stale는 unavailable이고 데이터 미수신을 사람 없음으로 판단하지 않습니다.
