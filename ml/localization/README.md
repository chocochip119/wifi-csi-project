# 위치 모델 (학습 · 내보내기 · 실시간 확인)

Wi-Fi CSI(RX 5대)로 **사람 없음 + 9개 지점 + p05 의자 앉기(p10)**, 11개 클래스를 분류합니다. 연속 XY 회귀가 아니라 정해진 지점 분류이며, 좌표는 각 지점의 대표값입니다.

| 영역 | 위치 |
|---|---|
| 학습·평가 코드, 실시간 확인 GUI | 이 폴더 |
| PC 실행(Backend)용 엔진과 배포 모델(NPZ) | [`pc/backend/localization`](../../pc/backend/localization) |
| PS ↔ PC 통신 규격 | [`docs/ps_pc_protocol.md`](../../docs/ps_pc_protocol.md) |

## 구성

| 파일 | 역할 |
|---|---|
| `labels.py` | 11클래스와 지점 좌표(cm) 계약 |
| `location_core.py` | CSI 해석·주기 검증·2초 창·특징(진폭 평균 950 + RSSI 평균 5 = 955) — 학습과 실시간이 공유 |
| `location_data.py` | 원본 CSV·manifest 읽기, split 검증, 창 생성 |
| `location_model.py` | kNN / Ridge / MLP 학습·검증 선정·저장(joblib + metadata)·로드 |
| `location_live.py` | 실시간 엔진(STATUS 확인, RX 5대 완전 주기, 0.5초마다 2초 창 판정) |
| `phase_features.py` | 실험용 위상 특징(기본 모델은 사용 안 함) |
| `studio_training.py`, `manifest_editor.py`, `build_notebook.py`, `01_Train_and_Evaluate.ipynb` | 학습 절차(노트북)와 manifest 편집 |
| `environment_probe.py`, `requirements*.txt`, `setup_windows.ps1`/`.cmd` | 실행 환경 확인·고정 의존성·자동 설치(PC의 Python 3.14.7을 찾아 `.venv` 생성) |
| `export_portable_model.py` | 학습 run → Backend용 `ridge_portable.npz/json` + 회귀 fixture |
| `csi_live_gui.py` 외 `desktop_controller.py`, `live_*.py`, `serial_input.py` | 실시간 확인 GUI (USB 직결). USB 모드는 외부 참고 파서 `vendor/sync_csi_input.py`가 필요하며 라이선스 미확인으로 저장소에 넣지 않았습니다([THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md)) |
| `tools/csi_live_gui_ethernet.py` | 같은 GUI를 **보드 경유 Ethernet(TCP 5000)**으로 실행 |
| `tests/` | 60개 단위 테스트 (하드웨어·실데이터 불필요) |
| `results/<run>/` | 배포 모델의 설정·데이터 구성·검증 성능 요약 |

> 파일 이름의 `location_*`는 이전 `fivepoint_*`(5지점 시절 이름)를 바꾼 것입니다. 저장된 모델 파일에는 모듈 이름이 들어 있지 않아 기존 run도 그대로 열립니다. 학습 보고서의 schema 문자열 `fivepoint_training_report_v2_presence`는 기존 run과의 호환을 위해 유지합니다.

## 환경

학습과 joblib 모델 로드는 **CPython 3.14.7, Windows x64, `requirements-lock.txt`의 정확한 버전**에서만 동작합니다(로더가 버전을 검사). 다른 PC의 `.venv`를 복사하지 말고 새로 만듭니다.

```bash
py -3.14 -m venv .venv
```

```bash
.venv\Scripts\python -m pip install -r ml\localization\requirements.txt
```

`python --version`이 정확히 3.14.7인지 확인하세요. Backend는 NPZ 모델을 쓰므로 이 버전 고정이 필요 없습니다.

## 데이터

원본 CSV, manifest(참여자 이름 포함), 학습 run 폴더는 **저장소에 올리지 않습니다**(`.gitignore`). 팀 공유 저장소에서 받습니다.

- CSV 열: `csi_host_time, trigger_seq, rx_index, rssi, csi_len, iq_pairs` (+ 사용하지 않는 카메라 열)
- 파일 이름: `<MMDD>_<HH>시[반]_<p01..p10><이름><회차>.csv`, 사람 없음은 `<MMDD>_<HH>시[반]_빈공간<회차>.csv`
  - 이름은 수집 때의 한글 이름(2~5자)입니다. 문서·테스트 예시는 **한 글자 가명(A, B, …)**을 쓰며 파서가 둘 다 받습니다.
- 배치 `layout_02`, RX 입력 순서 0~4, CSI 384바이트(HT40), 각 RX의 앞 2쌍 제외
- split은 **세션(날짜·시간대) 단위**로 나눕니다. 같은 세션·사람·회차가 다른 split에 섞이면 거부합니다.

## 학습과 배포

1. 노트북 `01_Train_and_Evaluate.ipynb`에서 manifest 작성 → split 지정 → 학습(train으로 fit, validation으로 선정). test는 모델 고정 후 별도로 한 번만 평가합니다.
2. 결과 run 폴더(`runs/run_<날짜>_<시각>_<id>/`)는 통째로 보관합니다. 모델 파일 하나만 떼어 옮기지 않습니다.
3. Backend에 배포:

```bash
.venv\Scripts\python ml\localization\export_portable_model.py --run <runs\run_...> --replace
```

   선정된 Ridge를 `pc/backend/localization/models/ridge_portable.{npz,json}`로, validation 창 40개를 `pc/backend/tests/fixtures/selfcheck_fixture.npz`로 씁니다. 모든 validation 창에서 NPZ와 원본 모델의 점수·판정이 같은지 확인하고, 다르면 실패합니다. test split은 읽지 않습니다.
4. 특징 계산(`location_core.py` 등)을 바꾸면 `pc/backend/localization/`의 같은 파일도 함께 고치고(상대 import만 다름) 다시 내보냅니다.

## 실시간 확인 GUI

- USB 직결: `python ml/localization/csi_live_gui.py --port COM8 --run-dir <run>`
- 보드 경유 Ethernet: `python ml/localization/tools/csi_live_gui_ethernet.py --run-dir <run> --port 192.168.10.2:5000`
  - TCP 수신은 `pc/backend`의 코드를 그대로 사용합니다. TX 명령은 PS가 담당합니다.
  - 보드는 포트당 PC 한 대만 받으므로 Backend와 동시에 5000번에 붙이지 않습니다.
- 보드 없이 시험: [`pc/backend/tools/replay_ps_server.py`](../../pc/backend/tools/replay_ps_server.py)로 녹화 CSV를 TCP로 재생하고 연결 칸에 `127.0.0.1:5000`
- 화면의 "입력 부족 / 대기"(STATUS 없음, RX 누락, 창 부족)는 사람 없음(empty)과 다릅니다.

## 현재 배포 모델 — `run_20261008_091144_37cf3fcf`

상세: [`results/run_20261008_091144_37cf3fcf/`](results/run_20261008_091144_37cf3fcf)

| split | 세션 | 참여자(가명) | 파일 |
|---|---|---|---|
| train | 10/03 19·20·22시, 10/04 14시반~21시(9개), 10/06 14시, 10/07 9시반 | A–F | 562 |
| validation | 10/07 13시 | C, F | 46 |
| test (미평가) | 10/07 16시 | A, B, C, E, F | 85 |

| 모델 | val 정확도 | val balanced acc | val macro F1 |
|---|---|---|---|
| **Ridge (선정)** | 94.5% | **96.2%** | 95.9% |
| kNN | 87.9% | 85.4% | 84.1% |
| MLP | 87.6% | 89.9% | 86.2% |

- 지점 p01~p09와 empty는 validation에서 재현율 97~100%.
- **p10(앉기) 재현율 60.8%**: 오답은 주로 p02(20창), empty(6창), p08(3창). 사람에 따라 차이가 큼(F의 p10 3파일은 모두 정답, C는 다수 오답). 시연·평가에서 앉기 결과는 따로 확인하세요.
- validation은 2명·1세션입니다. 성능은 2초 창(겹침 없음) 단위이며, 같은 파일의 창은 독립 시행이 아닙니다. 실시간은 0.5초마다 판정해 창이 75% 겹칩니다. 새 날짜·새 사람·정지·입퇴장 조건 성능은 아직 측정하지 않았습니다. test는 아직 열지 않았습니다.
- 모델에 RX MAC이 저장되어 있지 않아, 실행 시 STATUS의 RX 번호↔MAC↔위치를 사람이 확인해야 추론이 시작됩니다.

## 테스트

```bash
.venv\Scripts\python -m unittest discover -s ml\localization\tests
```
