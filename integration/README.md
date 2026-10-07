# Vivado 하드웨어 통합 자료

| 위치 | 내용 | 현재 해석 |
|---|---|---|
| `pose_cnn_1.1/component.xml` | Vivado IP 패키지 정의 | 패키지 버전 1.1 |
| `pose_cnn_1.1/src/` | AXI wrapper, CNN/FC/Loader와 RAM 복사본 | 원본 RTL과 함께 관리 |
| `pose_cnn_1.1/xgui/` | IP 파라미터 GUI Tcl | 패키징 시 함께 확인 |
| `design_1_wrapper.xsa` | 기존 PS/PL hardware export | 최신 RTL 적용 여부를 재검증해야 하는 기존 빌드 |

XSA 내부에는 `design_1.bda`, `design_1.hwh`, **`design_1_wrapper.bit`**, PS 초기화 파일과 metadata가 있습니다. 현재 checkout에 있는 XSA를 PR #29의 반올림 수정 후 새로 생성한 것으로 표시하지 않습니다.

## 원본과 복사본

원본은 [pl/cnn/rtl](../pl/cnn/README.md)입니다. Encoder, FC, Loader, top, AXI 디렉터리의 파일이 패키지에서는 `src/` 아래로 모여 있습니다. `requant_core.v`, `requant_stage.v`, `Pool.v`는 원본과 바이트가 같도록 맞췄습니다. 다른 RTL 변경도 필요한 패키지 파일과 함께 갱신해야 합니다.

패키지의 외부 top module은 `pose_cnn_v1_0`이며 core는 `pose_cnn`입니다. 파일/module 이름과 IP package version은 별개입니다.

## 보드 반영 순서

1. 원본 RTL과 패키지 소스, RX5 파라미터/CSR/DDR 연결을 확인합니다.
2. Vivado에서 IP를 다시 패키징하고 Block Design의 IP를 갱신합니다.
3. synthesis/implementation과 타이밍·자원을 확인한 뒤 bitstream 및 XSA를 export합니다.
4. 새 하드웨어에 맞춰 [PetaLinux/PS](../ps/README.md)의 Device Tree·주소·부트 이미지를 확인합니다.
5. 같은 최종 학습 가중치/input/output scale로 [golden](../ml/pose/INT8.md)과 실제 보드 결과를 비교합니다.

이번 문서 정리는 XSA·bitstream·소스 파일을 변경하지 않습니다. 기존 2026-09-30 보드 기록과 최신 소스의 검증 범위는 [점검 기록](../docs/reviews/2026-10-07-pc-integration.md)을 참고하세요.
