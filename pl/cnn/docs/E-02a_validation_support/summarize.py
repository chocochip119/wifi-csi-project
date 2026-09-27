from pathlib import Path
import json,re
r=Path(r'D:\2609_final_project');w=Path(__file__).parent;root=r/'cnn_rtl/docs/E-02a_runs'
rows=[]
for d in sorted(root.iterdir()):
 if not d.is_dir():continue
 row=json.loads((d/'run.json').read_text()) if (d/'run.json').exists() else {'tag':d.name,'running':True}
 row['recorded_tag']=row['tag'];row['tag']=d.name
 row['stages']={}
 if (d/'stages.tsv').exists():
  for line in (d/'stages.tsv').read_text().splitlines():
   stage,wns,whs,start,end=line.split('\t');row['stages'][stage]={'WNS':float(wns),'WHS':float(whs),'start':start,'end':end}
 for stage,v in row['stages'].items():
  p=d/(stage+'_paths.rpt');txt=p.read_text(encoding='utf-8',errors='replace')
  q=re.search(r'Data Path Delay:\s*([\d.]+)ns\s*\(logic\s*([\d.]+)ns.*?route\s*([\d.]+)ns',txt)
  if q:v.update(zip(['data_ns','logic_ns','route_ns'],map(float,q.groups())))
  q=re.search(r'Logic Levels:\s*(\d+)\s*\(([^\n]+)\)',txt)
  if q:v.update({'levels':int(q[1]),'primitives':q[2]})
  summary=(d/(stage+'_summary.rpt')).read_text(encoding='utf-8',errors='replace')
  q=re.search(r'Setup\s*:\s*(\d+)\s+Failing Endpoints',summary)
  if q:v['failing_setup_endpoints']=int(q[1])
  q=re.search(r'Hold\s*:\s*(\d+)\s+Failing Endpoints',summary)
  if q:v['failing_hold_endpoints']=int(q[1])
 if 'post_route' in row['stages'] and 'period_ns' in row:
  row['period_estimate_ns']=round(row['period_ns']-row['stages']['post_route']['WNS'],6)
  row['fmax_estimate_mhz']=1000/row['period_estimate_ns']
 if (d/'inspection.json').exists():row['inspection']=json.loads((d/'inspection.json').read_text())
 row['measurement_valid']='post_route' in row['stages'] and (row.get('complete',False) or row.get('inspection',{}).get('route_reopened_verified',False))
 rows.append(row)
(w/'summary.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
for row in rows:
 print(row['tag'],'complete=',row.get('complete'),[(k,v['WNS'],v.get('failing_setup_endpoints')) for k,v in row['stages'].items()])
