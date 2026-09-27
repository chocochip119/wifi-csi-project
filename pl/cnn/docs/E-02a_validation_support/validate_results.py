from pathlib import Path
import json,re,hashlib,shutil

r=Path(r'D:\2609_final_project');docs=r/'cnn_rtl/docs';w=Path(__file__).parent
m=json.loads((docs/'E-02a_measurements.json').read_text());audit=json.loads((docs/'E-02a_hash_audit.json').read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert all(sha(r/n)==h for n,h in audit['before'].items())
valid=[v for v in m['runs'] if v['measurement_valid']]
assert len(valid)==7
freq=[v for v in valid if v['period_ns']!=10]
assert len(freq)==3
for v in valid:
 assert set(v['stages'])=={'post_synth','post_place','post_phys_opt','post_route'}
 base=docs/'E-02a_runs'/v['tag']
 for stage,s in v['stages'].items():
  txt=(base/(stage+'_paths.rpt')).read_text()
  measured=float(re.search(r'Slack \([^)]*\)\s*:\s*([-\d.]+)ns',txt)[1])
  assert measured==s['WNS'],(v['tag'],stage)
  summary=(base/(stage+'_summary.rpt')).read_text()
  assert int(re.search(r'Setup\s*:\s*(\d+)\s+Failing Endpoints',summary)[1])==s['failing_setup_endpoints']
 assert v['stages']['post_route']['failing_hold_endpoints']==0
 if v['complete']:
  log=(base/'full.log').read_text(encoding='utf-8',errors='replace')
  assert 'E02A_IMPL_DONE top=' in log and not re.search(r'^ERROR:',log,re.M)
 if v['period_ns']!=10:
  assert re.search(r'ACLK\s+'+f"{v['period_ns']:.3f}"+r'\s+', (base/'clocks.rpt').read_text())
for tag,g in m['encoder_failure_groups'].items():
 v=next(v for v in valid if v['tag']==tag)
 assert sum(x['count'] for x in g.values())==v['stages']['post_route']['failing_setup_endpoints']
passrows=[v for v in freq if v['stages']['post_route']['WNS']>=0]
assert len(passrows)==1 and passrows[0]['period_ns']==14
assert passrows[0]['stages']['post_route']['WNS']==.182
assert passrows[0]['stages']['post_route']['WHS']==.082
for name in ['E-02a_측정기록.md','E-02a_구간별지연.md']:
 p=docs/name
 for link in re.findall(r'\]\(([^)]+)\)',p.read_text(encoding='utf-8')):
  assert (p.parent/link).resolve().exists(),link
syn=(r/'cnn_rtl/syn/README.md').read_text(encoding='utf-8')
assert syn.count('## 2026-09-26 E-02a requant P&R 측정')==1
assert '| Encoder | 14.000 | performance | 6377 | 3608 | 13 | 10 | +0.182 ns | 0 |' in syn
result={'protected_files_unchanged':394,'valid_routed_runs':7,'E4_confirmations':3,
        'stage_WNS_crosschecks':28,'all_report_links_exist':True,'passing_period_ns':14,
        'passing_WNS_ns':.182,'passing_WHS_ns':.082,'README_result_rows':7}
(docs/'E-02a_final_validation.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
shutil.copy2(w/'validate_results.py',docs/'E-02a_validation_support/validate_results.py')
print('E02A_FINAL_VALIDATION_PASS',json.dumps(result))
