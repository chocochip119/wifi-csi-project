# G-01 golden 생성 도구

고정된 v6/v2 네트워크 구조의 blob과 INT8 입력을 참고 C++ 모델로 실행한다.
RTL/TB나 참고 저장소를 수정하지 않는다. 실제 RTL과의 수치 대조는 G-02 범위다.

## 실행

PowerShell, 작업 루트 `D:\2609_final_project`:

```powershell
python .\cnn_rtl\golden\build_golden.py
```

현재 PC의 검증된 Python을 직접 지정하는 명령:

```powershell
& 'C:\Users\kccistc\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' .\cnn_rtl\golden\build_golden.py
```

현재 blob과 `test_vectors.h:test_input`을 사용해 `golden_current/`에 생성한다.
새 모델에는 별도 출력 폴더를 사용한다:

```powershell
python .\cnn_rtl\golden\build_golden.py --blob D:\models\new_weights.bin --input-bin D:\models\sample_i8.bin --output D:\2609_final_project\cnn_rtl\golden\golden_retrained
```

- `--input-bin`: 정확히 11,520 byte, signed INT8의 2의 보수 비트, `[channel][h][w]` 순서. header 없음.
- 생략하면 기존에 양자화된 `test_input`을 쓴다. **새 input scale로 다시 양자화해 주지 않는다.**
- 새 input scale을 쓸 때는 동일한 실수 입력도 새 scale로 양자화한 파일을 공급한다.
- `--blob`: 422,992 byte, little-endian, magic/version/총 word 및 shift 범위를 검사한다.
- 같은 구조·같은 양자화 계약의 blob만 지원한다. 레이어/채널/입력 크기가 달라진 모델에는 그대로 쓰지 않는다.
- 출력과 원본/RTL/TB/생성 소스 폴더의 겹침은 거부한다. 서로 다른 참고 소스 버전의 동시 실행은 하지 않는다.

Python 표준 라이브러리만 필요하다. 기본 compiler는 `C:/msys64/ucrt64/bin/g++.exe`,
HLS include는 `C:/Xilinx/Vivado/2020.2/include`다. `--cxx`, `--hls-include`, `--reference-dir`로 바꿀 수 있다.
참고 C++에 쓰인 HLS pragma는 호스트 빌드에서 하드웨어 병렬 실행을 뜻하지 않는다.

## 생성 및 검사 순서

1. 참고 파일 4개를 `src/original/`에 byte 그대로 복사하고 SHA-256을 기록한다.
2. 사본에 관측 호출 10개 줄만 추가해 `src/full_pose_instrumented.cpp`와 diff를 만든다.
3. 원본 testbench, 파일 입력을 받는 원본 모델, 같은 입력을 받는 관측 모델을 빌드한다.
4. 원본 샘플이 `max_abs_err=0 invalid=0`인지 확인한다.
5. 지정한 blob과 입력으로 원본/관측 모델을 각각 실행해 최종 float32 **24개 비트 전량**을 비교한다.
6. 지정 입력과 blob이 원본 샘플과 byte까지 같을 때만 기존 `test_expected_pose`와 비교한다.
7. 덤프 길이·형식, 3,072 byte→384 word 패킹을 검사하고, FC의 누산/requant/LUT/최종 scale을 Python으로 독립 재계산한다.
8. 성공 시 `manifest.json`의 `status=COMPLETE`와 `PASS: G-01`을 기록한다.

기존 기대값을 새 모델에 적용해 오류로 판정하거나, 새 모델이 기존 기대값을 통과한 것으로 표시하지 않는다.
실행 실패 시 종료 코드가 0이 아니다. 갱신 중인 출력의 manifest는 `INCOMPLETE`이므로 사용하지 않는다.
데이터를 사용할 때 해당 실행의 종료 코드 0, PASS, COMPLETE, blob/input SHA를 함께 확인한다.

빌드 실행 파일은 `%TEMP%/codex-g01-build/<내용 해시>/`에 둔다. 동일 소스·compiler의 재실행은 빌드 캐시를 쓴다.
매 실행의 blob/input snapshot은 별도 scratch 하위 폴더를 쓰며, golden 생성물에는 실행 파일을 넣지 않는다.
`run.log`에는 실제 명령, 출력 전문, exit code와 wall-clock 시간이 남는다.

## 다음 검증에서 사용할 파일

- `input_i8.hex`: Encoder에 공급할 입력 11,520 byte.
- `encoder_flat_i8.hex`: Encoder 결과 3,072 byte.
- `encoder_flat_u64.hex`: 같은 결과를 RTL Pool 메모리 순서의 384 word로 묶은 파일.
- `fc1_gelu_i8.hex`, `fc2_gelu_i8.hex`, `fc3_i8.hex`: FC 단계 최종 INT8.
- `fc1_acc_i32.hex` ~ `fc3_acc_i32.hex`: bias까지 더한 requant 직전 signed int32.
- `pose_f32.hex`, `pose_f32.txt`: INT8 pose에 output scale을 곱한 참고 모델의 float 결과.

모든 세부 형식·순서와 hook 위치는 [dump_hooks.md](dump_hooks.md)에 있다.
현재 결과의 해시는 [golden_current/manifest.json](golden_current/manifest.json)에 있다.

## 도구 자체 확인

```powershell
python .\cnn_rtl\golden\verify_tool.py
```

현재 golden을 먼저 생성한 뒤 실행한다. scratch에서 반복 재현, 실제로 다른 blob, 별도 입력,
exporter의 shift 경계, 잘못된 shift/사라진 hook 거부를 검사한다. RTL 시뮬레이션은 실행하지 않는다.
FC3을 0으로 만든 시험 blob은 재학습 결과가 아니며 도구가 인자 파일을 실제 소비하는지 확인하는 자료다.
