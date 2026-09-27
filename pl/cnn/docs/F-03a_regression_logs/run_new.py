from pathlib import Path
import subprocess,time,re
r=Path(r'D:\2609_final_project');w=Path(r'C:\Users\kccistc\AppData\Local\Temp\codex-f03a');s=w/'sim';s.mkdir(exist_ok=True);blocks=[]
def run(tool,args):
 cmd=[str(Path(r'C:\Xilinx\Vivado\2020.2\bin')/(tool+'.bat'))]+list(map(str,args));t=time.perf_counter();p=subprocess.run(cmd,cwd=s,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);out=p.stdout.decode('utf-8',errors='replace').replace('\r\n','\n')
 blocks.append('CWD: '+str(s)+'\nCOMMAND: '+subprocess.list2cmdline(cmd)+'\n'+out+'\nEXIT_CODE: '+str(p.returncode)+'\nWALL_CLOCK_SECONDS: %.6f\n'%(time.perf_counter()-t));(w/'loader_regression_run.txt').write_text('\n'.join(blocks),encoding='utf-8')
 print('COMMAND: '+subprocess.list2cmdline(cmd),flush=True);print('\n'.join(l for l in out.splitlines() if any(k in l for k in ['CASE id=','L-03','RESET','IDLE offered','WARNING:','ERROR:','FAIL:','Fatal:'])),flush=True)
 assert p.returncode==0 and not re.search(r'\b(?:ERROR|WARNING|FAIL|Fatal):',out)
 return out
run('xvlog',[r/f'cnn_rtl/rtl/{n}.v' for n in ['blob_decoder','conv_weight_ram','param_ram','gelu_lut_ram','fcw_ram']])
run('xvlog',['-sv',r/'cnn_rtl/tb/tb_blob_decoder.v',r/'cnn_rtl/tb/tb_loader_rams.v'])
for top in ['tb_loader_rams','tb_blob_decoder']:
 run('xelab',['work.'+top,'-s','l02_'+top]);out=run('xsim',['l02_'+top,'-runall','-onerror','quit'])
 assert '$finish called' in out and ('RAM M1-M6 ALL' if top=='tb_loader_rams' else 'L-03 ALL C1-C7 D1-D7 N1-N7') in out
 (w/(top+'_output.txt')).write_text(out,encoding='utf-8')
