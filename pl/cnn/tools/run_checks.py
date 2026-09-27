"""Portable handover regression; source files are never edited."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
TB = ROOT / 'testbench'
MARKERS = {
    'tb_s00_axi_write': 'PASS: S00-02 ALL CHECKS PASSED',
    'tb_s00_axi_regs': 'PASS: S00-03 ALL REGISTER CHECKS PASSED',
    'tb_s00_axi_read': 'PASS: S00-04 ALL READ CHECKS PASSED',
    'tb_s00_axi_ctrl': 'PASS: S00-05 ALL CONTROL CHECKS PASSED',
    'tb_ctrl_status': 'PASS: T-06 ALL CTRL STATUS CHECKS PASSED',
    'tb_csr_ctrl_link': 'PASS: T-06 ALL REACHABLE CSR/CTRL LINK CHECKS PASSED',
    'tb_top_load': 'PASS: T-07 LOAD ALL SELECTED cases=10 selector=-1',
    'tb_top_infer': 'PASS: T-04 N1-N8 ALL SELECTED CHECKS',
    'tb_top_fc1': 'PASS: T-05 ALL SELECTED',
    'tb_top_full': 'PASS: T-06 Q1-Q6 ALL SELECTED',
    'tb_m00_read': 'PASS: T-02b FUNCTIONAL 12/12 CASES',
    'tb_m00_read_perf': 'PASS: T-02b PERFORMANCE MEASUREMENT COMPLETE',
    'tb_m00_write': 'PASS: T-02c ALL W1-W8 CHECKS',
    'tb_m00_err': 'PASS: T-02d E1-E9 ALL CHECKS',
    'tb_axi4_slave_mem_model': 'PASS: T-02a ALL A/B/C/D CHECKS PASSED',
    'tb_blob_decoder': 'PASS: L-03 ALL C1-C7 D1-D7 N1-N7',
    'tb_loader_rams': 'PASS: L-02 RAM M1-M6 ALL',
    'tb_weight_param_loader': 'PASS: L-04 K2-K6 ALL',
    'tb_loader_real_blob': 'PASS: L-05 REAL_BLOB B1-B6 ALL',
}
SMOKE = ['tb_s00_axi_ctrl', 'tb_ctrl_status', 'tb_m00_read',
         'tb_top_load', 'tb_loader_real_blob']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--vivado-bin', default=os.environ.get('VIVADO_BIN'))
    parser.add_argument('--suite', choices=['smoke', 'core'], default='smoke')
    args = parser.parse_args()
    bindir = Path(args.vivado_bin) if args.vivado_bin else None
    def tool(name):
        found = str(bindir / (name + '.bat')) if bindir else shutil.which(name)
        if not found or not Path(found).is_file():
            raise RuntimeError('Vivado tool missing: ' + name + '; use --vivado-bin')
        return found
    executables = {name: tool(name) for name in ['xvlog', 'xelab', 'xsim']}
    run = ROOT / 'runs' / datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
    run.mkdir(parents=True)
    results = {'suite': args.suite, 'cwd': str(run), 'commands': [], 'tests': {}}
    def save():
        (run / 'results.json').write_text(json.dumps(results, indent=2, ensure_ascii=False), encoding='utf-8')
    def command(label, argv, marker=None):
        started = time.perf_counter()
        proc = subprocess.run(argv, cwd=run, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        output = proc.stdout.decode('utf-8', errors='replace')
        elapsed = time.perf_counter() - started
        bad = re.findall(r'(?im)^.*(?:ERROR:|WARNING:|FAIL:|Fatal:|MISMATCH:).*$', output)
        passed = proc.returncode == 0 and not bad
        if marker is not None:
            passed = passed and marker in output and '$finish called' in output
        entry = {'label': label, 'argv': argv, 'exit_code': proc.returncode,
                 'wall_seconds': round(elapsed, 3), 'passed': passed,
                 'diagnostics': bad, 'required_marker': marker}
        results['commands'].append(entry)
        (run / (label + '.log')).write_text(
            json.dumps(entry, ensure_ascii=False, indent=2) + '\n\n' + output, encoding='utf-8')
        save()
        print(('PASS' if passed else 'FAIL') + f': {label} ({elapsed:.2f} s)', flush=True)
        if not passed:
            raise RuntimeError('Check full log: ' + str(run / (label + '.log')))
    try:
        rtl = [(ROOT / line.strip()).as_posix() for line in
               (ROOT / 'tools/core_rtl.f').read_text(encoding='utf-8').splitlines() if line.strip()]
        command('compile_rtl', [executables['xvlog']] + rtl)
        modules = ['axi4_slave_mem_model', 'loader_stub', 'in_ram_stub', 'enc_stub', 'fc_stub']
        command('compile_tb', [executables['xvlog'], '-sv'] +
                [(TB / (name + '.v')).as_posix() for name in modules + list(MARKERS)])
        blob = ROOT / 'reference/pl_accel_v6/pl_accel_v6_weights.bin'
        staged_blob = run / 'blob.bin'
        shutil.copy2(blob, staged_blob)
        blob_sha = hashlib.sha256(blob.read_bytes()).hexdigest()
        if hashlib.sha256(staged_blob.read_bytes()).hexdigest() != blob_sha:
            raise RuntimeError('Staged blob SHA-256 mismatch')
        results['blob_sha256'] = blob_sha
        # XSIM 2020.2 misdecodes non-ASCII filenames in plusargs.
        # Keep the TB untouched and use a verified, relative ASCII filename.
        (run / 'blob.args').write_text('-testplusarg "BLOB=blob.bin"\n', encoding='ascii')
        for name in SMOKE if args.suite == 'smoke' else MARKERS:
            snapshot = 'handover_' + name
            command(name + '_elab', [executables['xelab'], 'work.' + name, '-s', snapshot])
            argv = [executables['xsim'], snapshot, '-runall', '-onerror', 'quit']
            if name == 'tb_loader_real_blob':
                argv += ['-f', 'blob.args']
            command(name + '_run', argv, MARKERS[name])
            results['tests'][name] = 'PASS'
            save()
        results['passed'] = True
    except Exception as error:
        results['passed'] = False
        results['error'] = str(error)
        print(str(error), file=sys.stderr)
    save()
    print('RESULTS: ' + str(run / 'results.json'))
    return 0 if results['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())
