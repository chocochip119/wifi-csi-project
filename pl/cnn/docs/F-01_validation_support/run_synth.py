from pathlib import Path
import subprocess,time,re,sys,json
r=Path(r'D:\2609_final_project');w=Path(__file__).parent
tops=sys.argv[1:] or ['fc1_weight_fifo','hidden_buffer','pose_buffer','fc_storage_ooc']
tcl=w/'storage_syn.tcl'
tcl.write_text('source {'+(r/'cnn_rtl/syn/syn_check.tcl').as_posix()+'}\n'+r'''
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
''',encoding='utf-8')
for top in tops:
 src=[r/f'cnn_rtl/rtl/fc/{top}.v'] if top!='fc_storage_ooc' else [r/f'cnn_rtl/rtl/fc/{n}.v' for n in ['fc1_weight_fifo','hidden_buffer','pose_buffer']]+[w/'fc_storage_ooc.v']
 cmd=[r'C:\Xilinx\Vivado\2020.2\bin\vivado.bat','-mode','batch','-source',str(tcl),'-nojournal','-nolog','-tclargs',top,'xc7z020clg400-1']+list(map(str,src))
 t=time.perf_counter();p=subprocess.run(cmd,cwd=r/'cnn_rtl/syn',stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 out=p.stdout.decode('utf-8',errors='replace').replace('\r\n','\n');elapsed=time.perf_counter()-t
 (w/('synthesis_'+top+'.txt')).write_text('CWD: '+str(r/'cnn_rtl/syn')+'\nCOMMAND: '+subprocess.list2cmdline(cmd)+'\n'+out+'\nEXIT_CODE: '+str(p.returncode)+'\nWALL_CLOCK_SECONDS: %.6f\n'%elapsed,encoding='utf-8')
 print(top,'exit=',p.returncode,'seconds=',round(elapsed,3),flush=True)
 print('\n'.join(l for l in out.splitlines() if any(k in l for k in ['ERROR:', 'WARNING:', 'F01_', 'LATCH count', 'Slice LUTs','Slice Registers','Block RAM Tile','LUT as Memory','DSPs','combinational loop'])),flush=True)
 assert p.returncode==0 and 'F01_SYN_DONE' in out and not re.search(r'\bERROR:',out)
