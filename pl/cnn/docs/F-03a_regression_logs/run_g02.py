from pathlib import Path
import hashlib,json,re,shutil,subprocess,time
r=Path(r'D:\2609_final_project');w=Path(r'C:\Users\kccistc\AppData\Local\Temp\codex-f03a');s=w/'golden_sim';s.mkdir(exist_ok=True)
g=r/'cnn_rtl/golden/golden_current';z=w/'golden_zero';blob=r/'wifi-csi-pose-main/HLS/pl_accel_v6/pl_accel_v6_weights.bin'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
rows={};blocks=[]
for path in [g,z]:
 m=json.loads((path/'manifest.json').read_text());assert m['status']=='COMPLETE'
 assert m['blob']['sha256']==sha(blob)
 assert m['input']['sha256']==sha(path/'input_i8.bin')
 assert m['dumps']['encoder_flat_u64.hex']['sha256']==sha(path/'encoder_flat_u64.hex')
 assert len((path/'input_i8.bin').read_bytes())==11520
 assert len((path/'encoder_flat_u64.hex').read_text().splitlines())==384
 rows[str(path)]=m
for src,dest in [(blob,'blob.bin'),(g/'input_i8.bin','sample_input.bin'),(z/'input_i8.bin','zero_input.bin'),
                 (g/'encoder_flat_u64.hex','encoder_sample_u64.hex'),(z/'encoder_flat_u64.hex','encoder_zero_u64.hex')]:
 shutil.copy2(src,s/dest);assert sha(src)==sha(s/dest)
staged={p.name:sha(p) for p in s.iterdir() if p.suffix in ['.bin','.hex']}
(s/'h1_verified.txt').write_text(sha(blob)+'\n'+sha(g/'input_i8.bin')+'\n'+sha(z/'input_i8.bin')+'\n',encoding='ascii')
(w/'h1_complete.json').write_text(json.dumps({'status':'PASS','manifests':rows,'staged_sha256':staged},indent=2),encoding='utf-8')
blocks.append('PASS H1: both manifest blob/input/golden hashes match; staged read-only source snapshots\n'+json.dumps(staged,indent=2))
def run(tool,args):
 cmd=[str(Path(r'C:\Xilinx\Vivado\2020.2\bin')/(tool+'.bat'))]+list(map(str,args));t=time.perf_counter()
 p=subprocess.run(cmd,cwd=s,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);out=p.stdout.decode('utf-8',errors='replace').replace('\r\n','\n');elapsed=time.perf_counter()-t
 blocks.append('CWD: '+str(s)+'\nCOMMAND: '+subprocess.list2cmdline(cmd)+'\n'+out+'\nEXIT_CODE: '+str(p.returncode)+'\nWALL_CLOCK_SECONDS: %.6f\n'%elapsed)
 (w/'g02_run.txt').write_text('\n'.join(blocks),encoding='utf-8')
 print(tool,'seconds=%.3f'%elapsed,flush=True)
 print('\n'.join(l for l in out.splitlines() if any(k in l for k in ['PASS:','RESULT:','MISMATCH:','OBS: G-02','WARNING:','ERROR:','FAIL:','Fatal:'])),flush=True)
 assert p.returncode==0 and not re.search(r'\b(?:ERROR|WARNING|FAIL|Fatal):',out)
 return out
rtl=['pose_cnn_ctrl','pose_cnn_v1_0_M00_AXI','blob_decoder','conv_weight_ram','param_ram','gelu_lut_ram','fcw_ram','weight_param_loader']
enc=['Buffer','Conv_MAC','requant_stage','gelu_stage','Pool','CNN_Encoder']
run('xvlog',[r/f'cnn_rtl/rtl/{n}.v' for n in rtl]+[r/f'cnn_rtl/rtl/encoder/{n}.v' for n in enc]+[r/'cnn_rtl/rtl/pose_cnn.v'])
run('xvlog',['-sv']+[r/f'cnn_rtl/tb/{n}.v' for n in ['axi4_slave_mem_model','fc_stub','tb_golden_encoder']])
run('xelab',['work.tb_golden_encoder','-s','g02_encoder'])
out=run('xsim',['g02_encoder','-runall','-onerror','quit'])
assert 'RESULT: G-02 COMPLETE cases=3' in out and '$finish called' in out
assert staged=={name:sha(s/name) for name in staged}
(w/'tb_golden_encoder_output.txt').write_text(out,encoding='utf-8')
print('EXECUTION COMPLETE: inspect H4_pass separately; a mismatch is not hidden or repaired.',flush=True)
