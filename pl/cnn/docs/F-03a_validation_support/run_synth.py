from pathlib import Path
import subprocess,time,re,sys,json
r=Path(r'D:\2609_final_project');w=Path(__file__).parent
tcl=w/'check.tcl'
tcl.write_text('source {'+(r/'cnn_rtl/syn/syn_check.tcl').as_posix()+'}\n'+r'''
check_timing -verbose
puts "F03A_CRITICAL_PATH"
report_timing -delay_type max -max_paths 1
puts "F03A_FLAT_UTILIZATION"
report_utilization
set paths [get_timing_paths -delay_type max -max_paths 1]
puts "F03A_WNS [get_property SLACK $paths]"
puts "F03A_CRITICAL_START [get_property STARTPOINT_PIN $paths]"
puts "F03A_CRITICAL_END [get_property ENDPOINT_PIN $paths]"
set loop_drc [get_drc_checks -quiet LUTLP-1]
if {[llength $loop_drc] > 0} {report_drc -checks $loop_drc}
puts "F03A_SYN_DONE"
''',encoding='utf-8')
tag=sys.argv[1]
if tag.startswith('encoder_'):
 top='CNN_Encoder';base=w/'encoder_before' if tag=='encoder_before' else r/'cnn_rtl/rtl/encoder'
 src=[base/(n+'.v') for n in ['Buffer','Conv_MAC','requant_stage','gelu_stage','Pool','CNN_Encoder']]
else:
 top=tag;src=[r/'cnn_rtl/rtl/encoder/requant_stage.v',w/(tag+'.v')]
 if tag=='fc_mac_requant_ooc':src.insert(0,r/'cnn_rtl/rtl/fc/fc_mac.v')
cmd=[r'C:\Xilinx\Vivado\2020.2\bin\vivado.bat','-mode','batch','-source',str(tcl),'-nojournal','-nolog','-tclargs',top,'xc7z020clg400-1']+list(map(str,src))
t=time.perf_counter();p=subprocess.run(cmd,cwd=r/'cnn_rtl/syn',stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
out=p.stdout.decode('utf-8',errors='replace').replace('\r\n','\n');elapsed=time.perf_counter()-t
(w/('synthesis_'+tag+'.txt')).write_text('CWD: '+str(r/'cnn_rtl/syn')+'\nCOMMAND: '+subprocess.list2cmdline(cmd)+'\n'+out+'\nEXIT_CODE: '+str(p.returncode)+'\nWALL_CLOCK_SECONDS: %.6f\n'%elapsed,encoding='utf-8')
print(tag,'exit=',p.returncode,'seconds=',round(elapsed,3),flush=True)
print('\n'.join(l for l in out.splitlines() if any(k in l for k in ['ERROR:', 'WARNING:', 'F03A_', 'LATCH count', 'Slice LUTs','Slice Registers','Block RAM Tile','LUT as Memory','DSPs','combinational loop'])),flush=True)
assert p.returncode==0 and 'F03A_SYN_DONE' in out and not re.search(r'\bERROR:',out)
wns=float(re.search(r'^F03A_WNS ([0-9.-]+)',out,re.M).group(1))
if tag=='encoder_after':
 old=(w/'synthesis_encoder_before.txt').read_text(encoding='utf-8');oldwns=float(re.search(r'^F03A_WNS ([0-9.-]+)',old,re.M).group(1))
 if wns<oldwns:raise SystemExit('STOP: Encoder WNS worsened; no timing changes authorized')
elif not tag.startswith('encoder_') and wns<1.0:raise SystemExit('STOP: FC WNS below +1.0 ns; report without timing changes')
