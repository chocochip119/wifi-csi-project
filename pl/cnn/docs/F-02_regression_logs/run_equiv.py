from pathlib import Path
import subprocess,time,re
r=Path(r'D:\2609_final_project');w=Path(r'C:\Users\kccistc\AppData\Local\Temp\codex-f02');s=w/'equiv_sim';s.mkdir(exist_ok=True);blocks=[]
def run(tool,args):
 cmd=[str(Path(r'C:\Xilinx\Vivado\2020.2\bin')/(tool+'.bat'))]+list(map(str,args));t=time.perf_counter();p=subprocess.run(cmd,cwd=s,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);out=p.stdout.decode('utf-8',errors='replace').replace('\r\n','\n');elapsed=time.perf_counter()-t
 blocks.append('CWD: '+str(s)+'\nCOMMAND: '+subprocess.list2cmdline(cmd)+'\n'+out+'\nEXIT_CODE: '+str(p.returncode)+'\nWALL_CLOCK_SECONDS: %.6f\n'%elapsed);(w/'equiv_run.txt').write_text('\n'.join(blocks),encoding='utf-8')
 print('COMMAND: '+subprocess.list2cmdline(cmd),flush=True);print('\n'.join(l for l in out.splitlines() if any(k in l for k in ['PASS:','OBS:','WARNING:','ERROR:','FAIL:','Fatal:','MISMATCH'])),flush=True);print('WALL_CLOCK_SECONDS: %.3f'%elapsed,flush=True)
 assert p.returncode==0 and not re.search(r'\b(?:ERROR|WARNING|FAIL|Fatal):',out)
 return out
names=['Buffer','Conv_MAC','requant_stage','gelu_stage','Pool','CNN_Encoder']
run('xvlog',[w/f'reference/{n}.v' for n in names]+[r/f'cnn_rtl/rtl/encoder/{n}.v' for n in names]+[r/f'cnn_rtl/rtl/{n}.v' for n in ['blob_decoder','conv_weight_ram','param_ram','gelu_lut_ram','fcw_ram','weight_param_loader']])
run('xvlog',['-sv',r/'cnn_rtl/tb/tb_encoder_equiv.v'])
run('xelab',['work.tb_encoder_equiv','-s','e01_equiv'])
out=run('xsim',['e01_equiv','-runall','-onerror','quit'])
assert 'PASS: E-01 ALL cases=2' in out and '$finish called' in out
(w/'tb_encoder_equiv_output.txt').write_text(out,encoding='utf-8')
