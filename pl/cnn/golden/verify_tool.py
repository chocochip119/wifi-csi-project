#!/usr/bin/env python3
"""G-01 host-tool checks only. Does not run/create any Verilog testbench."""
import ast
import importlib.util
import json
import math
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SCRATCH = Path(tempfile.gettempdir())/'codex-g01-validation'
SCRATCH.mkdir(exist_ok=True)
spec = importlib.util.spec_from_file_location('g01', HERE/'build_golden.py')
g01 = importlib.util.module_from_spec(spec)
sys.dont_write_bytecode = True
spec.loader.exec_module(g01)
current = HERE/'golden_current'
blob_path = ROOT/'wifi-csi-pose-main/HLS/pl_accel_v6/pl_accel_v6_weights.bin'
blob = blob_path.read_bytes()
records = []


def run_case(name, extra):
    out = SCRATCH/name
    cmd = [sys.executable, '-u', str(HERE/'build_golden.py'), '--output', str(out), *extra]
    proc = subprocess.run(cmd, text=True, encoding='utf-8', errors='replace', stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (SCRATCH/(name+'.console.log')).write_text(subprocess.list2cmdline(cmd)+'\n'+proc.stdout, encoding='utf-8')
    if proc.returncode or 'PASS: G-01 ' not in proc.stdout:
        raise RuntimeError(f'{name}: exit={proc.returncode}\n{proc.stdout}')
    manifest = json.loads((out/'manifest.json').read_text())
    assert manifest['status'] == 'COMPLETE'
    records.append({'case':name, 'command':subprocess.list2cmdline(cmd), 'seconds':manifest['total_seconds'],
                    'blob_sha256':manifest['blob']['sha256'], 'expected_sample_checked':manifest['expected_sample_checked']})
    print(f'PASS: {name} seconds={manifest["total_seconds"]:.3f}', flush=True)
    return out, manifest


repeat, m = run_case('repeat', [])
for name in json.loads((current/'manifest.json').read_text())['dumps']:
    assert (repeat/name).read_bytes() == (current/name).read_bytes(), name
assert m['max_abs_err'] == 0
print('PASS: repeated generation all 13 text dumps byte-identical', flush=True)

# An actually different compatible blob, NOT merely another path to the same bytes.
# Zero the FC3 weights and biases; all upstream feature/hidden values must stay identical.
variant = bytearray(blob)
variant[4*104652:4*105444] = bytes(4*(105444-104652))
variant_path = SCRATCH/'fc3_zero_weights_bias.bin'; variant_path.write_bytes(variant)
changed, m = run_case('changed_blob', ['--blob', str(variant_path)])
assert m['expected_sample_checked'] is False
assert m['blob']['sha256'] != g01.sha(blob)
for name in ['encoder_flat_i8.hex','fc1_gelu_i8.hex','fc2_gelu_i8.hex']:
    assert (changed/name).read_bytes() == (current/name).read_bytes(), name
assert set(g01.read_hex(changed/'fc3_acc_i32.hex',24,8)) == {0}
assert set(g01.read_hex(changed/'fc3_i8.hex',24,2)) == {0}
assert set(g01.read_hex(changed/'pose_f32.hex',24,8)) == {0}
print('PASS: different blob -> FC3 acc/int8/float all 24 zero; upstream unchanged; stale expected skipped', flush=True)

input_path = SCRATCH/'zero_input.bin'; input_path.write_bytes(bytes(11520))
changed_input, m = run_case('changed_input', ['--input-bin',str(input_path)])
assert m['expected_sample_checked'] is False
a = g01.read_hex(current/'encoder_flat_i8.hex',3072,2)
b = g01.read_hex(changed_input/'encoder_flat_i8.hex',3072,2)
changes = sum(x != y for x,y in zip(a,b)); assert changes > 0
print(f'PASS: supplied input file consumed; feature changes={changes}/3072', flush=True)

# Exercise the exact exporter routine without importing torch or executing exporter writes.
export_path = ROOT/'wifi-csi-pose-main/ML/src/int8_export.py'
tree = ast.parse(export_path.read_text())
node = next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='quantize_multiplier')
scope={'math':math}; exec(compile(ast.Module(body=[node],type_ignores=[]),str(export_path),'exec'),scope)
quantize = scope['quantize_multiplier']
lower=(1-2**-32)*2**-33; upper=(1-2**-32)*2**62
edges=[]
for name,value,want in [('lower below',math.nextafter(lower,0),64),('lower at',lower,63),
                        ('lower above',math.nextafter(lower,math.inf),63),
                        ('upper below',math.nextafter(upper,0),-31),('upper at',upper,-32),
                        ('upper above',math.nextafter(upper,math.inf),-32)]:
    mult,shift=quantize(value); assert shift == want,(name,value,mult,shift,want)
    edges.append({'name':name,'real_scale':value,'multiplier':mult,'shift':shift})
    print(f'PASS: exporter boundary {name} scale={value:.17g} multiplier={mult} shift={shift}',flush=True)

bad = bytearray(blob); struct.pack_into('<i',bad,4*220,64)
try: g01.validate_blob(bad)
except ValueError as e: assert 'conv1.shift[0]=64' in str(e)
else: raise AssertionError('shift=64 not rejected')
try: g01.instrument('changed source without required hooks')
except ValueError: pass
else: raise AssertionError('missing instrumentation anchor not rejected')
print('PASS: invalid shift and changed instrumentation anchors rejected',flush=True)
result={'cases':records,'changed_input_feature_bytes':changes,'shift_boundary_checks':edges,
        'status':'PASS','scratch':str(SCRATCH)}
(SCRATCH/'validation.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print('PASS: G-01 TOOL VALIDATION COMPLETE',flush=True)
