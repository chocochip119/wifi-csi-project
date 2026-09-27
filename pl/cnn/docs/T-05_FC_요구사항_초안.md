# FC 담당 지원에게 전달할 요구사항 초안 — T-05

2026-09-25. **전달용 초안이며 실제로 발송하지 않았다.** 기준은 사용자가 준 T-05 명세와 08_FC 계약이다. FC의 내부 연산 구조를 정하는 문서가 아니다. 실물 FC 결합·검수 및 D08 합의는 남아 있다.

## 확정 인터페이스

| 항목 | 요구 동작 | T-05 확인 방법 |
| --- | --- | --- |
| reset | 공통 clock의 동기식 active-low. 실행 상태·FIFO 포인터/개수·완료 표시를 초기화한다. RAM 전체를 지울 필요는 없다 | stub과 Top에 같은 reset 연결 |
| fc_start | idle일 때 받는 1-cycle 펄스. 진행 중 재START를 복구 방법으로 가정하지 않는다 | stub은 non-idle START에서 즉시 fatal |
| fc_sel | 2-bit 값을 fc_start 수락 edge에 저장. FC1은 0 | START 뒤 stub 입력 selector를 3으로 바꿔도 저장값 0과 전량 데이터 유지 |
| fc_done | 해당 단계의 결과가 버퍼/레지스터에 모두 기록된 뒤 1-cycle 펄스 | Top은 완료를 보관하고 DDR read 완료와 함께 판정 |
| FC1 FIFO | 512 × 64-bit = 4,096 B. full은 수락 edge에 적용되는 현재 용량을 나타낸다 | 표준 FIFO 모형으로 512개 full과 push/pop 순서 검사 |
| fifo_we/fifo_wdata | 별도 ready가 없다. we=1인 edge마다 정확히 한 word를 저장한다 | 49,152 word push/pop 전량 대조, X·초과 push·full push 검사 |
| fifo_full | full=1이면 Top은 fifo_we=0, mem_rd_ready=0으로 공급을 멈춘다 | 느린 소비/일시 정지/슬레이브 정체와 조합해 확인 |
| 전송량 | FC1마다 393,216 B = 49,152 word. FIFO를 여러 차례 채우고 비우는 스트림이다 | 정상 실행마다 push=pop=49,152, 최종 FIFO count=0 |

full인 cycle에 내부 pop이 가능하더라도 Top은 그 edge에 push하지 않는다. 가득 찬 FIFO가 다음 cycle에 여유를 표시하면 공급을 재개한다. FC는 공급에 공백이 있을 수 있음을 전제로 empty에서 읽지 않고 기다려야 한다. FIFO 소비 완료만으로 실제 FC 연산 완료를 대신하지 않는다.

## Top이 제공하는 동작

- ENC 완료 전이에 `fc_start=1, fc_sel=0`과 FC1 read START를 함께 발행한다.
- 주소는 **LOAD에서 저장한 load_base_reg + 5,936**이다. LOAD 뒤 PS가 WEIGHT_ADDR를 바꿔도 기존 모델의 FC1 weight를 사용한다. 다시 LOAD하면 base가 갱신된다.
- 정상 FC1은 `fifo_we = mem_rd_valid && !fifo_full`, `mem_rd_ready = !fifo_full`이다. 전송한 word 순서를 바꾸지 않는다.
- `fc_done`을 보관하므로 read가 끝나기 전에 펄스가 와도 놓치지 않는다. 단 이 방어 구조가 조기 완료를 허용하는 FC 계약은 아니다.
- FC1 read 오류를 관측하면 FIFO push를 중지하고 READY=1로 남은 AXI 데이터를 받아 버린다. read 완료 후 error=4를 기록한다. 현재 단계에는 FC abort를 발행하는 신호나 FC2 START가 없다.

## D08에서 정해야 할 오류 복구

**FC1 오류 뒤 단순 재START만으로 복구된다고 가정할 수 없다.** 실측 오류 case에서 FC는 1,285 word만 받았고, 나머지 47,867 word는 Top이 버렸다. AXI는 정상적으로 끝났지만 FC stub은 49,152 word를 채우지 못해 active 상태에 남았다. 다음 fc_start는 idle-only 계약과 충돌한다.

합의가 필요한 것은 실행 중 FC 중단/초기화 방법, FIFO 비우기, Encoder·Loader·cfg_ok와 함께 복구할 범위다. **공통 reset → 재LOAD → 재INFER**를 이번 복구 시험으로 사용할지 사용자에게 확인을 요청한 상태다. 이를 확정 정책이나 완료된 시험으로 기록하지 않는다. 공통 reset 이외의 전용 abort 포트는 추가하지 않았다.

M00의 read error는 오류 beat 수락 뒤 등록된다. 따라서 오류 beat 자체가 FIFO에 들어간 뒤 후속 push가 막힐 수 있다. 오류 실행의 중간 결과/FIFO 내용은 유효한 추론 결과로 사용하면 안 된다. 새로운 실행을 시작할 때 남은 데이터와 연산 상태를 어떻게 무효화할지는 D08 범위다.

## stub의 가정과 실물 요구를 구분할 항목

stub은 산술 연산을 하지 않는다. 소비 모드(매 cycle / 4 cycle마다 / seed 기반 난수 / 정지 후 재개)와 완료 지연은 Top 검사용이며 실물 FC의 처리율 목표가 아니다. 실제 처리율은 실물 FC로 다시 측정한다.

기본 완료는 모든 word 소비 후 설정 지연을 기다린다. read busy 하강과 같은 cycle 또는 먼저 완료하는 시험은 **명시적인 제어 시험용 완료 주입**이다. 정상 FC가 데이터를 다 받기 전에 결과 완료를 내도 된다는 의미가 아니다. 레벨 done 시험도 Top의 견고성을 검사하며 실물 계약은 1-cycle 펄스를 유지한다.

참고 실측: FC read 주소가 128 B 정렬이고 모형 DDR 지연 0일 때 빠른 소비는 55,296 cycle로 T-02b와 같다. 4 cycle당 한 word 소비는 194,561 cycle, FIFO full은 145,322 cycle이었다. 이는 실제 DDR 지연이나 실물 FC 성능을 예측한 수치가 아니다.

[T-05 구현·검증 기록](T-05_구현_검증기록.md)
