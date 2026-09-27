from pathlib import Path
import subprocess,time,sys,json,hashlib,re
r=Path(r'D:\2609_final_project');w=Path(__file__).parent
block=sys.argv[1];mode=sys.argv[2];period=sys.argv[3] if len(sys.argv)>3 else '10.000'
tag=sys.argv[4] if len(sys.argv)>4 else f'{block}_{mode}_{period}'
outdir=r/'cnn_rtl/docs/E-02a_runs'/tag;assert not outdir.exists(),'Use a fresh run tag; do not overwrite results'
outdir.mkdir(parents=True)
(outdir/'impl_check_used.tcl').write_bytes((r/'cnn_rtl/syn/impl_check.tcl').read_bytes())
before=json.loads((w/'before.json').read_text());sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert all(sha(r/n)==h for n,h in before.items()),'Protected source changed before run'
enc=[r/f'cnn_rtl/rtl/encoder/{n}.v' for n in ['Buffer','Conv_MAC','requant_stage','gelu_stage','Pool','CNN_Encoder']]
if block=='encoder':top='CNN_Encoder';src=enc
elif block=='fc':top='fc_mac_requant_ooc';src=[r/'cnn_rtl/rtl/fc/fc_mac.v',r/'cnn_rtl/rtl/encoder/requant_stage.v',w/'fc_mac_requant_ooc.v']
elif block=='core':
 top='pose_cnn';src=[r/f'cnn_rtl/rtl/{n}.v' for n in ['pose_cnn_ctrl','blob_decoder','conv_weight_ram','param_ram','gelu_lut_ram','fcw_ram','weight_param_loader']]+enc+[r/'cnn_rtl/tb/fc_stub.v',r/'cnn_rtl/rtl/pose_cnn.v']
else:raise ValueError(block)
cmd=[r'C:\Xilinx\Vivado\2020.2\bin\vivado.bat','-mode','batch','-source',(r/'cnn_rtl/syn/impl_check.tcl').as_posix(),'-nojournal','-nolog','-tclargs',top,'xc7z020clg400-1',period,mode,outdir.as_posix()]+[p.as_posix() for p in src]
header='CWD: '+str(r/'cnn_rtl/syn')+'\nCOMMAND: '+subprocess.list2cmdline(cmd)+'\n'
t=time.perf_counter();print('START',tag,flush=True)
with (outdir/'full.log').open('wb') as f:
 f.write(header.encode('utf-8'));f.flush()
 p=subprocess.Popen(cmd,cwd=r/'cnn_rtl/syn',stdout=f,stderr=subprocess.STDOUT)
 (outdir/'process.json').write_text(json.dumps({'pid':p.pid,'tag':tag,'command':cmd},indent=2))
 try:code=p.wait(timeout=900 if block=='core' else 1800)
 except subprocess.TimeoutExpired:
  # Terminate only the process tree started by this measurement runner.
  subprocess.run(['taskkill','/PID',str(p.pid),'/T','/F'],stdout=f,stderr=subprocess.STDOUT)
  code=124
 elapsed=time.perf_counter()-t
 f.write(f'\nEXIT_CODE: {code}\nWALL_CLOCK_SECONDS: {elapsed:.6f}\n'.encode('utf-8'))
out=(outdir/'full.log').read_text(encoding='utf-8',errors='replace')
complete=code==0 and 'E02A_IMPL_DONE top=' in out and not re.search(r'^ERROR:',out,re.M)
row={'tag':tag,'block':block,'top':top,'mode':mode,'period_ns':float(period),'exit':code,'seconds':round(elapsed,6),'complete':complete}
(outdir/'run.json').write_text(json.dumps(row,indent=2))
print(json.dumps(row),flush=True)
for line in out.splitlines():
 if line.startswith(('E02A_STAGE','E02A_IMPL_DONE','E02A_IMPL_FAILED','ERROR:')):print(line,flush=True)
assert all(sha(r/n)==h for n,h in before.items()),'Protected source changed during run'
if not complete:sys.exit(1)
