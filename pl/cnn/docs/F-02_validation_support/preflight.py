"""Copy read-only golden inputs into this scratch directory after SHA checks."""
from pathlib import Path
import hashlib,json,shutil
r=Path(r'D:\2609_final_project');w=Path(__file__).parent;s=w/'mac_sim';s.mkdir(exist_ok=True)
g=r/'cnn_rtl/golden/golden_current';blob=r/'wifi-csi-pose-main/HLS/pl_accel_v6/pl_accel_v6_weights.bin'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
m=json.loads((g/'manifest.json').read_text(encoding='utf-8'))
assert m['status']=='COMPLETE' and blob.stat().st_size==422992 and sha(blob)==m['blob']['sha256']
names={'fc1_acc_i32.hex':128,'fc2_acc_i32.hex':128,'fc3_acc_i32.hex':24,'encoder_flat_u64.hex':384,'fc1_gelu_i8.hex':128,'fc2_gelu_i8.hex':128}
hashes={'blob.bin':sha(blob)}
for name,count in names.items():
    assert sha(g/name)==m['dumps'][name]['sha256']
    assert len((g/name).read_text().splitlines())==count
    hashes[name]=sha(g/name)
shutil.copy2(blob,s/'blob.bin')
for name in names:shutil.copy2(g/name,s/name)
assert all(sha(s/name)==value for name,value in hashes.items())
(w/'preflight.json').write_text(json.dumps({'hashes':hashes,'status':'PASS'},indent=2),encoding='utf-8')
(s/'preflight_ok.txt').write_text('F02ACC01\n'+hashes['blob.bin']+'\n',encoding='ascii')
print('PASS: F-02 blob/golden manifest SHA-256 and staged copies verified')
