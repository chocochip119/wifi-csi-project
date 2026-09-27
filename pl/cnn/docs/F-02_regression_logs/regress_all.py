from pathlib import Path
import subprocess,sys,time,concurrent.futures,json
w=Path(__file__).parent
names=['run_existing.py','regression.py','run_new.py','run_wrapper.py','run_real.py','run_equiv.py','run_core.py','run_g02.py','run_storage.py']
def run(name):
 t=time.perf_counter();cmd=[sys.executable,'-X','utf8','-u',str(w/name)]
 p=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 out=p.stdout.decode('utf-8',errors='replace')
 (w/(name+'.console.txt')).write_text(subprocess.list2cmdline(cmd)+'\n'+out,encoding='utf-8')
 row={'runner':name,'exit':p.returncode,'seconds':round(time.perf_counter()-t,3)}
 print(row,flush=True)
 if p.returncode:print(out[-4000:],flush=True)
 return row
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
 rows=list(pool.map(run,names))
(w/'regression_runs.json').write_text(json.dumps(rows,indent=2))
assert all(row['exit']==0 for row in rows)
print('PASS: F-02 existing 23 TB regression groups completed',flush=True)
