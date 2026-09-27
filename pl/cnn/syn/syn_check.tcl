# 사용법:
#   vivado -mode batch -source syn_check.tcl -nojournal -nolog -tclargs <top> <part> <v파일...>
# 예:
#   vivado -mode batch -source syn_check.tcl -nojournal -nolog -tclargs \
#          pose_cnn_v1_0_S00_AXI xc7z010clg400-1 ../rtl/pose_cnn_v1_0_S00_AXI.v
#
# 목적: 래치 / 조합 루프 / 자원 / 타이밍을 한 번에 본다. 구현(P&R)은 하지 않는다.

set top   [lindex $argv 0]
set part  [lindex $argv 1]
set srcs  [lrange $argv 2 end]

foreach f $srcs { read_verilog $f }
read_xdc [file join [file dirname [info script]] timing_100mhz.xdc]

synth_design -top $top -part $part -mode out_of_context

puts "===== UTILIZATION ====="
report_utilization -hierarchical

puts "===== TIMING ====="
report_timing_summary -delay_type max -max_paths 3

puts "===== LATCH CHECK ====="
set latches [get_cells -hierarchical -filter {PRIMITIVE_TYPE =~ REGISTER.latch.*}]
puts "LATCH count = [llength $latches]"
if {[llength $latches] > 0} { puts "LATCHES: $latches" }

puts "SYN_CHECK_DONE"
