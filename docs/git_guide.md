# GitHub 팀 작업 가이드

Git을 처음 쓰는 팀원은 **일단 push까지 할 수 있으면 됩니다.**
PR(Pull Request)은 나중에 익숙해진 뒤 사용합니다.

## 1. 저장소 초대 수락

저장소 관리자가 GitHub의 `Settings → Collaborators → Add people`에서 팀원을 초대합니다.

초대받은 사람은 GitHub 알림 또는 이메일에서 초대를 수락하면 됩니다.

## 2. 처음 한 번만 Clone

> 저장소는 **Google Drive / OneDrive 같은 동기화 폴더가 아닌 일반 로컬 폴더**에 Clone하는 것을 권장합니다.

```bash
git clone https://github.com/chocochip119/wifi-csi-project.git
cd wifi-csi-project
```

`clone`은 GitHub 저장소를 내 컴퓨터로 복사하는 작업입니다.

## 3. 작업 전 최신 내용 받기

먼저 현재 작업 상태를 확인합니다.

```bash
git status
```

작업 중인 변경사항이 없다면 최신 내용을 받습니다.

```bash
git switch main
git pull
```

`pull`은 GitHub의 최신 변경 내용을 내 컴퓨터로 가져오는 작업입니다.

## 4. 내 작업 브랜치 만들기

예시:

```bash
git switch -c feature/cnn
git switch -c feature/fft
git switch -c feature/esp32
git switch -c feature/axi
```

`branch`는 main을 바로 수정하지 않고 각자 작업 공간을 따로 만드는 기능입니다.

이미 만든 브랜치로 이동할 때는:

```bash
git switch feature/cnn
```

## 5. 작업한 내용 올리기 — 여기까지 필수

```bash
git status
git add .
git commit -m "feat: add cnn module"
git push -u origin feature/cnn
```

- `git status` : 변경된 파일 확인
- `git add` : 커밋할 파일 선택
- `git commit` : 변경 내용을 하나의 기록으로 저장
- `git push` : 내 브랜치의 커밋을 GitHub에 업로드

첫 push 이후에는 보통 아래만 해도 됩니다.

```bash
git push
```

### 처음에는 이 흐름만 기억

```text
status 확인
   ↓
main 최신화
   ↓
내 branch 생성
   ↓
코드 작성
   ↓
add → commit → push
```

## PR(Pull Request)은 나중에

PR은 **내 브랜치의 내용을 main에 합치기 전에 확인하는 기능**입니다.

처음에는 필수가 아닙니다. Git 사용에 익숙해진 뒤 팀에서 PR 방식을 추가하면 됩니다.

## 자주 쓰는 명령어

```bash
git status           # 현재 상태 확인
git branch           # 브랜치 목록 확인
git switch main      # main으로 이동
git pull             # 최신 내용 받기
git add .            # 변경 파일 선택
git commit -m "..."  # 커밋
git push             # GitHub에 업로드
```

## 충돌 줄이기

- 저장소는 Google Drive / OneDrive 동기화 폴더 안에 두지 않습니다.
- 가능하면 `main`에서 직접 작업하지 않습니다.
- `git pull` 전에 `git status`로 작업 중인 변경사항이 없는지 확인합니다.
- 다른 사람 파일을 수정해야 하면 먼저 이야기하고 진행합니다.
- `.gitignore`는 공통 설정이므로 필요한 항목이 있으면 임의로 여러 명이 동시에 수정하지 말고 관리자에게 알려주세요.
- Vivado/Vitis 빌드 결과, Python 캐시, 모델 출력 등은 `.gitignore`로 제외되어 있습니다.
