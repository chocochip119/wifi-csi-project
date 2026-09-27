from pathlib import Path
import subprocess,time,re
r=Path(r'D:\2609_final_project');w=Path(r'C:\Users\kccistc\AppData\Local\Temp\codex-g02');s=w/'regression';s.mkdir(exist_ok=True);b=Path(r'C:\Xilinx\Vivado\2020.2\bin');blocks=[]
def run(tool,args):
 cmd=[str(b/(tool+'.bat'))]+list(map(str,args));t=time.perf_counter();p=subprocess.run(cmd,cwd=s,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);out=p.stdout.decode('utf-8',errors='replace').replace('\r\n','\n')
 blocks.append('CWD: '+str(s)+'\nCOMMAND: '+subprocess.list2cmdline(cmd)+'\n'+out+'\nEXIT_CODE: '+str(p.returncode)+'\nWALL_CLOCK_SECONDS: %.6f\n'%(time.perf_counter()-t));(w/'regression_run.txt').write_text('\n'.join(blocks),encoding='utf-8',newline='\n')
 print('COMMAND: '+subprocess.list2cmdline(cmd),flush=True)
 print('\n'.join(l for l in out.splitlines() if any(x in l for x in ['ALL ','totals ','ERROR:','WARNING:','FAIL:','Fatal:'])),flush=True)
 assert p.returncode==0 and not re.search(r'\b(?:ERROR|WARNING|FAIL|Fatal):',out)
 return out
run('xvlog',[r/f'cnn_rtl/rtl/{t}.v' for t in ['pose_cnn_ctrl','pose_cnn_v1_0_M00_AXI','pose_cnn_v1_0_S00_AXI']])
tops=['tb_s00_axi_write','tb_s00_axi_regs','tb_s00_axi_read','tb_s00_axi_ctrl','tb_m00_read','tb_m00_read_perf','tb_m00_write','tb_m00_err','tb_axi4_slave_mem_model']
run('xvlog',['-sv',r/'cnn_rtl/tb/axi4_slave_mem_model.v']+[r/f'cnn_rtl/tb/{t}.v' for t in tops])
for top in tops:
 run('xelab',['work.'+top,'-s','t07_'+top]);out=run('xsim',['t07_'+top,'-runall','-onerror','quit'])
 assert 'PASS:' in out and '$finish called' in out
 (w/(top+'_output.txt')).write_text(out,encoding='utf-8',newline='\n')
print('PASS: L-02 protected regression S00=4 M00=4 model=1',flush=True)
