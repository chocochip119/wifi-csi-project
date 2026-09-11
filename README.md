# Wi-Fi CSI Project

Wi-Fi CSI(Channel State Information)를 이용해 **자세, 호흡, 위치를 비접촉으로 추정**하는 7인 팀 프로젝트입니다.

> 현재는 기획 초기 단계이므로 기능과 담당은 진행하면서 바뀔 수 있습니다.

## 주요 기능

- ESP32 기반 Wi-Fi CSI 수집
- Zynq PS에서 CSI 수신 / 전처리 / PL 제어
- CNN 기반 자세 추정
- FFT 기반 호흡 분석
- CSI 기반 사람 위치 추정
- AXI 기반 PS ↔ PL 통신
- PL TOP 및 전체 시스템 통합

## 폴더 구조

```text
wifi-csi-project/
├─ docs/                   # 공통 문서
│  ├─ architecture.md      # 전체 시스템 구조
│  ├─ interface.md         # 모듈 간 입력/출력, 데이터 형식
│  ├─ git_guide.md         # Git/GitHub 초보자용 팀 작업 가이드
│  ├─ images/              # README / 문서용 이미지, 블록다이어그램
│  └─ members/             # 팀원별 조사 / 진행 내용
│
├─ esp32/
│  ├─ tx/                  # Wi-Fi 송신 코드
│  └─ rx/                  # CSI 수집 / 수신 코드
│
├─ ps/                     # Zynq PS 프로그램
│
├─ pl/                     # FPGA(PL) 설계
│  ├─ cnn/                 # 자세 추정
│  │  ├─ rtl/              # 실제 RTL 설계 코드
│  │  └─ testbench/        # Testbench / 필요 시 UVM
│  ├─ fft/                 # FFT / 호흡 분석
│  ├─ localization/        # 사람 위치 추정
│  ├─ axi/                 # AXI 인터페이스
│  └─ top/                 # PL 전체 TOP
│
├─ ml/
│  ├─ pose/                # CNN 모델 / Python 실험
│  ├─ respiration/         # 호흡 / FFT 실험
│  └─ localization/        # 위치 추정 모델 / 실험
│
└─ integration/            # Vivado Block Design / 전체 시스템 통합
```

### RTL / Testbench

- `rtl/` : FPGA에서 실제로 동작할 설계 코드
- `testbench/` : RTL 동작을 검증하는 시뮬레이션 코드
- UVM을 사용할 경우 `testbench/uvm/` 폴더를 추가해서 사용

## 이미지 저장 기준

일반 사진/스크린샷은 `.gitignore`로 제외합니다.
문서나 README에 필요한 블록다이어그램, 캡처 이미지 등은 `docs/images/`에 저장하면 Git에 올라갑니다.

## `.gitkeep`이란?

Git은 **빈 폴더를 저장하지 않습니다.**

그래서 아직 코드가 없는 폴더도 GitHub에서 보이게 하려고 빈 파일인 `.gitkeep`을 넣어둡니다.

```text
pl/fft/rtl/.gitkeep
```

실제 코드가 생기면 `.gitkeep`은 지워도 됩니다.

## 처음 작업할 때

처음 Git을 사용하는 팀원은 **[GitHub 팀 작업 가이드](docs/git_guide.md)** 를 먼저 확인하세요.

```bash
git clone <repository URL>
cd wifi-csi-project
```

자기 작업 브랜치를 만든 뒤 작업합니다.

```bash
git checkout -b feature/작업이름
```

작업 후에는 기본적으로 아래 순서입니다.

```bash
git add .
git commit -m "작업 내용"
git push origin feature/작업이름
```

### Git 명령 의미

| 명령 | 의미 |
|---|---|
| `git pull` | GitHub의 최신 변경 내용 가져오기 |
| `git add` | 커밋할 파일 선택 |
| `git commit` | 변경 내용을 하나의 기록으로 저장 |
| `git push` | 내 커밋을 GitHub에 업로드 |

> 다른 사람 작업과 겹치지 않도록 **작업 시작 전 `git pull`** 하는 습관을 권장합니다.

## 문서 작성 기준

- 전체 구조 변경 → `docs/architecture.md`
- 모듈 I/O / AXI / 데이터 형식 변경 → `docs/interface.md`
- Git/GitHub 사용법 → `docs/git_guide.md`
- 문서용 이미지 / 블록다이어그램 → `docs/images/`
- 개인 조사 / 진행 내용 → `docs/members/memberX.md`
- 실제 코드는 해당 기능 폴더에 저장

## Reference

- Wi-Fi CSI Pose Estimation: https://github.com/ziziccc/wifi-csi-pose
