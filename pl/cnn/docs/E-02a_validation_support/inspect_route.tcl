# Re-open the completed route without rerunning implementation or changing RTL.
set dir [lindex $argv 0]
open_checkpoint [file join $dir routed.dcp]
report_route_status -file [file join $dir route_status_reopened.rpt]
report_timing -max_paths 3 -nworst 1 -input_pins -delay_type max -file [file join $dir reopened_paths.rpt]
set starts {}
foreach p [get_pins -hierarchical -filter {REF_PIN_NAME == C && NAME =~ *param3_reg*}] {
    if {[regexp {param3_reg\[69\].*/C$} [get_property NAME $p]]} {lappend starts $p}
}
if {[llength $starts] > 0} {
    report_timing -from $starts -max_paths 3 -nworst 1 -input_pins -delay_type max -file [file join $dir requant_paths.rpt]
    puts "E02A_REQUANT_STARTS $starts"
}
set path [lindex [get_timing_paths -delay_type max -max_paths 1] 0]
puts "E02A_REOPENED_WNS [get_property SLACK $path]"
set f [open [file join $dir failing_paths.tsv] w]
foreach p [get_timing_paths -delay_type max -slack_lesser_than 0 -max_paths 5000 -nworst 1] {
    puts $f "[get_property SLACK $p]\t[get_property STARTPOINT_PIN $p]\t[get_property ENDPOINT_PIN $p]"
}
close $f
puts "E02A_CHECKPOINT_VERIFIED"
exit 0
