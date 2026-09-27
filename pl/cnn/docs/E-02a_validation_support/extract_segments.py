from pathlib import Path
import json,re

root=Path(r'D:\2609_final_project\cnn_rtl\docs\E-02a_runs')
configs={
 'encoder_default_10.000':{
  'prefix':'u_enc_rq/',
  'pins':['param3_reg[68]/C','param3_reg[68]/Q','rq_reg[3]_i_12/S[1]',
          'rq_reg[7]_i_115/O[3]','rq[7]_i_721/O','rq_reg[2]/R'],
  'evidence':['rq[7]_i_696','rq[3]_i_19','rq_reg[3]_i_12','rq_reg[7]_i_115',
              'rq[7]_i_166','rq[7]_i_953','rq[7]_i_843','rq[7]_i_721',
              'rq[7]_i_578','rq_reg[7]_i_369','rq_reg[7]_i_3','rq[7]_i_1']},
 'fc_default_10.000':{
  'prefix':'u_rq/',
  'pins':['param3_reg[69]/C','param3_reg[69]/Q','rq_reg[7]_i_361/S[0]',
          'rq_reg[7]_i_133/O[3]','rq_reg[7]_i_828/O','rq_reg[1]/R'],
  'evidence':['rq[7]_i_692','rq[7]_i_532','rq_reg[7]_i_361','rq_reg[7]_i_133',
              'rq[7]_i_967','rq[7]_i_977','rq[7]_i_927','rq_reg[7]_i_828',
              'rq[7]_i_705','rq_reg[7]_i_594','rq_reg[7]_i_3','rq[7]_i_1']}}
names=['clock-to-Q','half/decode + carry-propagate preparation','rounding carry chain',
       'variable shift + sign mux','saturation compare + output/reset select']
out={}
for tag,c in configs.items():
 d=root/tag
 text=(d/'post_route_paths.rpt').read_text()
 first='Slack '+text.split('Slack ',2)[1]
 lines=first.splitlines()
 times=[]
 for pin in c['pins']:
  exact=c['prefix']+pin
  idx=next(i for i,l in enumerate(lines) if l.rstrip().endswith(exact) and not l.strip().startswith(('Source:','Destination:')))
  nums=re.findall(r'(?<![\w.])-?\d+\.\d+',lines[idx])
  if not nums:nums=re.findall(r'(?<![\w.])-?\d+\.\d+',lines[idx-1])
  assert nums,exact
  times.append(float(nums[-1]))
 segments=[{'name':name,'from':c['prefix']+c['pins'][i], 'to':c['prefix']+c['pins'][i+1],
            'ns':round(times[i+1]-times[i],3),'cumulative_from_C_ns':round(times[i+1]-times[0],3)}
           for i,name in enumerate(names)]
 total=float(re.search(r'Data Path Delay:\s*([\d.]+)',first)[1])
 assert abs(sum(s['ns'] for s in segments)-total)<.002
 v={'path_ns_absolute':dict(zip(c['pins'],times)),'segments':segments,'total_data_ns':total,
    'Q_to_barrel_shift_boundary_ns':round(times[3]-times[1],3),
    'hypothetical_cuts_data_only':[]}
 for i in (3,4):
  a=round(times[i]-times[0],3);b=round(times[-1]-times[i],3)
  v['hypothetical_cuts_data_only'].append({'at':c['prefix']+c['pins'][i],'prefix_ns':a,'suffix_ns':b,'max_ns':max(a,b)})
 out[tag]=v
 net=(d/'routed_netlist.v').read_text().splitlines()
 evidence=[]
 for cell in c['evidence']:
  matches=[i for i,l in enumerate(net) if l.strip()==('\\'+cell) or
           re.match(r'(?:CARRY4|MUXF7|FDRE|FDSE)\s+\\'+re.escape(cell)+r'\s*$',l.strip())]
  assert len(matches)==1,(cell,matches)
  n=matches[0];end=n
  while '));' not in net[end] and ');' not in net[end]:end+=1
  evidence.append('\n'.join(f'{i+1}: {net[i]}' for i in range(max(0,n-3),end+1)))
 (d/'semantic_evidence.txt').write_text('\n\n'.join(evidence),encoding='utf-8')
 (d/'first_critical_path.txt').write_text(first,encoding='utf-8')
root.parent.joinpath('E-02a_segments.json').write_text(json.dumps(out,indent=2),encoding='utf-8')
print(json.dumps(out,indent=2))
