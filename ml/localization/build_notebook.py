"""Generate a clean, step-by-step training notebook without any dataset or fit."""
import json
from pathlib import Path
import uuid

ROOT=Path(__file__).resolve().parent
cells=[]

def md(source): cells.append({'cell_type':'markdown','id':uuid.uuid4().hex[:8],'metadata':{},'source':source.strip().splitlines(keepends=True)})
def code(source): cells.append({'cell_type':'code','id':uuid.uuid4().hex[:8],'metadata':{},'source':source.strip().splitlines(keepends=True),'execution_count':None,'outputs':[]})

md('''# CSI 사람 없음 + 9지점 + p05 앉기(p10) 학습과 시험

**수집 CSV → 파일 라벨 → 학습·검증·시험 분리 → 새 학습 → 보류 시험 → 실시간 GUI** 순서입니다.
Codex에게 학습을 부탁할 필요 없이 이 노트북의 셀을 순서대로 실행하세요.

먼저 정확한 Python3.14.7 x64(Tcl/Tk 포함)를 준비하고 `setup_windows.ps1` 또는 `setup_windows.cmd`를 실행합니다. GitHub 소스는 requirements.txt로 인터넷 설치하며, VS Code 커널을 이 폴더의 `.venv\\Scripts\\python.exe`로 선택합니다.
Python **3.14.7 x64** 환경입니다. 수집기 `making_templates`와 원본 CSV는 그대로 둡니다.
기존 Python 3.11의 모델은 가져오지 않습니다. 이 환경에서 새로 학습한 모델을 GUI가 읽습니다.

지점은 p01=(30,30), p02=(90,30), p03=(150,30), p04=(30,90), p05=(90,90), p06=(150,90), p07=(30,150), p08=(90,150), p09=(150,150)cm입니다. **p10은 p05 의자에 앉은 상태**이며 좌표는 p05와 같은 (90,90)입니다. p05 서기도 의자를 둔 채로 수집합니다. 파일 이름 예: `1004_15시_p10E1.csv`.
좌표는 지점 대표값이며 카메라의 실시간 정답 좌표가 아닙니다. `empty`는 측정 영역에 사람이 없는 상태이며 좌표가 없습니다.
**11개 클래스(p01~p10 + empty)의 실제 수집 데이터로 새로 학습해야 합니다. 기존 5지점/6클래스 모델은 이 앱에서 열 수 없습니다.** p05와 p10은 좌표가 같아 좌표 오차로 구분되지 않으므로 혼동행렬로 확인합니다.
자세 좌표 열은 입력 특징에 사용하지 않습니다. 중간 위치·여러 사람·새 환경의 성능은 별도 확인이 필요합니다.
''')
md(r'''## VS Code PowerShell에서 시작

아래 명령은 **이 노트북의 Python 셀이 아닌 VS Code PowerShell 터미널**에 입력합니다.
ZIP을 D드라이브 바로 아래에 풀어 `D:\csi_studio_py314`가 되게 합니다. 설치는 처음 한 번만 합니다.

```powershell
Set-Location -LiteralPath 'D:\csi_studio_py314'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup_windows.ps1
if ($LASTEXITCODE -ne 0) { throw '설치 오류를 확인하세요.' }
& .\.venv\Scripts\python.exe -X utf8 .\environment_probe.py
if ($LASTEXITCODE -ne 0) { throw 'Python 환경을 확인하세요.' }
code --new-window .
```

노트북 커널을 `.venv\Scripts\python.exe`로 선택한 뒤 아래 Python 셀부터 실행합니다.
학습 후 실시간 화면은 PowerShell에서 다음과 같이 엽니다. 수집기의 같은 COM 연결은 먼저 해제하세요.

```powershell
& .\.venv\Scripts\python.exe -X utf8 -u .\csi_live_gui.py
```

가상환경 활성화는 필요 없습니다. `.cmd` 없이 설치하는 방법과 run/COM 지정,
설치·학습·실시간 실행 명령은 같은 폴더의 `README.md`에 있습니다.
''')
code('''from pathlib import Path
import sys, subprocess
from IPython.display import display
ROOT = Path.cwd().resolve()
if not (ROOT / "studio_training.py").is_file():
    raise RuntimeError("VS Code에서 csi_studio_py314 폴더를 열고 커널을 다시 선택하세요.")
from environment_probe import check_environment
from studio_training import (create_manifest, read_manifest, save_manifest, plan_splits,
                             prepare_summary, train_new_run, evaluate_run)
display(check_environment(strict=True))
print("사용 중인 Python:", sys.executable)
''')
md('''## 1 수집 파일 폴더 지정

아래 `DATA_ROOT`를 실제 수집 CSV 전용 폴더로 바꿉니다. 하위 폴더도 읽습니다. ZIP은 먼저 별도 데이터 폴더에 풉니다.
`MANIFEST`는 **원본 CSV의 위치와 라벨을 적는 목록**입니다. 같은 목록이 있으면 다시 읽고 덮어쓰지 않습니다.
다른 데이터 묶음은 `MANIFEST` 파일 이름도 바꿔 주세요. 원본 CSV가 있는 폴더에 학습 결과나 목록 CSV를 저장하지 마세요.
''')
code('''DATA_ROOT = ROOT / "data"  # 시연 PC: D:/csi_studio_py314/data (수집 CSV 전용)
MANIFEST = ROOT / "metadata" / "recordings.csv"
if MANIFEST.exists():
    files = read_manifest(MANIFEST)
    print("기존 목록을 읽었습니다. 데이터 폴더를 바꿨다면 MANIFEST 이름도 바꾸세요.")
else:
    files = create_manifest(DATA_ROOT, MANIFEST)
display(files)
print("편집할 목록:", MANIFEST)
''')
md('''## 2 파일별 라벨 확인과 편집

다음 셀은 **별도 라벨 편집창**을 엽니다. Ctrl/Shift로 파일을 여러 개 선택해 사람·시간대·회차를 한 번에 지정할 수 있습니다.

| 열 | 예 | 의미 |
|---|---|---|
| point_id | p01 또는 empty | 실제 지점 또는 측정 영역에 사람 없음 |
| person | G 또는 none | empty는 반드시 none. 사람 있음은 실제 이름/코드 |
| session | 1002_오전_배치02 | 날짜·시간대·배치가 구분되는 수집 묶음 |
| repeat | r01 | 같은 묶음에서 지점들을 방문한 회차 |
| split | train / validation / test | 다음 셀에서 자동 배정 가능 |
| enabled | true | 확인한 파일만 학습·평가 대상으로 포함 |

일반 이름 `sync_csi_pose_2026...csv`에는 위치/사람이 없어서 자동으로 알 수 없습니다.
알고 있는 수집 기록을 기준으로 입력하세요. `1001_14시_p01G1.csv` 등 해석 가능한 이름도 확인 후 enabled=true로 바꿉니다.
**선택 파일에 적용 → 목록 저장 → 창 닫기** 후 다음 셀로 진행합니다. 편집창은 원본 CSI 파일을 수정하지 않습니다.

**사람 없음 수집:** 기존 수집기로 사람이 영역에서 완전히 빠진 뒤 3~5초 기다리고 30초씩 기록합니다.
(5지점 당시 예시) 시간대당 3명 × 5지점 × 5회차에서는 사람 있음이 75파일이었습니다. 11클래스에서는 지점 수가 10개(p01~p10)이므로 같은 구성이면 사람 있음이 150파일입니다.
empty도 **시간대당 30초 × 15파일 = 7.5분**을 첫 기준으로 권합니다. 다섯 지점 합계인 75파일에 맞추는 것은 아닙니다.
앞서 제안한 5파일은 빠른 파일럿용이며, 이번 3명 수집 규모에는 15파일을 권합니다. 성능이 보장되는 최소 수량은 아닙니다.
empty는 각 회차에 독립적으로 3번씩 수집하면 총 15파일입니다. 사람 있음 기록 사이에 나눠 모으세요.
파일 예: `20261002_l02_b01_none_r01_empty_take01.csv` (r01~r05, take01~take03).
take는 **새로 측정한 기록**을 뜻하며 파일 사본이 아닙니다. 기존 이름을 바꿀 필요 없이 편집창에서 라벨을 지정해도 됩니다.
empty를 선택하면 person=none이 자동 지정됩니다. 같은 empty 파일을 사람마다 복제하지 않습니다.
사람이 가만히 있을 때도 구분되는지 확인하려면 사람 있음 자료에도 정지 상태를 포함하세요.
사람 있음 37.5분 + empty 7.5분 = 순수 기록 45분/시간대입니다. 이동·준비 시간을 더하면 1시간 간격이 빠듯할 수 있습니다.
''')
code('''editor = subprocess.Popen([sys.executable, str(ROOT / "manifest_editor.py"), str(MANIFEST)], cwd=ROOT)
print("라벨 편집창에서 저장하고 닫은 뒤 다음 셀을 실행하세요.")
''')
md('''## 3 학습과 검증과 시험 분리

현재 기본값은 **sessions**입니다. 각 시간대에 사람·p01~p10·회차·empty를 모두 수집하고,
첫 묶음 b01은 학습, b02는 검증(모델 선정), b03은 보류 시험으로 배정합니다.
3묶음이 기본 예시이며, 묶음이 더 많으면 학습 목록에 여러 시간대를 넣을 수 있습니다.
사용자는 파일별 실제 라벨과 아래 시간대 목록을 확인합니다. 프로그램이 그 규칙으로 CSV 전체를 배정하므로
각 파일을 하나씩 임의로 학습/검증에 지정할 필요가 없습니다. 미지정·중복 그룹은 오류로 알려줍니다.
이것은 **동일한 3명의 다른 시간대** 시험입니다. 처음 보는 사람 성능은 people/heldout_people로 별도 평가합니다.

**people:** 학습·검증·시험 사람을 따로 두어 새 사람에 대한 성능을 확인합니다. 아래 예는 G 학습, F 검증, A 시험입니다.

**heldout_people:** 기존 실험처럼 학습 사람들의 r01~r04를 학습, r05를 검증으로 쓰고 나머지 사람을 시험합니다.
`FIT_PEOPLE`을 ["G"] 또는 ["G", "F"]으로 바꾸면 단독/혼합 학습을 선택합니다.
이 방식의 검증은 같은 사람의 다른 회차라 쉽게 100%에 도달할 수 있습니다. 새 사람 성능은 보류 시험 결과로 따로 판단합니다.

**sessions (기본):** 시간대를 분리합니다. 서로 다른 3개 이상 수집 묶음이 필요합니다. 목록의 session 값을 정확히 입력합니다.

**repeats:** 같은 사람·세션에서 r01~r03 학습, r04 검증, r05 시험입니다. 빠른 파일럿이며 새 사람·새 날짜 성능으로 해석하면 안 됩니다.

**manual:** 라벨 편집창에서 지정한 split을 그대로 씁니다. 같은 회차의 지점 파일들을 split 사이에 나누지 않습니다.
프로그램은 파일 경로/내용 SHA와 session·person·repeat 중복을 검사합니다. 한 파일에서 만든 창을 무작위로 나누지 않습니다.

각 split은 **p01~p10 + empty, 11클래스 모두** 있어야 합니다. 사람 분리 모드에서 empty는 사람이 없으므로 따로 배정합니다.
`EMPTY_MODE="sessions"`는 빈 공간을 수집한 서로 다른 시간대를 지정하고, `"repeats"`는 r01~r03/r04/r05로 나눕니다.
기본 repeats는 빠른 파일럿용입니다. 시간 안정성을 보려면 sessions로 바꾸세요.
메인 SPLIT_MODE가 sessions/repeats이면 empty도 메인 규칙을 따르며, 별도 EMPTY_MODE는 사용하지 않습니다.
''')
code('''files = read_manifest(MANIFEST)
print("목록에 등록된 시간대:", sorted(set(files["session"].astype(str)) - {""}))
SPLIT_MODE = "sessions"  # sessions / repeats / people / heldout_people / manual
# 예시 이름입니다. 위 목록과 정확히 맞춰 날짜·시간대 값을 지정하세요.
TRAIN_SESSIONS = ["20261002_l02_b01"]
VALIDATION_SESSIONS = ["20261002_l02_b02"]
TEST_SESSIONS = ["20261002_l02_b03"]
FIT_PEOPLE = ["G", "F"]  # heldout_people 방식에서 사용
HELDOUT_PEOPLE = ["A"]       # FIT_PEOPLE과 겹치면 안 됨
EMPTY_MODE = "repeats"         # people/heldout_people에서만 사용: repeats / sessions
EMPTY_SPLIT = dict(empty_mode=EMPTY_MODE,
                   empty_train_repeats=["r01","r02","r03"],
                   empty_validation_repeats=["r04"], empty_test_repeats=["r05"],
                   empty_train_sessions=TRAIN_SESSIONS,
                   empty_validation_sessions=VALIDATION_SESSIONS,
                   empty_test_sessions=TEST_SESSIONS)
if SPLIT_MODE == "people":
    files = plan_splits(files, mode="people",
                       train_people=["G"], validation_people=["F"], test_people=["A"],
                       **EMPTY_SPLIT)
elif SPLIT_MODE == "heldout_people":
    files = plan_splits(files, mode="heldout_people", fit_people=FIT_PEOPLE,
                       heldout_people=HELDOUT_PEOPLE, **EMPTY_SPLIT)
elif SPLIT_MODE == "sessions":
    files = plan_splits(files, mode="sessions",
                       train_sessions=TRAIN_SESSIONS,
                       validation_sessions=VALIDATION_SESSIONS, test_sessions=TEST_SESSIONS)
elif SPLIT_MODE == "repeats":
    files = plan_splits(files, mode="repeats",
                       train_repeats=["r01","r02","r03"], validation_repeats=["r04"], test_repeats=["r05"])
elif SPLIT_MODE != "manual":
    raise ValueError("SPLIT_MODE 값을 확인하세요.")
summary = prepare_summary(files)
display(summary["by_split_point"])
display(summary["by_person_session"])
display(summary["missing_fields"])
print("포함 파일:", summary["enabled_files"], "/ 전체:", summary["files"])
print("아래 학습 셀은 현재 메모리의 files 목록을 복사해 이번 실행에 고정합니다.")
''')
md('''## 4 후보 학습과 모델 선정

첫 실행은 `amp_rssi`를 유지합니다. kNN(5이웃·거리 가중), Ridge(alpha=10), MLP(64,32·alpha=0.001·max_iter=300)를 비교합니다.
`FAMILIES`에서 후보를 줄일 수 있습니다. 실행마다 새 Python 프로세스·새 scaler·새 모델을 만들고 새 runs 폴더에 저장합니다.

학습/검증은 2초 창·2초 stride입니다. RX5개 완성, CSI384바이트, 첫 2 IQ쌍 제외, 진폭950+RSSI5를 사용합니다.
모델과 scaler는 train으로만 맞추고 **검증 BA → macro F1 → 선언한 후보 순서**로 선정합니다. 검증까지 합쳐 다시 학습하지 않습니다.
동점이면 자동 최우수 근거가 강한 것이 아니므로 다음 독립 시험으로 확인하세요.

`RUN_TRAINING=True`로 바꿔 실행합니다. 입력이 잘못되면 원인을 고친 후 새 실행으로 진행하세요.
`amp_phase_rssi`는 선택 가능한 실험용 상대 위상 cos/sin 특징입니다. HT40 물리 위상 보정 완료를 뜻하지 않습니다.
''')
code('''RUN_TRAINING = False  # 라벨·분리를 확인한 뒤 True로 변경
FAMILIES = ("knn", "ridge", "mlp")
VARIANT = "amp_rssi"  # 선택 실험: amp_phase_rssi
CONFIG = {"layout_id":"layout_02", "mode":"window", "window_s":2.0, "stride_s":2.0,
          "rx_ids":[0,1,2,3,4], "csi_len":384, "drop_pairs":2,
          "min_interval_s":0.1, "max_cycle_span_s":0.1,
          "min_window_cycles":10, "min_window_span_s":1.0,
          "trim_start_s":2.0, "trim_end_s":2.0}
if RUN_TRAINING:
    RUN_DIR = train_new_run(files, ROOT / "runs", CONFIG, families=FAMILIES, variant=VARIANT, seed=17)
    print("학습 완료. 결과 폴더를 메모하세요:", RUN_DIR)
else:
    print("대기: 라벨·분리를 확인하고 RUN_TRAINING=True로 실행하세요.")
''')
md('''## 5 검증 결과와 수신 품질 보기

leaderboard는 **검증 결과**입니다. 가장 위 후보가 고정된 선정 모델입니다. 학습 로그의 수렴 경고도 확인하세요.
파일별 정상 주기·필터 통과 창 수를 함께 봅니다. 창이 적거나 파일이 거부되면 원인을 먼저 확인합니다.
노트북을 재시작했다면 아래 RUN_DIR에 이전 결과 폴더 경로를 직접 넣으면 됩니다.
''')
code('''import pandas as pd
if "RUN_DIR" in globals():
    RUN_DIR = Path(RUN_DIR)
    display(pd.read_csv(RUN_DIR / "fit" / "leaderboard.csv"))
    import json
    training_report = json.loads((RUN_DIR / "fit" / "training_report.json").read_text(encoding="utf-8"))
    for fit in training_report["fits"]:
        for warning in fit.get("warnings", []):
            print("학습 경고:", fit["candidate"], warning["category"], warning["message"])
    quality = pd.read_csv(RUN_DIR / "train_validation_quality.csv")
    display(quality[["path", "split", "duration_s", "complete_cycles", "selected_cycles", "accepted_windows", "rejected_windows"]])
    print("선정/전처리 고정 기록:", RUN_DIR / "frozen.json")
    print("품질 보고서 파일:", [p.name for p in RUN_DIR.glob("*quality*")])
    print("GUI에서 선택할 폴더:", RUN_DIR)
else:
    print("먼저 학습하거나 RUN_DIR = Path(r'저장한 결과 폴더')를 지정하세요.")
''')
md('''## 6 보류 시험 실행

모든 후보와 선정 모델을 고정한 뒤 시험 파일을 엽니다. 시험은 **2초 창·0.5초 stride**입니다.
시험 결과를 본 뒤 모델을 바꾸면 이 자료는 개발용 평가가 됩니다. 새 최종 시험 자료가 필요합니다.
검증/시험 파일이 같은 원본이거나 파일이 바뀌면 중단합니다. 같은 결과 폴더에서 시험을 다시 덮어쓰지 않습니다.
정확도·BA·macro F1·정밀도·재현율·혼동행렬을 확인합니다. 파일 다수결은 보조 지표이며 실시간 보정이 아닙니다.

추가로 **빈 공간 오탐률**(실제 empty인데 지점을 출력), **사람 놓침률**(사람이 있는데 empty 출력)을 봅니다.
`occupied_location_accuracy`는 사람 있음 전체에서 위치까지 맞힌 비율이며 사람 놓침도 오답에 포함합니다.
좌표 오차는 정답·예측 모두 사람 있음인 경우만 계산하므로 평가 대상 수/coverage를 함께 확인합니다.
위치 오차만 작고 사람 놓침률이 높으면 좋은 모델이라고 볼 수 없습니다.
''')
code('''RUN_TEST = False  # 선정 모델을 고정한 뒤 True로 변경
if RUN_TEST:
    if "RUN_DIR" not in globals():
        raise RuntimeError("학습 결과 RUN_DIR을 지정하세요.")
    test_result = evaluate_run(RUN_DIR)
    display(test_result)
    print("시험 결과:", Path(RUN_DIR) / "evaluation")
else:
    print("대기: 시험을 공개하려면 RUN_TEST=True로 실행하세요.")
''')
md('''## 7 실시간 GUI

`python csi_live_gui.py --run-dir <RUN_DIR>`(보드 경유 Ethernet은 `python tools/csi_live_gui_ethernet.py --run-dir <RUN_DIR>`)로 실행하고 **학습 결과 폴더**로 위 RUN_DIR을 선택합니다. 또는 다음 셀에서 실행할 수 있습니다.
수집기가 같은 TX COM을 사용하고 있으면 수집기에서 연결을 해제한 뒤 GUI로 연결하세요.
모델 선택 → TX 데이터 COM 연결 → Status → 필요 시 TX Run → 학습 배치/RX 순서/HT40 확인 → 추론 시작 순서입니다.

시각은 현장 수정본과 같이 `perf_counter_ns()`를 사용합니다. 시각·순서 거부 사유, RX별 실제 수신 행/초, 유효 주기 수를 표시합니다.
GUI에서 30초 지점 시험과 원본 CSI 저장을 선택할 수 있습니다. 새 현장 시험의 정답은 직접 지정합니다.
empty 예측은 **사람 없음**으로 표시하고 지도 강조점·대표 좌표를 지웁니다.
CSI 미수신/품질 부족은 **대기/입력 부족** 상태이며 사람 없음 판정으로 간주하지 않습니다.
연결할 때 선택 모델이 로드됩니다. 연결 후 모델을 바꿀 때 **선택 모델 적용**을 사용합니다.
처음에는 empty와 p01~p10을 각각 30초씩 시험하고, 실제 장치에서 수신이 끊기지 않는지도 확인하세요.
''')
code('''OPEN_LIVE_GUI = False  # GUI를 열려면 True
if OPEN_LIVE_GUI:
    if "RUN_DIR" not in globals():
        raise RuntimeError("학습 결과 RUN_DIR을 지정하세요.")
    gui = subprocess.Popen([sys.executable, str(ROOT / "csi_live_gui.py"), "--run-dir", str(RUN_DIR)], cwd=ROOT)
    print("GUI에서 TX 연결과 추론을 시작하세요.")
else:
    print("python csi_live_gui.py --run-dir <RUN_DIR>로 실행하거나 OPEN_LIVE_GUI=True로 실행하세요.")
''')
md('''## 팀원에게 전달하기

프로그램 폴더와 사용할 `runs/<실행ID>` 폴더를 함께 전달합니다. `.venv`는 복사하지 않고 대상 PC에서 setup_windows.cmd로 다시 만듭니다.
실시간 추론만 할 때 원본 학습 CSV는 필요하지 않습니다. 기존 run의 보류 시험은 학습 당시 원본 절대 경로와 SHA를 검사하므로 경로를 바꾸면 거부합니다.
다른 위치로 원본을 옮겨 새 실험을 할 때는 새 manifest와 새 run을 만드세요. 기존 결과는 보존합니다.
모델만 골라 복사하지 말고 `fit/models`, 버전 sidecar, model_catalog 및 기록을 포함한 결과 폴더 전체를 옮기세요.
변경한 사람·시간대 분리와 모델 설정, 실제 현장 조건을 기록합니다. 상세 설명은 README.md를 참고하세요.
''')
book={'cells':cells,'metadata':{'kernelspec':{'display_name':'CSI Studio Python 3.14.7','language':'python','name':'csi-studio-py314'},'language_info':{'name':'python','version':'3.14.7'}},'nbformat':4,'nbformat_minor':5}
(ROOT/'01_Train_and_Evaluate.ipynb').write_text(json.dumps(book,ensure_ascii=False,indent=1),encoding='utf-8')
print('Created clean notebook:',len(cells),'cells')
