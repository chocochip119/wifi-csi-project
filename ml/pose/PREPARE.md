# CSI CSV 전처리와 RX mask 검증

`prepare.py`는 참고 레포 `ziziccc/wifi-csi-pose`의 `ML/src/prepare.py`를 바탕으로 만든 독립 실행 전처리기다. 팀 레포에 기존 전처리 파일이 없어 이 위치에 추가했다. CNN 구조나 학습 코드를 변경하는 작업은 아니다.

## 실행

Python 3.10 이상과 NumPy가 필요하다. 저장소 루트에서 실행한다.

```powershell
python -m pip install numpy
python ml/pose/prepare.py --input-dir <수집한_CSV_폴더> --output-dir ml/pose/data_cache
```

현재 PC의 기존 학습 환경을 사용하는 경우:

```powershell
& .\.venv\Scripts\python.exe .\ml\pose\prepare.py --input-dir <수집한_CSV_폴더> --output-dir .\ml\pose\data_cache
```

현재 RX5 직접 전처리에는 기본값을 바꾸는 인자를 명시한다.

```text
python ml/pose/prepare.py --input-dir <수집한_CSV_폴더> --output-dir ml/pose/data_cache --node-count 5
```

기본 파일 패턴은 `sync_csi_pose*.csv`이며 하위 폴더도 탐색한다. 기본 RX는 3개, remap은 `esp32_htltf_ht40_above_nonstbc`, seed는 42다. `--pair-count 0`은 첫 유효 행에서 I/Q 쌍 개수를 추론한다. 수신 규격을 알고 있다면 `--pair-count 192`처럼 명시할 수 있다.

같은 부모 폴더의 파일을 그룹으로 묶고, 그룹마다 test 1개를 먼저 확보한 뒤 남은 파일을 train/val에 배정한다. 기본 설정에서 각 그룹에 파일 3개 이상이 있어야 세 split을 모두 채울 수 있다. 이는 최소 분할 조건이며 실제 데이터 충분성을 의미하지 않는다.

## 수정한 유효성 검사

기존 코드는 `iq_pairs="[]"`를 0 벡터로 반환한 뒤 `mask=1`로 표시했다. 이제 빈 CSI를 거부하므로 해당 RX의 base와 mask는 초기 0을 유지한다.

- `trigger_seq`는 0..4294967295의 십진 정수여야 한다. 잘못된 값/빈 값은 해당 행만 제외하고 전체 CSV 처리를 계속한다. 숫자로 파싱한 값으로 그룹화한다.
- JSON 최상위 값은 비어 있지 않은 배열이어야 한다.
- 각 항목은 정확히 `[I, Q]` 두 값으로 구성한다.
- I/Q는 `-128..127` 정수다. bool, 소수, 문자열, null, NaN, 무한대는 거부한다.
- 기본 HT-LTF 모드는 원본 I/Q 128쌍 또는 192쌍을 지원한다. 파일들을 처리하는 한 실행 안에서는 설정/추론한 쌍 개수와 정확히 일치해야 한다. 짧은 입력의 0-padding이나 긴 입력의 묵시적 잘라내기를 하지 않는다.
- `--subcarrier-remap none`은 양의 쌍 개수를 지원한다. 결합 LTF 모드 `esp32_ht40_above_nonstbc`는 64/128/192쌍을 지원하며, 실제 segment 개수에 맞춰 출력 크기와 metadata를 기록한다.
- 최종 특징이 예상 크기의 유한값인지 확인한 뒤에만 base를 대입하고 mask를 1로 바꾼다.
- 길이 추론에도 같은 검사를 적용하므로 앞쪽의 깨진 JSON이나 빈 행이 추론을 중단시키지 않는다.

**측정된 I/Q가 모두 0인 정상 길이 배열은 유효하다.** 정상 데이터의 전처리 결과가 0이라는 이유로 누락 처리하지 않는다. mask는 신호 품질 점수나 사람 유무가 아닌, 해당 프레임에서 유효 CSI 기록을 처리했는지를 나타낸다.

유효 데이터의 log-power, 정규화/clip, HT-LTF 순서, base/delta/mask 채널 배치, 정답 좌표 정규화, 파일 분할은 참고 방식대로 유지한다. RX 누락을 과거 값으로 채우는 forward-fill은 Dataset 단계의 역할이며, 이 전처리기는 그 정책을 바꾸지 않는다.

## 출력과 오류 확인

```text
train.npz / val.npz / test.npz / metadata.json
```

NPZ에는 `features`, `labels`, `file_ids`, `trigger_seq`, `frame_size`를 저장한다. 기본 RX3의 프레임 특징은 `[N,9,128]`, RX5는 `[N,15,128]`, 정답은 `[N,24]`다. window를 묶은 RX5 학습 입력은 `[B,15,128,10]`이다. [학습 순서](README.md)와 [INT8 계약](INT8.md)을 참고한다. 각 프레임에서 유효한 RX가 하나라도 있으면 나머지 RX의 mask는 0으로 남기고 프레임을 저장한다. 모두 무효이면 원본처럼 프레임을 제외한다.

`metadata.json`의 `splits.<train|val|test>.summary.csi_quality`에서 RX별 상태를 확인한다.

| 필드 | 의미 |
|---|---|
| `invalid_trigger_rows` | trigger_seq가 빈 값/잘못된 정수/uint32 범위 밖인 행 수 |
| `invalid_rx_rows` | RX 번호가 없거나 범위 밖인 행 수 |
| `rx.<번호>.accepted_rows` | 유효한 CSI 행 수 |
| `rx.<번호>.rejected_rows` | CSI 검증에서 거부한 행 수 |
| `rx.<번호>.missing_frames` | 해당 RX의 유효 데이터가 없는 trigger 그룹 수 |
| `rx.<번호>.reasons` | `empty` / `format` / `value` / `length` / `feature`별 거부 수 |

RX별 집계는 **관절 정답이 완전한 trigger 그룹만 대상으로 하며 forward-fill 이전 기준**이다. `invalid_trigger_rows`는 그룹 생성 전에 CSV의 모든 행에서 집계한다. missing_frames에는 행 자체가 없는 경우와 잘못된 행만 있는 경우가 모두 포함된다. 모든 RX가 무효라 NPZ에서 제외된 그룹도 집계한다. 따라서 accepted_rows와 저장 프레임 수, missing_frames는 서로 다른 단위이며 단순히 더하거나 빼서 해석하지 않는다.

모든 행이 무효라 쌍 개수를 추론할 수 없으면 명확한 오류로 중단한다. 원본 수집 규격에 맞춰 데이터를 고친 후 다시 실행한다. 기존에 만들어 둔 NPZ의 잘못된 mask는 자동 수정되지 않으므로 **이 변경을 사용하려면 CSV에서 cache를 다시 생성**해야 한다.

## 회귀 테스트

```powershell
python -m pip install numpy pytest
python -m pytest ml/pose/tests/test_prepare.py -q
```

테스트는 저장소 밖의 참고 코드, 실측 데이터, 모델 가중치나 학습 패키지에 의존하지 않는다. 합성 CSV로 빈 입력과 정상 0의 구별, 값/길이 검사, 손상된 행 뒤의 길이 추론, NPZ mask/정답, metadata 집계 및 CLI 실행을 검증한다.
