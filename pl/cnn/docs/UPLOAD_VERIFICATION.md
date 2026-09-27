# cnn 업로드 구성 검증 — 2026-09-27

팀 저장소 `D:/wifi-csi-project`의 실제 경로에서 Vivado 2020.2로 실행했다.
RTL/TB를 수정해 통과시킨 것이 아니라 인계본과 같은 바이트를 배치해 검증했다.

| 시험 | 결과 | xsim wall-clock(초) | 근거 |
|---|---|---:|---|
| tb_s00_axi_ctrl | PASS | 7.080 | [로그](upload_validation/20260927_201407_598250/tb_s00_axi_ctrl_run.log) |
| tb_ctrl_status | PASS | 4.750 | [로그](upload_validation/20260927_201407_598250/tb_ctrl_status_run.log) |
| tb_m00_read | PASS | 4.565 | [로그](upload_validation/20260927_201407_598250/tb_m00_read_run.log) |
| tb_top_load | PASS | 5.536 | [로그](upload_validation/20260927_201407_598250/tb_top_load_run.log) |
| tb_loader_real_blob | PASS | 4.409 | [로그](upload_validation/20260927_201407_598250/tb_loader_real_blob_run.log) |

Top LOAD는 기본 10 case 전체 실행. 실제 blob Loader는 422,992 B와 RAM 내용을 전량 대조했다.
최종 PASS 표식 + `$finish called` + exit code 0 + ERROR/WARNING/FAIL/Fatal 부재를 함께 확인했다.
RTL/TB 컴파일 및 각 elaboration의 오류·경고도 0이다.
smoke 컴파일·실행 명령 시간 합계는 49.496초다.
[명령·출력·종료코드·시간](upload_validation/20260927_201407_598250/results.json).

추가로 **RTL 20개 전체 컴파일 + 코어 TB 컴파일 + tb_pose_cnn_core elaboration**을 확인했다.
수정 Encoder와 FC 개발분, pose_cnn의 FC 모형 연결이 포함되며 오류·경고 0이다.
이 확인은 전체 코어 시뮬레이션이나 golden/합성 재실행이 아니다.
[세 명령·시간 기록](upload_validation/20260927_201505_integration_compile/results.json),
[전체 RTL 컴파일](upload_validation/20260927_201505_integration_compile/compile_all_20_rtl.log),
[코어 elaboration](upload_validation/20260927_201505_integration_compile/elaborate_pose_cnn_core.log).

업로드 RTL 20개와 기존 TB/모형 30개는 인계본과 SHA-256이 같다.
기존 팀 Encoder와의 실질 차이는 [diff](handover/team_encoder_before_vs_uploaded.diff)를 참조한다.
기존 팀 파일과 줄바꿈이 달라 Git에서는 6개 모두 변경으로 보일 수 있다. 의미 비교는 `git diff --ignore-space-at-eol`로 확인했다.
기존 팀 Encoder TB 8개 파일은 수정하지 않는다.

전체 기존 회귀·실물 Encoder golden·FC golden·합성/P&R은 이번 업로드에서 재실행하지 않았다.
그 결과는 기존 단계별 보고서의 범위와 한계를 따른다. 실제 FC 결합·전체 IP 완성·100 MHz 충족으로 표시하지 않는다.

업로드 payload는 ../UPLOAD_MANIFEST_SHA256.json에 기록하며 tools/verify_sources.py로 확인할 수 있다.
Vivado 새 생성물은 runs/에 남고 Git에서 제외한다. 이 문서에 연결한 텍스트 로그만 근거로 포함한다.
