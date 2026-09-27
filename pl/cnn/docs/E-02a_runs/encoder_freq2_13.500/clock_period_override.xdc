create_clock -period 13.500 -name ACLK [get_ports -filter {NAME =~ *ACLK || NAME == clk}]
