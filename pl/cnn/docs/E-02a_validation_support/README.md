# E-02a 실행 보조 자료

RTL/TB가 아닌 Vivado 실행·보고서 추출용 스크립트 사본이다. 시뮬레이션은 실행하지 않았다.
`fc_mac_requant_ooc.v.txt`는 F-03a fixture와 byte 동일하다.

재현 시 새 scratch 디렉터리에 이 파일들을 복사하고 fixture의 이름만
`fc_mac_requant_ooc.v`로 둔다. `prepare.py`는 최초 보호 해시를 기록하는 용도이며
이미 저장된 before.json 위에 다시 실행하지 않는다. `run_impl.py`는 새로운 run tag를
필수로 사용하므로 기존 로그를 덮지 않는다. 각 full.log 첫머리에 실제 명령 전체가 있다.

`impl_check.tcl`는 원본 100 MHz XDC를 그대로 읽고, 주기가 10 ns가 아닐 때만
실행 폴더에 clock_period_override.xdc를 만들어 create_clock 주기를 덮는다.
I/O delay 2 ns, part, timing exception은 바꾸지 않는다.

`inspect_route.py`는 기존 routed.dcp를 열어 경로를 읽을 뿐 P&R을 반복하지 않는다.
`extract_segments.py`는 report_timing의 핀별 시각과 routed netlist를 대조한다.
`archive_support.py`는 전체 보호 파일 집합과 SHA-256을 다시 비교한다.

초기 두 setup_failure 실행은 Windows 역슬래시 출력 경로 정규화 오류로 합성 전에
종료됐다. 기본 10 ns 두 실행은 P&R 완료 후 2020.2 미지원 TIMING_POINTS 조회에서
종료 코드 1을 냈으며, 저장 checkpoint를 다시 열어 배선과 WNS를 검증했다.
첫 주기 변경 실행도 합성 전 get_ports 조회로 종료했고, 별도 XDC 방식으로 고쳐
새 run tag에서 재실행했다. 합성 전에 실패한 시도는 E4의 P&R 확인 횟수에 세지 않는다.
기본 두 실행의 완료된 P&R은 E1/E2의 유효 측정으로 포함하며 종료 코드 1도 그대로 보고한다.
