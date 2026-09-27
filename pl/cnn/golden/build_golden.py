#!/usr/bin/env python3
"""G-01: reproducible, file-driven reference goldens; Python standard library only."""
from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
REFERENCE = ROOT / 'wifi-csi-pose-main'
FILES = ('full_pose.cpp', 'full_pose.h', 'test_vectors.h', 'testbench.cpp')
COUNTS = {'encoder_flat_i8.hex': 3072, 'fc1_requant_i8.hex': 128,
          'fc1_gelu_i8.hex': 128, 'fc2_requant_i8.hex': 128,
          'fc2_gelu_i8.hex': 128, 'fc3_i8.hex': 24,
          'fc1_acc_i32.hex': 128, 'fc2_acc_i32.hex': 128,
          'fc3_acc_i32.hex': 24, 'pose_f32.hex': 24}


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def emit(path: Path, text: str) -> None:
    path.write_text(text, encoding='utf-8', newline='\n')


def instrument(source: str) -> str:
    edits = [
        ('#include "full_pose.h"', '#include "golden_hooks.hpp"'),
        ('        qint32_t acc = (qint32_t)bias[o] + acc0 + acc1;',
         '        g01_capture_acc(OUT_DIM == HIDDEN_DIM ? 2 : 3, o, acc);'),
        ('        qint32_t acc = (qint32_t)g_fc1_bias_int32[o] + acc0 + acc1 + acc2 + acc3;',
         '        g01_capture_acc(1, o, acc);'),
        ('    encode_all_receivers_direct(input, flatten_banks);',
         '    g01_dump_flatten(flatten_banks);'),
        ('    fc1_requant_4way_banked(flatten_banks, weights, head_fc1);',
         '    g01_dump_i8("fc1_requant_i8.hex", head_fc1, HIDDEN_DIM);'),
        ('    apply_head_gelu1(head_fc1, head_gelu1);',
         '    g01_dump_i8("fc1_gelu_i8.hex", head_gelu1, HIDDEN_DIM);'),
        ('    fc2_requant(head_gelu1, head_fc2);',
         '    g01_dump_i8("fc2_requant_i8.hex", head_fc2, HIDDEN_DIM);'),
        ('    apply_head_gelu2(head_fc2, head_gelu2);',
         '    g01_dump_i8("fc2_gelu_i8.hex", head_gelu2, HIDDEN_DIM);'),
        ('    fc3_requant(head_gelu2, pose_q);',
         '    g01_dump_i8("fc3_i8.hex", pose_q, POSE_DIM);'),
        ('    write_final_pose(pose_q, final_pose);', '    g01_dump_accs();'),
    ]
    for anchor, addition in edits:
        if source.count(anchor) != 1:
            raise ValueError(f'reference changed; review instrumentation anchor: {anchor}')
        source = source.replace(anchor, anchor + '\n' + addition)
    return source


def c_array(text: str, name: str) -> list[str]:
    m = re.search(r'\b' + name + r'\[[^]]+\]\s*=\s*\{([^}]+)\}', text)
    if not m:
        raise ValueError(f'missing reference array {name}')
    return [s.strip() for s in m[1].split(',') if s.strip()]


def validate_blob(blob: bytes) -> dict:
    if len(blob) != 422992:
        raise ValueError(f'blob size={len(blob)}, expected 422992 (fixed architecture v2)')
    words = struct.unpack('<105748I', blob)
    if words[:3] != (0x36574c50, 2, 105748):
        raise ValueError(f'bad magic/version/count: {words[:3]}')
    scales = struct.unpack_from('<2f', blob, 12)
    if any(not math.isfinite(s) or s <= 0 for s in scales):
        raise ValueError('input/output scale must be finite and positive')
    shifts = {}
    for name, offset, count in [('pool', 6, 1), ('conv1', 220, 16),
                               ('conv2', 1452, 32), ('fc1', 100044, 128),
                               ('fc2', 104524, 128), ('fc3', 105468, 24)]:
        v = struct.unpack_from(f'<{count}i', blob, 4*offset)
        for i, s in enumerate(v):
            if not -31 <= s <= 63:
                raise ValueError(f'{name}.shift[{i}]={s} outside Loader [-31,63]')
        shifts[name] = {'min': min(v), 'max': max(v), 'count': count}
    return {'size_bytes': len(blob), 'sha256': sha(blob), 'input_scale': scales[0],
            'output_scale': scales[1], 'header_hex': [f'{w:08x}' for w in words[:8]],
            'shift_ranges': shifts}


def read_hex(path: Path, count: int, width: int) -> list[int]:
    lines = path.read_text(encoding='ascii').splitlines()
    if len(lines) != count or any(not re.fullmatch('[0-9a-f]{' + str(width) + '}', s) for s in lines):
        raise ValueError(f'wrong dump format/count: {path.name}')
    return [int(s, 16) for s in lines]


def validate_fc_dumps(output: Path, blob: bytes) -> dict:
    """Independent scalar observer checks all FC accumulators, requant and LUT outputs."""
    i8 = lambda xs: [v if v < 128 else v-256 for v in xs]
    x = i8(read_hex(output/'encoder_flat_i8.hex', 3072, 2))
    checked = {}
    for stage, dim, nout, wo, bo, mo, so, lo in [
        (1, 3072, 128, 1484, 99788, 99916, 100044, 105620),
        (2, 128, 128, 100172, 104268, 104396, 104524, 105684),
        (3, 128, 24, 104652, 105420, 105444, 105468, None)]:
        weights = struct.unpack_from(f'<{dim*nout}b', blob, wo*4)
        bias = struct.unpack_from(f'<{nout}i', blob, bo*4)
        mult = struct.unpack_from(f'<{nout}i', blob, mo*4)
        shift = struct.unpack_from(f'<{nout}i', blob, so*4)
        acc, req = [], []
        for o in range(nout):
            a = (bias[o] + sum(v*w for v, w in zip(x, weights[o*dim:(o+1)*dim]))) & 0xffffffff
            acc.append(a)
            signed = a if a < 0x80000000 else a-0x100000000
            p = signed * mult[o]; s = shift[o]
            if s <= 0:
                shifted = p << -s
                if not -(1 << 63) <= shifted < (1 << 63):
                    raise ValueError(f'FC{stage} index {o}: C++ signed shift overflow; reference review required')
            else:
                adjusted = p + ((1 << (s-1)) if p >= 0 else -(1 << (s-1)))
                if not -(1 << 63) <= adjusted < (1 << 63):
                    raise ValueError('C++ rounding overflow; reference review required')
                shifted = adjusted >> s
            req.append(max(-127, min(127, shifted)))
        if acc != read_hex(output/f'fc{stage}_acc_i32.hex', nout, 8):
            raise ValueError(f'FC{stage} independent accumulator mismatch')
        req_file = f'fc{stage}_requant_i8.hex' if stage < 3 else 'fc3_i8.hex'
        if req != i8(read_hex(output/req_file, nout, 2)):
            raise ValueError(f'FC{stage} independent requant mismatch')
        if lo is not None:
            lut = struct.unpack_from('<256b', blob, lo*4)
            x = [lut[v+128] for v in req]
            if x != i8(read_hex(output/f'fc{stage}_gelu_i8.hex', nout, 2)):
                raise ValueError(f'FC{stage} independent LUT mismatch')
        checked[f'fc{stage}'] = {'acc': nout, 'requant': nout, 'gelu': nout if lo is not None else 0}
    scale = struct.unpack_from('<f', blob, 16)[0]
    expected_bits = [struct.unpack('<I', struct.pack('<f', q*scale))[0] for q in req]
    if expected_bits != read_hex(output/'pose_f32.hex', 24, 8):
        raise ValueError('FC3 int8 -> float32 scale mismatch')
    return checked


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--blob', type=Path, default=REFERENCE/'HLS/pl_accel_v6/pl_accel_v6_weights.bin')
    parser.add_argument('--input-bin', type=Path, help='11520 raw int8 bytes in [channel][h][w] order')
    parser.add_argument('--output', type=Path, default=HERE/'golden_current')
    parser.add_argument('--reference-dir', type=Path, default=REFERENCE/'HLS/pl_accel_v6')
    parser.add_argument('--cxx', type=Path, default=Path('C:/msys64/ucrt64/bin/g++.exe'))
    parser.add_argument('--hls-include', type=Path, default=Path('C:/Xilinx/Vivado/2020.2/include'))
    args = parser.parse_args()
    start = time.perf_counter()
    out = args.output.resolve(); ref = args.reference_dir.resolve()
    # No output or generated source is ever placed in the reference tree or RTL/TB.
    for protected in [REFERENCE, ROOT/'cnn_rtl/rtl', ROOT/'cnn_rtl/tb', ROOT/'cnn_rtl/others', ref, HERE/'src']:
        p = protected.resolve()
        if out == p or p in out.parents or out in p.parents:
            raise ValueError(f'output overlaps protected/source directory: {out}')
    originals = {name: (ref/name).read_bytes() for name in FILES}
    source_hashes = {name: sha(data) for name, data in originals.items()}
    vec = originals['test_vectors.h'].decode('utf-8-sig')
    ref_input = bytes(int(v) & 255 for v in c_array(vec, 'test_input'))
    ref_weights = struct.pack('<105748I', *(int(v, 0) for v in c_array(vec, 'test_weights')))
    expected = [struct.unpack('<f', struct.pack('<f', float(v.rstrip('fF'))))[0]
                for v in c_array(vec, 'test_expected_pose')]
    if len(ref_input) != 11520 or len(expected) != 24:
        raise ValueError('reference input/expected shape differs from this fixed architecture')
    blob_path = args.blob.resolve(); blob = blob_path.read_bytes()
    blob_info = validate_blob(blob)
    input_bytes = args.input_bin.resolve().read_bytes() if args.input_bin else ref_input
    if len(input_bytes) != 11520: raise ValueError('input must contain exactly 11520 int8 bytes')
    same_sample = blob == ref_weights and input_bytes == ref_input
    if args.input_bin is None and blob != ref_weights:
        print('NOTE: changed blob with original quantized input; supply --input-bin for a new scale/sample.', flush=True)
    out.mkdir(parents=True, exist_ok=True)
    # An interrupted/failed regeneration must never leave a previous success manifest.
    emit(out/'manifest.json', json.dumps({'schema':'G-01-v1', 'status':'INCOMPLETE',
         'invocation':subprocess.list2cmdline([sys.executable]+sys.argv)}, indent=2)+'\n')
    src = HERE/'src'; original_dir = src/'original'; original_dir.mkdir(parents=True, exist_ok=True)
    for name, data in originals.items(): (original_dir/name).write_bytes(data)
    source = originals['full_pose.cpp'].decode('utf-8-sig').replace('\r\n', '\n')
    observed = instrument(source)
    emit(src/'full_pose_instrumented.cpp', observed)
    emit(src/'instrumentation.diff', ''.join(difflib.unified_diff(
        source.splitlines(True), observed.splitlines(True), fromfile='original/full_pose.cpp', tofile='full_pose_instrumented.cpp')))
    compiler = args.cxx.resolve(); include = args.hls_include.resolve()
    env = os.environ.copy(); env['PATH'] = str(compiler.parent) + os.pathsep + env.get('PATH', '')
    version = subprocess.check_output([str(compiler), '--version'], env=env, text=True)
    key_data = observed.encode() + b''.join(originals.values()) + (HERE/'golden_hooks.hpp').read_bytes() + (HERE/'golden_runner.cpp').read_bytes()
    key_data += (version + str(include)).encode() + (include/'ap_int.h').read_bytes()
    work = Path(tempfile.gettempdir())/'codex-g01-build'/sha(key_data)[:16]
    work.mkdir(parents=True, exist_ok=True)
    log = []; timings = []
    def run(label: str, cmd: list[str], cwd: Path) -> str:
        before = time.perf_counter()
        print(f'RUN: {label}', flush=True)
        proc = subprocess.run(cmd, cwd=cwd, env=env, text=True, encoding='utf-8', errors='replace',
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        elapsed = time.perf_counter()-before
        block = f'[{label}] cwd={cwd}\n{subprocess.list2cmdline(cmd)}\n{proc.stdout}\nexit={proc.returncode} wall_seconds={elapsed:.3f}\n'
        log.append(block); emit(out/'run.log', '\n'.join(log))
        timings.append({'step': label, 'seconds': round(elapsed, 6), 'exit': proc.returncode})
        print(proc.stdout, end='', flush=True)
        if proc.returncode: raise RuntimeError(f'{label} failed, see {out / "run.log"}')
        return proc.stdout
    log.append('Compiler:\n' + version)
    flags = [str(compiler), '-O2', '-std=c++14', '-I'+str(include), '-I'+str(original_dir), '-I'+str(HERE)]
    targets = [('original_test', original_dir/'testbench.cpp', original_dir/'full_pose.cpp'),
               ('baseline', HERE/'golden_runner.cpp', original_dir/'full_pose.cpp'),
               ('instrumented', HERE/'golden_runner.cpp', src/'full_pose_instrumented.cpp')]
    for name, driver, model in targets:
        exe = work/(name+'.exe')
        # A content-addressed build directory prevents stale binaries across source/compiler changes.
        if not exe.exists():
            run('build '+name, flags+['-o', str(exe), str(driver), str(model)], work)
        else: log.append(f'[build {name}] cache hit {exe}; command={subprocess.list2cmdline(flags+["-o", str(exe), str(driver), str(model)])}')
    stdout = run('original sample', [str(work/'original_test.exe')], work)
    if 'max_abs_err=0.000000000 invalid=0' not in stdout:
        raise ValueError('reference sample failed exact expected-pose check')
    (out/'input_i8.bin').write_bytes(input_bytes)
    emit(out/'input_i8.hex', ''.join(f'{b:02x}\n' for b in input_bytes))
    # Per-run snapshots keep the two model executions on exactly the same bytes.
    run_work = Path(tempfile.mkdtemp(prefix='run-', dir=work))
    (run_work/'blob.bin').write_bytes(blob); (run_work/'input.bin').write_bytes(input_bytes)
    base_out = run_work/'baseline_output'; base_out.mkdir()
    run('uninstrumented file model', [str(work/'baseline.exe'), str(run_work/'blob.bin'), str(run_work/'input.bin')], base_out)
    run('instrumented file model', [str(work/'instrumented.exe'), str(run_work/'blob.bin'), str(run_work/'input.bin')], out)
    for name, count in COUNTS.items(): read_hex(out/name, count, 8 if ('i32' in name or 'f32' in name) else 2)
    if (out/'pose_f32.hex').read_bytes() != (base_out/'pose_f32.hex').read_bytes():
        raise ValueError('instrumentation changed pose bits')
    pose_bits = read_hex(out/'pose_f32.hex', 24, 8)
    poses = [struct.unpack('<f', struct.pack('<I', n))[0] for n in pose_bits]
    max_error = max(abs(a-b) for a,b in zip(poses, expected)) if same_sample else None
    if same_sample and max_error != 0: raise ValueError('instrumented current sample differs from expected')
    fc_checks = validate_fc_dumps(out, blob)
    flat = bytes(read_hex(out/'encoder_flat_i8.hex', 3072, 2))
    emit(out/'encoder_flat_u64.hex', ''.join(f'{int.from_bytes(flat[i:i+8], "little"):016x}\n' for i in range(0,3072,8)))
    # Check independent coordinate formula, not merely byte count.
    words64 = read_hex(out/'encoder_flat_u64.hex', 384, 16)
    for rx in range(3):
        for oc in range(32):
            for oh in range(8):
                for ow in range(4):
                    n = ((rx*32+oc)*8+oh)*4+ow
                    word, lane = rx*128+oc*4+oh//2, (oh%2)*4+ow
                    if (words64[word] >> (8*lane)) & 255 != flat[n]: raise ValueError('flatten packing mismatch')
    if source_hashes != {name:sha((ref/name).read_bytes()) for name in FILES}:
        raise ValueError('reference source changed during generation')
    if args.blob.resolve().read_bytes() != blob: raise ValueError('blob changed during generation')
    final = f'PASS: G-01 flatten=3072 bytes/384 words FC_acc=128+128+24 pose=24 baseline_bits_equal=24 expected_sample={same_sample} max_abs_err={max_error}\n'
    print(final, end=''); log.append(final); emit(out/'run.log', '\n'.join(log))
    manifest = {'schema': 'G-01-v1', 'status':'COMPLETE', 'blob': {**blob_info, 'path': str(blob_path)},
                'input': {'source': str(args.input_bin.resolve()) if args.input_bin else 'test_vectors.h:test_input', 'sha256':sha(input_bytes)},
                'original_source_sha256':source_hashes, 'instrumented_sha256':sha(observed.encode()),
                'compiler':version, 'invocation':subprocess.list2cmdline([sys.executable]+sys.argv),
                'expected_sample_checked':same_sample, 'max_abs_err':max_error,
                'baseline_bit_matches':24, 'independent_fc_checks':fc_checks, 'timings':timings,
                'total_seconds':round(time.perf_counter()-start,6),
                'dumps':{name:{'lines':len((out/name).read_text().splitlines()), 'text_bytes':(out/name).stat().st_size,
                               'sha256':sha((out/name).read_bytes())} for name in [*COUNTS, 'encoder_flat_u64.hex','input_i8.hex','pose_f32.txt']}}
    emit(out/'manifest.json', json.dumps(manifest, indent=2, ensure_ascii=False)+'\n')


if __name__ == '__main__':
    try: main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as exc:
        print(f'FAIL: {exc}', file=sys.stderr); sys.exit(1)
