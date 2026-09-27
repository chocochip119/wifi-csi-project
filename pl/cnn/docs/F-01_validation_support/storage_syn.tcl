source {D:/2609_final_project/cnn_rtl/syn/syn_check.tcl}

puts "F01_TIMING_CHECK"
check_timing -verbose
puts "F01_CRITICAL_PATH"
report_timing -delay_type max -max_paths 1
puts "F01_FLAT_UTILIZATION"
report_utilization
set paths [get_timing_paths -delay_type max -max_paths 1]
puts "F01_WNS [get_property SLACK $paths]"
foreach c [get_cells -hier -filter {REF_NAME =~ RAMB* || REF_NAME =~ RAM32* || REF_NAME =~ RAM64*}] {
    puts "F01_MEMORY $c [get_property REF_NAME $c]"
}
set loop_drc [get_drc_checks -quiet LUTLP-1]
if {[llength $loop_drc] > 0} {report_drc -checks $loop_drc}
puts "F01_SYN_DONE"
