# PC Frontend

현재 이 폴더에는 안내 문서만 있습니다. 전달 ZIP에 실행 프런트엔드·캐릭터 GLB·텍스처가 없어 아직 구현되지 않았습니다.

구현 시 `src/`, `public/models/`, `public/textures/`, `package.json`을 여기에 추가합니다. [Backend API](../backend/README.md)의 `/ws` 스냅샷과 `/api/rx-layout`, `/api/confirm-rx-layout`을 사용합니다. 위치/Pose의 availability·stale·좌표계를 각각 확인하고, 연결 오류나 오래된 결과를 unavailable로 표시합니다.

Backend 의존성을 설치한 뒤 저장소 루트에서 화면 연동용 가짜 스냅샷을 실행합니다.

```bash
python pc/backend/run_backend.py --fake
```

`http://127.0.0.1:8000/api/snapshot`에서 확인합니다. 실제 연결 순서는 [통합 실행](../../docs/bringup.md)에 있습니다.
