# 위치 모델 학습

위치 모델의 학습·검증·데이터 분석·Portable Ridge export 코드를 두는 영역입니다. 전달 ZIP에는 전체 학습 프로젝트가 없어, 현재 이 디렉터리에는 안내 문서만 있습니다.

실시간 입력·특징·추론과 필요한 동반 모듈은 [PC Backend](../../pc/backend/README.md)의 `localization/`에 있습니다. 실행 모델 NPZ/JSON은 [models](../../pc/backend/localization/models/)에, 전달된 회귀 fixture는 Backend 테스트 영역에 있습니다. 실행에 필요한 `fivepoint_model.py`, `phase_features.py`, `labels.py`도 함께 유지합니다.

향후 학습 원본과 데이터 분석을 추가할 때 이 영역에 배치하고, 배포할 최종 모델/특징 계약만 PC 실행 영역과 맞춥니다. 학습 RX 순서와 물리 배치, NPZ/JSON·scale·검증 결과를 함께 기록하세요. 현재 모델의 수치 회귀와 실제 현장 정확도는 [점검 기록](../../docs/reviews/2026-10-07-pc-integration.md)을 참고하세요.
