create_clock -period 13.160 -name ACLK [get_ports -filter {NAME =~ *ACLK || NAME == clk}]
