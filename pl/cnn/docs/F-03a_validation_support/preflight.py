from pathlib import Path
import hashlib,json,struct,shutil
r=Path(r'D:\2609_final_project');w=Path(__file__).parent;s=w/'requant_sim';s.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
g=r/'cnn_rtl/golden/golden_current';blob=r/'wifi-csi-pose-main/HLS/pl_accel_v6/pl_accel_v6_weights.bin'
m=json.loads((g/'manifest.json').read_text());assert m['status']=='COMPLETE'
assert blob.stat().st_size==422992 and sha(blob)==m['blob']['sha256']
names={'fc1_acc_i32.hex':128,'fc2_acc_i32.hex':128,'fc3_acc_i32.hex':24,'encoder_flat_u64.hex':384,'fc1_gelu_i8.hex':128,'fc2_gelu_i8.hex':128,'fc1_requant_i8.hex':128,'fc2_requant_i8.hex':128,'fc3_i8.hex':24,'pose_f32.hex':24}
hashes={'blob.bin':sha(blob)};shutil.copy2(blob,s/'blob.bin')
for n,count in names.items():
 assert sha(g/n)==m['dumps'][n]['sha256'] and len((g/n).read_text().splitlines())==count
 hashes[n]=sha(g/n);shutil.copy2(g/n,s/n)
data=blob.read_bytes();layout=json.loads((blob.parent/'pl_accel_v6_weight_layout.json').read_text())['offset_words']
def si(x,b):return x-(1<<b) if x&(1<<(b-1)) else x
def values(n,b=8):return [si(int(v,16),b) for v in (g/n).read_text().splitlines()]
def arr(name,n):return struct.unpack_from(f'<{n}i',data,4*layout[name])
def roundq(a,m,s):
 p=a*m
 return (p+(1<<(s-1)) if p>=0 else p-(1<<(s-1)))//(1<<s) if s>0 else p*(1<<(-s))
def sat(q):return min(127,max(-127,q))
rows=[];mut=[];allsh=[];allmult=[]
for name,n in [('conv1',16),('conv2',32),('fc1',128),('fc2',128),('fc3',24)]:
 allsh+=list(arr(name+'.requant_shift',n));allmult+=list(arr(name+'.requant_mult',n))
for layer,n in [(1,128),(2,128),(3,24)]:
 name=f'fc{layer}';bias=arr(name+'.bias_int32',n);mult=arr(name+'.requant_mult',n);shift=arr(name+'.requant_shift',n)
 acc=values(name+'_acc_i32.hex',32);gold=values(name+('_i8.hex' if layer==3 else '_requant_i8.hex'))
 raw=[roundq(a,m,s) for a,m,s in zip(acc,mult,shift)];assert list(map(sat,raw))==gold
 rows.append({'layer':layer,'count':n,'raw_min':min(raw),'raw_max':max(raw),'saturation_count':sum(abs(v)>127 for v in raw),'max_product_abs':max(abs(a*m) for a,m in zip(acc,mult)),'signed_product_bits':max(abs(a*m) for a,m in zip(acc,mult)).bit_length()+1})
 for field in range(3):
  for o in range(n):
   b,mu,sh=bias[o],mult[o],shift[o];pure=acc[o]-b
   nb,nm,ns=(b+1048576,mu,sh) if field==0 else (b,mu//2,sh) if field==1 else (b,mu,sh+1)
   q=sat(roundq(pure+nb,nm,ns))
   if q!=gold[o]:
    mut.append({'layer':layer,'field':['bias','mult','shift'][field],'out':o,'before':[b,mu,sh],'after':[nb,nm,ns],'rq_before':gold[o],'rq_after':q});break
  else:raise AssertionError('No observable mutation')
scale=struct.unpack_from('<f',data,16)[0];pose=values('fc3_i8.hex');pose_bits=[int(v,16) for v in (g/'pose_f32.hex').read_text().splitlines()]
assert [struct.unpack('<I',struct.pack('<f',q*scale))[0] for q in pose]==pose_bits
stats={'shift_count':len(allsh),'shift_min':min(allsh),'shift_max':max(allsh),'mult_min':min(allmult),'mult_max':max(allmult),'output_scale':scale,'pose_f32_matches':24}
assert all(sha(s/n)==h for n,h in hashes.items())
(s/'preflight_ok.txt').write_text('F03A0001\n'+sha(blob)+'\n',encoding='ascii')
(w/'preflight.json').write_text(json.dumps({'hashes':hashes,'stats':stats,'layers':rows,'mutations':mut,'status':'PASS'},indent=2),encoding='utf-8')
print('PASS: F-03a manifest/SHA, independent requant, pose_f32, staged inputs verified')
