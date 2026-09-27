from pathlib import Path
import shutil,subprocess,sys,time
w=Path(__file__).parent;old=w.parent/'codex-x02a'
names=['run_existing.py','regression.py','run_new.py','run_wrapper.py','run_real.py','run_equiv.py','run_core.py']
for name in names:
 (w/name).write_text((old/name).read_text(encoding='utf-8').replace('codex-x02a','codex-g02'),encoding='utf-8')
(w/'reference').mkdir(exist_ok=True)
for p in (old/'reference').glob('*.v'):shutil.copy2(p,w/'reference'/p.name)
for name in names:
 t=time.perf_counter();print('START regression group',name,flush=True)
 cmd=[sys.executable,'-u',str(w/name)]
 proc=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace')
 (w/(name+'.console.txt')).write_text(subprocess.list2cmdline(cmd)+'\n'+proc.stdout,encoding='utf-8')
 if proc.returncode:print(proc.stdout,flush=True);raise SystemExit(proc.returncode)
 print('PASS regression group',name,'seconds=%.3f'%(time.perf_counter()-t),flush=True)
print('PASS: G-02 existing 21 TB groups completed',flush=True)
