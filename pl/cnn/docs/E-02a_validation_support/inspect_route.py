from pathlib import Path
import subprocess,time,json,sys,re
r=Path(r'D:\2609_final_project');w=Path(__file__).parent;d=r/'cnn_rtl/docs/E-02a_runs'/sys.argv[1]
if (d/'inspect.log').exists():
 assert not (d/'inspect_initial.log').exists(), 'Preserve earlier inspections'
 (d/'inspect_initial.log').write_bytes((d/'inspect.log').read_bytes())
 (d/'inspection_initial.json').write_bytes((d/'inspection.json').read_bytes())
cmd=[r'C:\Xilinx\Vivado\2020.2\bin\vivado.bat','-mode','batch','-source',(w/'inspect_route.tcl').as_posix(),'-nojournal','-nolog','-tclargs',d.as_posix()]
t=time.perf_counter();p=subprocess.run(cmd,cwd=r/'cnn_rtl/syn',stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
out=p.stdout.decode('utf-8',errors='replace').replace('\r\n','\n');elapsed=time.perf_counter()-t
(d/'inspect.log').write_text('COMMAND: '+subprocess.list2cmdline(cmd)+'\n'+out+f'\nEXIT_CODE: {p.returncode}\nWALL_CLOCK_SECONDS: {elapsed:.6f}\n',encoding='utf-8')
assert p.returncode==0 and 'E02A_CHECKPOINT_VERIFIED' in out and not re.search(r'^ERROR:',out,re.M)
(d/'inspection.json').write_text(json.dumps({'exit':p.returncode,'seconds':elapsed,'route_reopened_verified':True},indent=2))
print(d.name,'route checkpoint verified',elapsed,flush=True)
