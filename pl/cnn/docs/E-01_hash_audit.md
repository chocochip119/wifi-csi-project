# E-01 원본·보호 파일·검증 후보 SHA-256

원본 14파일(Verilog 9개 포함), 기존 RTL/TB 33파일 무변경. 복사 직후 9개 Verilog 해시도 JSON에 보존했다.

공유 작업본은 외부 복사로 원본 상태이며, 동시 편집 종료 확인 전에는 덮어쓰지 않았다. 아래 후보 해시는 실제 시험·합성한 소스와 같다.

| 파일 | 원본 SHA-256 | 검증 후보 SHA-256 |
|---|---|---|
| Buffer.v | `78be32c2b479055d4b2bbbbd46a7cc8cb142f8c758ba09c637f3b57bf1d164f3` | `91173f7c50df58aee6750ede3a01f5aa64a9ce4f8fb10e032d9aca0ea7b5a602` |
| Conv_MAC.v | `c6328db582b6c435ff05849eb8644fa0bd2364858c0954fe713b1d361000ba18` | `c6328db582b6c435ff05849eb8644fa0bd2364858c0954fe713b1d361000ba18` |
| requant_stage.v | `4e11cf526482b43c448c9c7bf843c33c8802f74235da8d5ed31a7a9d2a80b7f0` | `4e11cf526482b43c448c9c7bf843c33c8802f74235da8d5ed31a7a9d2a80b7f0` |
| gelu_stage.v | `14cd1cd2cd19ee7b76873f91dd7c169176382daf161582726564ece258934d89` | `0c0b90d866198c317f49261fe07c5068c34dd6acbb67c95aede39aa19c5f405c` |
| Pool.v | `42414baea311e6e28ecf429bea445ec4c0d23de2839bb499088f34b654dcfbbe` | `dbf4f5e5f1a64bccf2d5e9190f916302c39153789c2d3ba55575e30c12079aff` |
| CNN_Encoder.v | `9543ccaa26e77e453903a999d06520f86b6cd61a2d14e9c31436e6c86351f17e` | `9543ccaa26e77e453903a999d06520f86b6cd61a2d14e9c31436e6c86351f17e` |

[전체 47파일 전후 해시 및 최초 9개 복사 기록](E-01_hash_audit.json)

| 회귀 TB | PASS/OBS 줄 수 | L-07과 동일 |
|---|---:|---|
| tb_axi4_slave_mem_model | 36 | 예 |
| tb_blob_decoder | 557 | 예 |
| tb_csr_ctrl_link | 12 | 예 |
| tb_ctrl_status | 38 | 예 |
| tb_loader_rams | 4 | 예 |
| tb_loader_real_blob | 92 | 예 |
| tb_m00_err | 150 | 예 |
| tb_m00_read | 37 | 예 |
| tb_m00_read_perf | 13 | 예 |
| tb_m00_write | 60 | 예 |
| tb_s00_axi_ctrl | 53 | 예 |
| tb_s00_axi_read | 14 | 예 |
| tb_s00_axi_regs | 25 | 예 |
| tb_s00_axi_write | 12 | 예 |
| tb_top_fc1 | 41 | 예 |
| tb_top_full | 83 | 예 |
| tb_top_infer | 46 | 예 |
| tb_top_load | 21 | 예 |
| tb_weight_param_loader | 48 | 예 |

총 1342개 관측 줄이 동일하다.
