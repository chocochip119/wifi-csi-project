from pathlib import Path
import subprocess,time,re,sys
r=Path(r'D:\2609_final_project');w=Path(r'C:\Users\kccistc\AppData\Local\Temp\codex-f01-fifo');b=Path(r'C:\Xilinx\Vivado\2020.2\bin')
baseline='--baseline' in sys.argv; args=[a for a in sys.argv[1:] if a!='--baseline'];tops=args or ['tb_top_load','tb_top_infer','tb_top_fc1','tb_top_full','tb_ctrl_status','tb_csr_ctrl_link']
s=w/('baseline' if baseline else 'existing');s.mkdir(exist_ok=True);blocks=[];tag=('baseline_' if baseline else 'final_')+'_'.join(tops)
def run(tool,args):
 cmd=[str(b/(tool+'.bat'))]+list(map(str,args));t=time.perf_counter();p=subprocess.run(cmd,cwd=s,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);out=p.stdout.decode('utf-8',errors='replace').replace('\r\n','\n');elapsed=time.perf_counter()-t
 blocks.append('CWD: '+str(s)+'\nCOMMAND: '+subprocess.list2cmdline(cmd)+'\n'+out+'\nEXIT_CODE: '+str(p.returncode)+'\nWALL_CLOCK_SECONDS: %.6f\n'%elapsed);(w/(tag+'_run.txt')).write_text('\n'.join(blocks),encoding='utf-8')
 print('COMMAND: '+subprocess.list2cmdline(cmd),flush=True);print('\n'.join(l for l in out.splitlines() if any(k in l for k in ['PASS:','OBS:','ERROR:','WARNING:','FAIL:','Fatal:'])),flush=True);print('WALL_CLOCK_SECONDS: %.3f'%elapsed,flush=True)
 assert p.returncode==0 and not re.search(r'\b(?:ERROR|WARNING|FAIL|Fatal):',out)
 return out
rtl=[(w/'original/pose_cnn_ctrl.v' if baseline else r/'cnn_rtl/rtl/pose_cnn_ctrl.v')]+[r/f'cnn_rtl/rtl/{n}.v' for n in ['pose_cnn_v1_0_M00_AXI','pose_cnn_v1_0_S00_AXI','blob_decoder','conv_weight_ram','param_ram','gelu_lut_ram','fcw_ram','weight_param_loader']]
# Saved originals are flat .v files.
if baseline and not rtl[0].exists():rtl[0]=w/'original/rtl/pose_cnn_ctrl.v'
run('xvlog',rtl)
run('xvlog',['-sv']+[r/f'cnn_rtl/tb/{n}.v' for n in ['axi4_slave_mem_model','loader_stub','in_ram_stub','enc_stub','fc_stub']+tops])
for top in tops:
 run('xelab',['work.'+top,'-s','t07_'+top]);opt=[]
 if baseline:
  p=s/'baseline.args';p.write_text('-testplusarg "BASELINE_T06"\n',encoding='ascii');blocks.append('OPTION_FILE: '+p.read_text());opt=['-f',p.name]
 out=run('xsim',['t07_'+top,'-runall','-onerror','quit']+opt)
 assert 'PASS:' in out and '$finish called' in out
 (w/(('baseline_' if baseline else '')+top+'_output.txt')).write_text(out,encoding='utf-8')
