create_clock -period 14.000 -name ACLK [get_ports -filter {NAME =~ *ACLK || NAME == clk}]
