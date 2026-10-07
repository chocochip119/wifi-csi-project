# GitHub 팀 작업 가이드

현재 작업 흐름은 **main 최신화 → 작업 브랜치 → commit/push → PR → 검토·병합**입니다. push는 브랜치 업로드이며 main 반영은 PR 병합 단계입니다. 폴더 역할은 [저장소 구조](repository_structure.md)를 먼저 확인하세요.

## 처음 한 번

초대받은 팀원은 GitHub 알림/이메일에서 저장소 초대를 수락합니다. 일반 로컬 폴더에 clone합니다.

```bash
git clone https://github.com/chocochip119/wifi-csi-project.git
cd wifi-csi-project
```

## 작업 시작

`git status`로 기존 변경을 확인합니다. 작업 중인 파일이 있으면 현재 브랜치에서 정리한 뒤 이동합니다. 작업 트리가 깨끗할 때:

```bash
git switch main
git pull --ff-only
git switch -c docs/update-structure
```

위 브랜치 이름은 문서 수정 예시입니다. 자신의 작업에 맞는 이름 하나를 사용합니다.

| 작업 | 브랜치 예시 |
|---|---|
| ESP32 수집 | `feature/esp32-trigger` |
| CNN RTL | `fix/cnn-rounding` |
| PS↔PC | `feature/ps-pc-tcp` |
| 문서 | `docs/update-structure` |

이미 있는 작업 브랜치에는 `git switch 브랜치이름`으로 이동합니다.

## 확인하고 업로드

문서 수정 예시입니다. `git add`에는 자신이 실제로 수정한 경로만 선택합니다.

```bash
git status
git diff
git add README.md docs/repository_structure.md
git diff --cached
git commit -m "docs: align repository structure with RX5 integration"
git push -u origin docs/update-structure
```

첫 push 뒤 같은 브랜치에는 `git push`를 사용합니다. 모델 원본·실측 데이터·Vivado/Vitis/PetaLinux 빌드 결과를 추가하기 전 기존 `.gitignore`와 팀의 공유 기준을 확인합니다. `.gitignore`는 이미 추적 중인 파일을 자동으로 제거하지 않습니다.

## PR과 main 반영

GitHub의 `Pull requests → New pull request`에서 base를 `main`, compare를 자신의 브랜치로 선택합니다. 무엇이 바뀌는지, 실행한 검증, 아직 장비에서 확인하지 못한 부분을 본문에 적습니다.

리뷰 수정은 같은 브랜치에서 commit/push하면 PR에 이어집니다. 검토와 필요한 검증이 끝나면 팀의 병합 담당자가 PR을 main에 합칩니다. 자동 리뷰·호스트 테스트·RTL 시뮬레이션과 실제 장비 검증은 각각 결과를 기록합니다.

병합 후 작업 트리가 깨끗할 때 main을 다시 최신화합니다.

```bash
git switch main
git pull --ff-only
```

`--ff-only`가 실패하면 main에 별도 로컬 commit이 있는지 먼저 확인합니다. 기존 변경을 버리는 명령으로 해결하지 말고 원인을 확인하세요.

## 변경이 함께 필요한 경우

- 원본 CNN RTL을 고치면 `integration/pose_cnn_1.1/src/`의 같은 모듈과 Python INT8/golden 계약도 확인합니다.
- PS↔PC 바이트를 바꾸면 C 서버·Python protocol·[통신규격](ps_pc_protocol.md)·회귀 테스트를 함께 맞춥니다.
- 모델을 바꾸면 가중치·metadata·scale·golden·manifest를 같은 export run으로 유지합니다.
- 실행 방법·폴더 위치를 바꾸면 해당 README와 [루트 README](../README.md)의 링크를 확인합니다.

## 충돌 줄이기

동기화 폴더의 자동 파일 변경을 피하고, main을 최신화한 뒤 짧은 작업 브랜치를 사용합니다. 다른 영역을 함께 수정할 때에는 담당자와 경계·계약을 맞춥니다. 충돌이 발생하면 양쪽 변경을 확인하고 실제 의도에 맞춰 수정·검증합니다. 담당자를 적는 [팀 템플릿](members/README.md)은 아직 이름이 배정되지 않은 양식입니다.
