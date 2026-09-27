# E-02a: read-only RTL measurement. No timing exceptions or RTL transformations
# are added here beyond the requested Vivado implementation commands.
# Usage: vivado -mode batch -source impl_check.tcl -nojournal -nolog -tclargs \
#   <top> <part> <period_ns> <default|performance> <output_directory> <source...>
# Read the original 100 MHz XDC. Only E4 overrides its clock period in memory.

if {$argc < 6} {error "Expected top part period mode output_directory source..."}
set top [lindex $argv 0]
set part [lindex $argv 1]
set period [lindex $argv 2]
set mode [lindex $argv 3]
set out_dir [file normalize [lindex $argv 4]]
set srcs [lrange $argv 5 end]
if {$part ne "xc7z020clg400-1"} {error "E-02a part must be xc7z020clg400-1"}
if {$mode ni {default performance}} {error "Unsupported implementation mode"}
if {![string is double -strict $period] || $period <= 0} {error "Invalid period"}
file mkdir $out_dir

proc e02a_stage {stage out_dir} {
    report_timing_summary -delay_type min_max -max_paths 3 -file [file join $out_dir ${stage}_summary.rpt]
    report_timing -max_paths 3 -nworst 1 -input_pins -delay_type max -file [file join $out_dir ${stage}_paths.rpt]
    set p [lindex [get_timing_paths -delay_type max -max_paths 1] 0]
    set h [lindex [get_timing_paths -delay_type min -max_paths 1] 0]
    if {$p eq ""} {error "No constrained setup timing path at $stage"}
    set wns [get_property SLACK $p]
    set whs [get_property SLACK $h]
    set start [get_property STARTPOINT_PIN $p]
    set end [get_property ENDPOINT_PIN $p]
    set line "$stage\t$wns\t$whs\t$start\t$end"
    set f [open [file join $out_dir stages.tsv] a]
    puts $f $line
    close $f
    puts "E02A_STAGE $line"
    flush stdout
}

set status [catch {
    puts "E02A_CONFIG top=$top part=$part period=$period mode=$mode"
    puts "E02A_VERSION [version -short]"
    foreach source $srcs {
        # The optional E5 TB stub contains SystemVerilog, read unmodified.
        if {[file tail $source] eq "fc_stub.v"} {read_verilog -sv $source} else {read_verilog $source}
    }
    read_xdc [file join [file dirname [info script]] timing_100mhz.xdc]
    if {$period != 10.000} {
        # read_xdc is deferred until synthesis opens the design. A direct
        # get_ports here has no open design in Vivado 2020.2. Load only the
        # period override after the original XDC; all I/O delays stay intact.
        set override [file join $out_dir clock_period_override.xdc]
        set f [open $override w]
        puts $f [format {create_clock -period %s -name ACLK [get_ports -filter {NAME =~ *ACLK || NAME == clk}]} $period]
        close $f
        read_xdc $override
    }
    synth_design -top $top -part $part -mode out_of_context
    report_clocks -file [file join $out_dir clocks.rpt]
    e02a_stage post_synth $out_dir
    if {$mode eq "performance"} {
        opt_design -directive Explore
        place_design -directive ExtraTimingOpt
    } else {
        opt_design
        place_design
    }
    e02a_stage post_place $out_dir
    if {$mode eq "performance"} {phys_opt_design -directive AggressiveExplore} else {phys_opt_design}
    e02a_stage post_phys_opt $out_dir
    if {$mode eq "performance"} {route_design -directive Explore} else {route_design}
    e02a_stage post_route $out_dir
    report_route_status -file [file join $out_dir route_status.rpt]
    report_utilization -file [file join $out_dir utilization.rpt]
    report_drc -file [file join $out_dir drc.rpt]
    check_timing -verbose -file [file join $out_dir check_timing.rpt]
    write_checkpoint -force [file join $out_dir routed.dcp]
    write_verilog -force -mode funcsim [file join $out_dir routed_netlist.v]
    # Preserve path properties for E6. Vivado 2020.2 has no TIMING_POINTS
    # property; per-pin increments are in report_timing -input_pins above.
    set p [lindex [get_timing_paths -delay_type max -max_paths 1] 0]
    set f [open [file join $out_dir path_properties.txt] w]
    foreach prop [list_property $p] {puts $f "$prop\t[get_property $prop $p]"}
    close $f
    set f [open [file join $out_dir failing_paths.tsv] w]
    foreach p [get_timing_paths -delay_type max -slack_lesser_than 0 -max_paths 5000 -nworst 1] {
        puts $f "[get_property SLACK $p]\t[get_property STARTPOINT_PIN $p]\t[get_property ENDPOINT_PIN $p]"
    }
    close $f
    puts "E02A_IMPL_DONE top=$top period=$period mode=$mode"
} detail options]
if {$status} {
    puts "E02A_IMPL_FAILED $detail"
    puts [dict get $options -errorinfo]
    exit 1
}
exit 0
