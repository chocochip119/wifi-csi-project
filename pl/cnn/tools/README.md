# 팀 저장소에서 검증하기

Python 3 표준 라이브러리와 Vivado 2020.2를 사용한다. 경로는 스크립트 위치에서 계산한다.
아래 명령은 **저장소 루트** 기준이다.

```powershell
python pl/cnn/tools/verify_sources.py
python pl/cnn/tools/run_checks.py --vivado-bin C:/Xilinx/Vivado/2020.2/bin --suite smoke
python pl/cnn/tools/run_checks.py --vivado-bin C:/Xilinx/Vivado/2020.2/bin --suite core
```

smoke는 S00 control, ctrl status, M00 read, Top LOAD 기본 10조건, 실제 blob Loader의 5개 TB다.
core는 S00 4개·상태/CSR 2개·Top 4개·M00 4개·모형 1개·Loader 4개, 총 19 TB다.
지원 목록을 제공하는 것과 이번 업로드에서 전부 재실행한 것은 구분한다. 이번 실행 범위는 ../docs/UPLOAD_VERIFICATION.md를 본다.
결과는 runs/새 타임스탬프 폴더에 생성한다. XSIM exit code뿐 아니라 최종 PASS, finish, 오류·경고 부재를 검사한다.
실제 blob은 해시를 대조한 후 실행 폴더의 blob.bin으로 복사해 한글 plusarg 경로 문제를 피한다.

## 소스 선택

- core_rtl.f: 핵심 RTL 9개. 단일 완성 top을 뜻하지 않는다.
- encoder_rtl.f: 수정 Encoder 6개. reference/CNN_Encoder와 중복 컴파일하지 않는다.
- fc_work_rtl.f: FC 개발분 4개와 공용 requant. 제어/후처리를 포함한 완성 FC가 아니다.
- RTL은 xvlog, TB/모형은 xvlog -sv. pose_cnn은 fc_stub를 포함한 시뮬레이션용 통합 top이다.

## 심화 검증의 준비 조건

기존 docs의 runner에는 당시 PC 절대 경로가 남아 있다. 그대로 실행하지 말고 해당 실행의 staging 규칙을 확인한다.
tb_encoder_equiv는 reference 모듈 이름 분리와 blob 준비, tb_golden_encoder는 SHA preflight 및 sample/zero 파일이 필요하다.
tb_fc_mac/tb_fc_requant는 blob·golden을 staging하고 해시 확인 후 preflight_ok를 생성한다.
tb_pose_cnn_core의 blob 경로는 원본 TB에 하드코딩돼 있다. 이번 업로드에서 해당 TB 내용을 바꾸지 않았다.
guard 파일만 임의로 만들어 검증을 건너뛰지 않는다.

G-01 새 golden 생성은 원래 도구를 바꾸지 않고 저장소 경로를 명시하는 launcher를 사용한다.

```powershell
python pl/cnn/tools/build_golden_here.py --cxx C:/msys64/ucrt64/bin/g++.exe --hls-include C:/Xilinx/Vivado/2020.2/include
```

결과 기본 위치는 pl/cnn/runs/golden_generated다. 기존 golden_current를 덮어쓰지 않는다.
현재 golden은 업로드 당시 기준값이며 재학습 모델 적용은 별도 계약/검증이 필요하다.
