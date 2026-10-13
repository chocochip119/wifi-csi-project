# PL Location — Ridge 위치 분류 RTL

이 폴더는 Wi-Fi CSI의 위치 특징을 **FPGA에서 Ridge 선형 분류 연산**으로 처리하기 위한 하드웨어 원본 RTL과 테스트벤치를 관리합니다. 기본 PC Backend의 Portable Ridge와는 **계산 위치가 다른 별도 하드웨어 경로**이며, 해당 IP를 생성했다는 것과 실제 보드에서 실시간 위치 추론에 사용 중이라는 것은 다릅니다.

## 구현 기능

```text
PS: CSI/RSSI → 955개 위치 특징
              ↓ AXI4-Lite (가중치·Bias·특징 로드)
PL: ridge_axi_v1 → 클래스별 고정소수점 점수 계산
              ↓
PS: 결과 class code/점수 읽기
```

| 경로 | 내용 |
|---|---|
| [`rtl/ridge_axi_v1.v`](rtl/ridge_axi_v1.v) | AXI4-Lite 레지스터, 내부 모델/특징 저장, MAC·결과 레지스터 |
| [`testbench/tb_ridge_axi_v1.v`](testbench/tb_ridge_axi_v1.v) | XSim 기반 수치 golden·제어/오류·reset 테스트 |
| `testbench/generated/` | 특징·가중치·Bias·예상 점수/클래스 비교 벡터 |
| [`../../integration/ridge_axi_1.0/`](../../integration/README.md) | Vivado에서 사용하는 패키지 IP 복사본 |

## PS·PL 연결과 검증

Vivado 구성에서는 CNN IP와 별도로 **GP0의 AXI4-Lite Slave**로 연결되며 Ridge base는 **`0x43C10000`**입니다. PS가 모델을 전송한 뒤 commit을 수행해야 추론을 시작할 수 있습니다. 상세 레지스터와 연산 흐름은 [Integration README](../../integration/README.md)에 설명되어 있습니다.

[Integration 검증 현황](../../integration/README.md)은 XSim·합성·타이밍·XSA 내보내기 범위와 **실제 보드 MMIO·최종 위치 정확도 미검증**을 구분합니다. 기본 위치 실시간 실행은 [PC Backend](../../pc/backend/README.md), PS에서 위치를 계산하는 시험판은 [ps_location](../../ps_location/README.md)에 있습니다.
