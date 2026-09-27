# Encoder 작업본 (E-01~)

`cnn_rtl/others/CNN_Encoder/` 의 **합성 대상 6개 파일을 복사**한 작업본이다.
2026-09-26 사용자 결정으로, 동우에게 요청하는 대신 우리가 먼저 고치고
동작 등가성을 증명한 뒤 패치를 전달한다. M00_AXI(R-01)와 같은 방식이다.

## 원본과의 관계

- **원본은 `cnn_rtl/others/CNN_Encoder/` 이며 읽기 전용이다. 수정하지 않는다.**
  등가성 대조의 기준이 되므로 반드시 남겨 둔다.
- 복사 시점의 원본 해시: `cnn_rtl/docs/E-01_원본_기준해시.txt`
- 여기서 수정한 내용의 **원본 대비 diff 가 동우에게 전달할 패치**다.

## 복사한 파일 (복사 시점에는 원본과 바이트 동일)

    CNN_Encoder.v  Conv_MAC.v  requant_stage.v  gelu_stage.v  Pool.v  Buffer.v

동우의 TB(`tb_*.v`)와 생성 스크립트(`gen_*.py`)는 복사하지 않았다.
필요하면 `others/CNN_Encoder/` 에서 직접 읽는다.

## E-01 에서 바꿀 것

1. `Pool.v` / `gelu_stage.v` / `Buffer.v` 에 `` `timescale 1ns / 1ps `` 추가
2. `Buffer.v` 의 저장소를 **넓은 쪽 기준**으로 선언해 BRAM 추론이 되게 한다
   - 현재: 좁은 쪽(11,520 x 8-bit) 선언 + 한 클록에 8주소 쓰기 → BRAM 불가
   - 목표: 넓은 쪽(1,440 x 64-bit) 선언 + 클록당 1주소 쓰기,
     읽기는 word 를 읽고 `raddr` 하위 비트로 byte 선택
   - **읽기 지연 1 cycle 유지** (명세 `06_Encoder` r33/r34)
3. `CNN_Encoder.v` / `Conv_MAC.v` / `requant_stage.v` 는 건드리지 않는다

## 반드시 지킬 것

- 명세 `06_Encoder` 의 포트·폭·타이밍 계약을 바꾸지 않는다
- **원본과 출력이 비트 단위로 같아야 한다.** `enc_start`~`enc_done` 전 구간 대조
- `enc_done` 까지 **1,278,890 cycle** (Claude 실측값) 유지
