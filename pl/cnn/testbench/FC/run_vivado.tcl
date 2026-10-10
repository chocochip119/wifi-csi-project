# vivado -mode batch -source pl/cnn/testbench/FC/run_vivado.tcl -tclargs top 5
set here [file dirname [file normalize [info script]]]
set rtl [file normalize [file join $here ../../rtl/FC]]
set test top
set rx 5
if {$argc > 0} { set test [lindex $argv 0] }
if {$argc > 1} { set rx [lindex $argv 1] }
if {$test ni {fifo mac requant gelu memories controller top}} { error "Unknown FC test: $test" }
if {$rx ni {3 5}} { error "RX must be 3 or 5" }
set work [file normalize [file join [pwd] build fc_vivado_${test}_rx${rx}]]
file mkdir $work
cd $work
puts [exec python [file join $here gen_vectors.py] --rx $rx]
create_project -force fc_test [file join $work project] -part xc7z020clg400-1
add_files [glob [file join $rtl *.v]]
set bench [file join $here tb_fc_${test}.v]
add_files -fileset sim_1 $bench
set_property file_type SystemVerilog [get_files $bench]
set_property top tb_fc_${test} [get_filesets sim_1]
if {$test eq "top"} { set_property generic RX=$rx [get_filesets sim_1] }
set_property xsim.simulate.runtime all [get_filesets sim_1]
update_compile_order -fileset sim_1
# Keep fixture files in the xsim working directory, where $readmemh resolves paths.
set simdir [file join $work project fc_test.sim sim_1 behav xsim]
file mkdir $simdir
foreach path [glob [file join $work *.hex]] { file copy -force $path $simdir }
launch_simulation -simset sim_1 -mode behavioral
close_sim
close_project
