# PC Frontend

실행 프런트엔드/캐릭터 GLB/텍스처는 받은 ZIP에 포함되지 않아 아직 구현되지 않았습니다.

추가 시 `src/`, `public/models/`, `public/textures/`, `package.json`을 이 위치에 둡니다. Backend의 `/ws` 스냅샷과 `/api/rx-layout`, `/api/confirm-rx-layout`을 사용하며 연결 오류/오래된 위치/Pose는 unavailable로 표시합니다. 프런트엔드 개발 중에는 `python pc/backend/run_backend.py --fake`로 스냅샷을 확인할 수 있습니다.
