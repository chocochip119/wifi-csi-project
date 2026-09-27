from pathlib import Path
import subprocess,time,re,sys
r=Path(r'D:\2609_final_project');w=Path(r'C:\Users\kccistc\AppData\Local\Temp\codex-g02');s=w/'core_sim';s.mkdir(exist_ok=True);blocks=[]
def run(tool,args):
 cmd=[str(Path(r'C:\Xilinx\Vivado\2020.2\bin')/(tool+'.bat'))]+list(map(str,args));t=time.perf_counter();p=subprocess.run(cmd,cwd=s,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);out=p.stdout.decode('utf-8',errors='replace').replace('\r\n','\n');elapsed=time.perf_counter()-t
 blocks.append('CWD: '+str(s)+'\nCOMMAND: '+subprocess.list2cmdline(cmd)+'\n'+out+'\nEXIT_CODE: '+str(p.returncode)+'\nWALL_CLOCK_SECONDS: %.6f\n'%elapsed);(w/'core_run.txt').write_text('\n'.join(blocks),encoding='utf-8')
 print('COMMAND: '+subprocess.list2cmdline(cmd),flush=True);print('\n'.join(l for l in out.splitlines() if any(k in l for k in ['PASS:','OBS:','WARNING:','ERROR:','FAIL:','Fatal:'])),flush=True);print('WALL_CLOCK_SECONDS: %.3f'%elapsed,flush=True)
 assert p.returncode==0 and not re.search(r'\b(?:ERROR|WARNING|FAIL|Fatal):',out)
 return out
rtl=['pose_cnn_ctrl','pose_cnn_v1_0_M00_AXI','blob_decoder','conv_weight_ram','param_ram','gelu_lut_ram','fcw_ram','weight_param_loader']
enc=['Buffer','Conv_MAC','requant_stage','gelu_stage','Pool','CNN_Encoder']
run('xvlog',[r/f'cnn_rtl/rtl/{n}.v' for n in rtl]+[r/f'cnn_rtl/rtl/encoder/{n}.v' for n in enc]+[r/'cnn_rtl/rtl/pose_cnn.v'])
run('xvlog',['-sv']+[r/f'cnn_rtl/tb/{n}.v' for n in ['axi4_slave_mem_model','fc_stub','tb_pose_cnn_core']])
run('xelab',['work.tb_pose_cnn_core','-s','x02a_core'])
if '--compile-only' not in sys.argv:
 opts=[]
 if len(sys.argv)>1:
  optfile=s/'case.args';optfile.write_text('-testplusarg '+chr(34)+'CASE='+sys.argv[1]+chr(34)+'\n');opts=['-f',optfile.name]
 out=run('xsim',['x02a_core','-runall','-onerror','quit']+opts)
 assert 'PASS: X-02a ALL' in out and '$finish called' in out
 (w/'tb_pose_cnn_core_output.txt').write_text(out,encoding='utf-8')
