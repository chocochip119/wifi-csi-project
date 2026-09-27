# 단독(out-of-context) 합성용 잠정 제약. 목표 클록 100 MHz.
# 보드·클록은 D10 미결이므로 확정값이 아니다.
create_clock -period 10.000 -name ACLK [get_ports -filter {NAME =~ *ACLK || NAME == clk}]
set_input_delay  -clock ACLK 2.000 [get_ports * -filter {DIRECTION == IN  && NAME !~ *ACLK && NAME != "clk"}]
set_output_delay -clock ACLK 2.000 [get_ports * -filter {DIRECTION == OUT}]
