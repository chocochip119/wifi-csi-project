# 참고 코드와 의존성 출처

## 수집기 패킷 파서

- 파일: `vendor/sync_csi_input.py` — **이 저장소에는 포함하지 않습니다.** 재배포 라이선스를 확인하지 못했기 때문입니다.
  USB 직결 모드를 쓰는 사람만 아래 참고 저장소의 원본을 직접 받아 이 경로에 두고, 해당 저장소의 이용 조건을 따릅니다.
  Ethernet(PS 경유) 모드, 학습, Backend는 이 파일이 필요 없습니다.
- 참고 저장소: [ziziccc/wifi-csi-pose](https://github.com/ziziccc/wifi-csi-pose)
- 원본 상대 경로: `tools/sync_csi_input.py`
- SHA-256: `df01454247955677f56ad5e8516013b61b9aad47a05e753a04c23c3c3201816e`
- 이 사본은 팀에서 사용하던 `making_templates/sync_csi_input.py` 및 로컬 참고 원본과 바이트 단위로 일치합니다. 파서 내용은 변경하지 않았습니다.

팀의 펌웨어 참고 저장소는 [chocochip119/wifi-csi-project](https://github.com/chocochip119/wifi-csi-project)입니다.
이 소스 배포본에는 ESP32 펌웨어를 포함하지 않습니다.

## 현장 수정본

실시간 엔진·화면·기록·시리얼 연결의 시작점은 팀 내부 `CSI_LOCAL_FIX_HANDOFF_20261001`의 `code_after`입니다.
이번 애플리케이션은 해당 코드의 수신 시각 처리와 패킷 호환성을 유지하고, 동적 모델 로드·새 학습·6클래스 처리 등을 추가했습니다.

위 참고 원본에서 적용 라이선스를 확인하지 못했으므로 이 파일에서 MIT/BSD 등 새로운 라이선스를 부여하지 않습니다.
저장소에 적용할 라이선스와 참고 코드의 재배포 조건은 팀이 확인해 기록할 항목입니다. 출처 표기는 라이선스 허가를 대신하지 않습니다.

## Python 패키지

Python 패키지는 저장소에 복사하지 않고 pip로 설치합니다. 각 패키지의 버전·다운로드 해시는 `requirements-lock.txt`에 있습니다.
각 의존성은 해당 프로젝트의 라이선스를 따릅니다.

requirements 파일에서 다른 requirements를 참조하고 해시 검증을 사용하는 방식은 [pip 공식 형식](https://pip.pypa.io/en/stable/reference/requirements-file-format/)을 따릅니다.
