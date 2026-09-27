from pathlib import Path
import hashlib,json,shutil
r=Path(r'D:\2609_final_project');w=Path(__file__).parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
groups=['cnn_rtl/rtl','cnn_rtl/tb','cnn_rtl/golden','cnn_rtl/others','wifi-csi-pose-main']
files=[p for g in groups for p in (r/g).rglob('*') if p.is_file()]
files += [r/'cnn_rtl/syn/syn_check.tcl',r/'cnn_rtl/syn/timing_100mhz.xdc']
before={str(p.relative_to(r)):sha(p) for p in files}
assert not (w/'before.json').exists(),'Starting hashes already exist'
(w/'before.json').write_text(json.dumps(before,indent=2),encoding='utf-8')
fixture=r/'cnn_rtl/docs/F-03a_validation_support/fc_mac_requant_ooc.v.txt'
shutil.copy2(fixture,w/'fc_mac_requant_ooc.v')
assert sha(fixture)==sha(w/'fc_mac_requant_ooc.v')
print(json.dumps({'protected':len(before),'fixture_sha256':sha(fixture),'counts':{g:len([p for p in files if p.is_relative_to(r/g)]) for g in groups}},indent=2))
