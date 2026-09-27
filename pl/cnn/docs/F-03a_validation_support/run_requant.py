from pathlib import Path
import subprocess,time,re,json,hashlib
r=Path(r'D:\2609_final_project');w=Path(__file__).parent;s=w/'requant_sim'
hashes=json.loads((w/'preflight.json').read_text())['hashes'];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert all(sha(s/n)==h for n,h in hashes.items())
blocks=['SHA PREFLIGHT PASS\n'+json.dumps(hashes,indent=2)]
def run(tool,args):
 cmd=[str(Path(r'C:\Xilinx\Vivado\2020.2\bin')/(tool+'.bat'))]+list(map(str,args));t=time.perf_counter()
 p=subprocess.run(cmd,cwd=s,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 out=p.stdout.decode('utf-8',errors='replace').replace('\r\n','\n');elapsed=time.perf_counter()-t
 blocks.append('CWD: '+str(s)+'\nCOMMAND: '+subprocess.list2cmdline(cmd)+'\n'+out+'\nEXIT_CODE: '+str(p.returncode)+'\nWALL_CLOCK_SECONDS: %.6f\n'%elapsed)
 (w/'requant_run.txt').write_text('\n'.join(blocks),encoding='utf-8')
 print(out,flush=True);print('WALL_CLOCK_SECONDS:',elapsed,flush=True)
 assert p.returncode==0 and not re.search(r'\b(?:ERROR|WARNING|FAIL|Fatal):',out)
 return out
run('xvlog',[r/f'cnn_rtl/rtl/fc/{n}.v' for n in ['fc_mac','fc1_weight_fifo','hidden_buffer']]+[r/f'cnn_rtl/rtl/{n}.v' for n in ['fcw_ram','param_ram']]+[r/'cnn_rtl/rtl/encoder/requant_stage.v'])
run('xvlog',['-sv',r/'cnn_rtl/tb/tb_fc_requant.v'])
run('xelab',['work.tb_fc_requant','-s','f03a_requant'])
out=run('xsim',['f03a_requant','-runall','-onerror','quit'])
assert 'PASS: F-03a ALL cases=27' in out and '$finish called' in out and 'MISMATCH:' not in out
assert all(sha(s/n)==h for n,h in hashes.items())
(w/'tb_fc_requant_output.txt').write_text(out,encoding='utf-8')
