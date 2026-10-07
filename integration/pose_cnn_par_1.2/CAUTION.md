# pose_cnn_par IP 1.2 사용 시 주의사항

IP: `user.org:user:pose_cnn_par:1.2` (RX = 5)

이 IP는 Block Design에 넣을 때 **아래 두 가지를 지키지 않으면 에러나 경고 없이 오동작**합니다. Vivado의 Validate, 합성, 타이밍 검사로는 잡히지 않으니 직접 확인해야 합니다.

`20260930_cnn_soc` 프로젝트의 BD와 xsa는 두 조건을 모두 지키고 있어서 정상입니다.

---

## 1. 클록·리셋: m00 핀을 s00 핀과 같은 신호에 연결할 것

### 규칙

| IP 핀 | 연결 |
|---|---|
| `s00_axi_aclk`, `m00_axi_aclk` | **같은 클록 net** (예: `FCLK_CLK0`) |
| `s00_axi_aresetn`, `m00_axi_aresetn` | **같은 리셋 net** (예: `rst_ps7_0_100M/peripheral_aresetn`) |

### 이유

IP 내부는 **`s00_axi_aclk` 클록 하나와 `s00_axi_aresetn` 리셋 하나로만** 동작합니다. M00_AXI(DDR 접근) 로직도 s00 클록·리셋을 씁니다. `m00_axi_aclk`, `m00_axi_aresetn` 포트는 있지만 내부에서 쓰지 않습니다(`src/pose_cnn_v1_0.v` 185~186행).

그런데 IP 패키지 정보(`component.xml`)에는 "M00_AXI는 `m00_axi_aclk` 클록 도메인"이라고 적혀 있습니다. 실제 동작과 표시가 다릅니다.

### 지키지 않으면

`m00_axi_aclk`에 다른 클록(예: 150 MHz HP 포트 클록)을 연결한 경우:

- Vivado는 M00이 150 MHz라고 믿고 interconnect를 만들지만, 실제 M00 신호는 s00 클록으로 움직입니다. 결과적으로 **동기화 없이 클록 도메인을 넘나드는 버스**가 되어 DDR 읽기·쓰기가 간헐적으로 깨집니다.
- 타이밍 제약도 잘못 걸려서, 타이밍이 "통과"로 나와도 실제로는 보장되지 않습니다.
- Vivado의 클록 주파수 검사(FREQ_HZ)는 패키지에 적힌 `m00_axi_aclk`만 봅니다. **경고가 나오지 않습니다.**

`m00_axi_aresetn`에만 리셋을 건 경우:

- **아무 효과가 없습니다.** IP는 `s00_axi_aresetn`으로만 리셋됩니다.

### 확인 방법

BD에서 `pose_cnn_0`의 네 핀을 선택하고 연결된 net 이름을 확인합니다. 클록 두 개가 같은 net, 리셋 두 개가 같은 net이어야 합니다.

---

## 2. AXI 파라미터: 기본값에서 바꾸지 말 것

IP 설정 창(BD에서 IP 더블클릭)에서 아래 값을 바꿀 수 있게 열려 있지만, **RTL은 표의 값만 지원합니다.** 사용자가 바꿔도 되는 파라미터는 `RX`(1~7)뿐입니다.

| 파라미터 | 지원 값 (= 기본값) | 다른 값을 넣으면 |
|---|---|---|
| `C_M00_AXI_DATA_WIDTH` | **64** | 합성은 성공하지만 64-bit 데이터가 잘림 → **DDR 데이터 깨짐, 경고 없음** |
| `C_M00_AXI_ADDR_WIDTH` | **32** | 합성은 성공하지만 주소가 잘림 → **엉뚱한 DDR 주소 접근, 경고 없음** |
| `C_M00_AXI_BURST_LEN` | **16** (1~16 허용) | 범위 밖이면 합성 단계에서 에러로 중단 |
| `C_S00_AXI_DATA_WIDTH` | **32** | CSR 레지스터 접근 오동작 |
| `C_S00_AXI_ADDR_WIDTH` | **5** | CSR 레지스터 주소 해석 오동작 |

### 이유

- M00 RTL은 64-bit 전송으로 고정돼 있습니다(`WSTRB = 8'hff`, `AWSIZE = 3'd3`, 내부 데이터선 64-bit).
- 폭 검사는 `synthesis translate_off` 안에 있어서 **시뮬레이션에서만** 동작합니다.
- GUI의 값 검사 함수(`xgui/pose_cnn_v1_0_v1_0.tcl`)도 모든 값을 통과시킵니다.

### 확인 방법

IP 설정 창에서 `RX` 외의 값이 위 표와 같은지 확인합니다. 또는 `.xci` 파일에서 `C_M00_AXI_*`, `C_S00_AXI_*` 값을 확인합니다.

---

## 3. 체크리스트 (이 IP를 새 BD에 넣을 때)

- [ ] `s00_axi_aclk`와 `m00_axi_aclk`가 같은 클록 net이다
- [ ] `s00_axi_aresetn`과 `m00_axi_aresetn`이 같은 리셋 net이다
- [ ] 그 클록은 타이밍이 통과한 주파수 이하다 (현재 100 MHz에서 WNS +0.095 ns)
- [ ] IP 설정에서 `RX` 외의 파라미터를 바꾸지 않았다
- [ ] M00_AXI는 PS `S_AXI_HP0`(64-bit)에, S00_AXI는 PS `M_AXI_GP0`에 연결했다

## 4. 근본 해결 (다음 IP 버전에서 할 일)

- wrapper에서 `m00_axi_aclk`, `m00_axi_aresetn` 포트를 제거하고, `s00_axi_aclk`가 `s00_axi`와 `m00_axi`를 모두 담당하도록 패키지 정보를 고칩니다(`ASSOCIATED_BUSIF = s00_axi:m00_axi`).
- GUI 검사 함수가 지원하지 않는 값에 `false`를 돌려주게 하고, RTL의 폭 검사를 합성에서도 동작하게 바꿉니다.

이렇게 고치면 위 1, 2번을 사용자가 기억하지 않아도 Vivado가 잘못된 연결과 설정을 막아 줍니다. 회로 동작은 바뀌지 않지만, 포트 구성이 바뀌므로 BD 업그레이드와 xsa 재생성이 필요합니다.
