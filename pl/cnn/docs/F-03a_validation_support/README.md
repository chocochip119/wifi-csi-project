# F-03a 재현 보조

이 파일을 새 scratch 폴더로 복사해 사용한다. RTL이나 golden 원본을 수정하지 않는다.
경로 기본값은 `D:/2609_final_project`, 도구는 Vivado 2020.2이다.

1. `preflight.py`를 실행한다. blob/golden manifest SHA와 line 수, 독립 requant/pose 계산을 확인하고 `requant_sim`에 파일과 `F03A0001` guard를 만든다.
2. `run_requant.py`를 실행한다. RTL은 xvlog, TB는 xvlog -sv로 컴파일한다. 27 case 전체 실행, 성공 표식과 `$finish` 및 FAIL/Fatal/MISMATCH 부재를 모두 검사한다.
3. 합성 fixture 두 개의 `.v.txt`를 scratch에서 `.v`로 복사한다. `run_synth.py fc_requant_ooc`와 `run_synth.py fc_mac_requant_ooc`로 각각 측정한다. **이번 측정값은 WNS −3.494 ns이므로 합성 성공 후 runner가 의도적으로 exit 1로 중단한다.** RTL을 바꿔 통과시키라는 뜻이 아니다.
4. Encoder 전후 합성을 재현하려면 현재 `rtl/encoder` 6개 파일을 scratch의 `encoder_before`에 복사한 후, 그 사본의 requant만 `requant_stage_before.v.txt`로 교체한다. 원본 파일은 바꾸지 않는다. `run_synth.py encoder_before`, 이어 `run_synth.py encoder_after`를 실행한다.

실행 예(Python 경로는 환경에 맞게 지정):

```text
python -X utf8 -u preflight.py
python -X utf8 -u run_requant.py
python -X utf8 -u run_synth.py encoder_before
python -X utf8 -u run_synth.py encoder_after
python -X utf8 -u run_synth.py fc_requant_ooc
python -X utf8 -u run_synth.py fc_mac_requant_ooc
```

`run_synth.py`는 기존 `syn_check.tcl`/XDC를 읽고 timing/loop 검사를 추가하는 scratch Tcl을 만든다. 합성 CWD는 기존 `cnn_rtl/syn`이다. before/after 및 FC 합성 수치는 보고서와 전문 로그에서 확인한다. 이 fixture는 F-03b/c의 FC 제어 구현이 아니다.

기존 24 TB의 실제 실행 명령·원문 출력·사용 runner는 `../F-03a_regression_logs`에 보존했다. 그 runner는 당시 scratch 경로를 포함하므로 재현 시 새 scratch 경로와 reference 사본, zero golden, preflight 파일을 준비해야 한다. G-02의 `h1_verified.txt`는 저장된 `run_g02.py`가 manifest/SHA를 확인한 뒤 작성한다. E-01 reference는 `others/CNN_Encoder` 원본에 module 이름 분리와 timescale만 적용한 scratch 사본이며 해당 단계 보고서의 절차를 따른다.

보조 Python 3개는 syntax check도 통과했다. 실제 이번 실행 명령과 출력은 상위 보고서의 로그에 있으며, 스크립트 설치나 다음 단계 실행을 자동 예약하지 않는다.
