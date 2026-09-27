# F-02 검증 재현

Vivado 2020.2 `C:/Xilinx/Vivado/2020.2/bin`, 프로젝트 `D:/2609_final_project` 기준이다.

1. `preflight.py`, `run_mac.py`, `run_mac_synth.py`를 새로운 scratch 디렉터리에 복사한다.
2. `fc_mac_storage_ooc.v.txt`도 복사하고 이름을 `fc_mac_storage_ooc.v`로 바꾼다. 이 파일은 합성 fixture이며 production RTL이 아니다.
3. Python으로 `preflight.py` 실행: manifest와 blob/golden 7개 파일의 SHA-256·크기/줄 수 확인 후 읽기 전용 원본을 scratch에 복사한다.
4. Python으로 `run_mac.py` 실행: 기본 12 case 전부 실행. preflight hash 재확인, xvlog/엘라보레이션 경고·오류 0, runtime 실패 부재와 최종 성공 표식을 검사한다.
5. Python으로 `run_mac_synth.py` 실행: MAC 단독과 MAC+저장소 3종을 합성한다. 임계 여유가 1.0 ns 미만이면 검수 중단 기준에 따라 중단한다.

명령·출력·exit code·wall-clock은 scratch에 남는다. 기존 `syn_check.tcl`과 100 MHz XDC를 재사용한다. 합성 fixture에서 FCW RAM은 Loader 소유 외부 인터페이스로 남기며 pose 쓰기도 외부 입력이다. 기능 TB에서는 실물 FCW RAM을 사용한다. requant/GELU/FC 제어를 이 fixture에 포함하지 않는다.

기존 23 TB의 실제 실행 명령·출력은 `../F-02_regression_logs/`에 보존했다. 해당 과거 runner는 실행 당시 scratch 경로와 E-01 reference 사본을 사용한다. 단독 MAC 재검증에는 위 파일들만 필요하다.
