from pathlib import Path
import subprocess,time,re
r=Path(r'D:\2609_final_project');w=Path(__file__).parent;s=w/'storage_sim';s.mkdir(exist_ok=True)
blocks=[]
def run(tool,args):
 cmd=[str(Path(r'C:\Xilinx\Vivado\2020.2\bin')/(tool+'.bat'))]+list(map(str,args));t=time.perf_counter()
 p=subprocess.run(cmd,cwd=s,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 out=p.stdout.decode('utf-8',errors='replace').replace('\r\n','\n');elapsed=time.perf_counter()-t
 blocks.append('CWD: '+str(s)+'\nCOMMAND: '+subprocess.list2cmdline(cmd)+'\n'+out+'\nEXIT_CODE: '+str(p.returncode)+'\nWALL_CLOCK_SECONDS: %.6f\n'%elapsed)
 (w/'storage_run.txt').write_text('\n'.join(blocks),encoding='utf-8')
 print(out,flush=True);print('WALL_CLOCK_SECONDS:',elapsed,flush=True)
 assert p.returncode==0 and not re.search(r'\b(?:ERROR|WARNING|FAIL|Fatal):',out)
 return out
run('xvlog',[r/f'cnn_rtl/rtl/fc/{n}.v' for n in ['fc1_weight_fifo','hidden_buffer','pose_buffer']])
run('xvlog',['-sv',r/'cnn_rtl/tb/tb_fc_storage.v'])
run('xelab',['work.tb_fc_storage','-s','f01_storage'])
out=run('xsim',['f01_storage','-runall','-onerror','quit'])
assert 'PASS: tb_fc_storage ALL Y1-Y5 cases complete' in out and '$finish called' in out
(w/'tb_fc_storage_output.txt').write_text(out,encoding='utf-8')
