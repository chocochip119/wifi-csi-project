# F-01 저장소 검증 재현

Vivado 2020.2 설치 경로 `C:/Xilinx/Vivado/2020.2/bin`, 프로젝트 경로 `D:/2609_final_project`를 사용하는 runner다.

1. 이 폴더의 `run_storage.py`, `run_synth.py`를 새 scratch 디렉터리에 복사한다.
2. `fc_storage_ooc.v.txt`도 같은 scratch로 복사하고 이름을 `fc_storage_ooc.v`로 바꾼다. 합성 전용 wrapper이므로 production RTL 폴더에 넣지 않는다.
3. Python으로 `run_storage.py`를 실행한다. 기본 실행에서 Y1~Y5 전부를 검증한다.
4. Python으로 `run_synth.py fc1_weight_fifo fc_storage_ooc`를 실행한다. 인자를 생략하면 hidden/pose를 포함한 4회 합성을 모두 수행한다.

runner는 실행 명령·출력·exit code·wall-clock을 scratch에 저장한다. 시뮬레이션은 exit code에 더해 PASS/finish와 ERROR/WARNING/FAIL/Fatal 부재를 검사한다. 합성 스크립트는 기존 `syn_check.tcl`과 100 MHz XDC를 읽고, 추가 자원·타이밍·루프 검사를 수행한다. 동봉한 `storage_syn.tcl`은 실제 실행본 기록이며 runner가 scratch 경로에 다시 작성한다.

기존 22 TB의 실제 명령·출력과 runner는 `../F-01_final_regression_logs/`에 보존한다. 해당 runner는 당시 scratch 경로를 사용하므로 다른 위치에서 재실행하려면 scratch 경로만 바꾼다. TB/RTL 기대값은 바꾸지 않는다.
