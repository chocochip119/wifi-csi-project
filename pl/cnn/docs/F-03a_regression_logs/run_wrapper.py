from pathlib import Path
import subprocess,time,re
r=Path(r'D:\2609_final_project');w=Path(r'C:\Users\kccistc\AppData\Local\Temp\codex-f03a');s=w/'wrapper_sim';s.mkdir(exist_ok=True);blocks=[]
def run(tool,args):
 cmd=[str(Path(r'C:\Xilinx\Vivado\2020.2\bin')/(tool+'.bat'))]+list(map(str,args));t=time.perf_counter();p=subprocess.run(cmd,cwd=s,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);out=p.stdout.decode('utf-8',errors='replace').replace('\r\n','\n')
 blocks.append('CWD: '+str(s)+'\nCOMMAND: '+subprocess.list2cmdline(cmd)+'\n'+out+'\nEXIT_CODE: '+str(p.returncode)+'\nWALL_CLOCK_SECONDS: %.6f\n'%(time.perf_counter()-t));(w/'wrapper_run.txt').write_text('\n'.join(blocks),encoding='utf-8')
 print('COMMAND: '+subprocess.list2cmdline(cmd),flush=True);print('\n'.join(l for l in out.splitlines() if any(k in l for k in ['CASE id=','L-04','RESET','IDLE offered','WARNING:','ERROR:','FAIL:','Fatal:'])),flush=True)
 assert p.returncode==0 and not re.search(r'\b(?:ERROR|WARNING|FAIL|Fatal):',out)
 return out
run('xvlog',[r/f'cnn_rtl/rtl/{n}.v' for n in ['blob_decoder','conv_weight_ram','param_ram','gelu_lut_ram','fcw_ram','weight_param_loader']])
run('xvlog',['-sv',r/'cnn_rtl/tb/tb_weight_param_loader.v'])
run('xelab',['work.tb_weight_param_loader','-s','l04_loader'])
out=run('xsim',['l04_loader','-runall','-onerror','quit'])
assert '$finish called' in out and 'PASS: L-04 K2-K6 ALL completed_LOADs=6 aborted_LOADs=1 full_port_sweeps=6' in out
(w/'tb_weight_param_loader_output.txt').write_text(out,encoding='utf-8')
