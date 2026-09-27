"""Reproduce E-01 from the preserved candidate, without modifying either source tree.

Examples (Python 3):
  python E-01_reproduce.py --mode prepare
  python E-01_reproduce.py --mode equiv
  python E-01_reproduce.py --mode synth
Candidate files are hash-checked against the sources actually validated in E-01.
Vivado-generated files go to scratch, except its transient .Xil under syn/.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import time
import zipfile

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mode', choices=['prepare','equiv','synth','all'], default='prepare')
parser.add_argument('--scratch', type=Path)
parser.add_argument('--vivado-bin',type=Path,default=Path(r'C:\Xilinx\Vivado\2020.2\bin'))
args=parser.parse_args()
docs=Path(__file__).resolve().parent
root=docs.parents[1]
work=args.scratch or Path(tempfile.mkdtemp(prefix='codex-e01-reproduce-'))
work.mkdir(parents=True,exist_ok=True)
manifest=json.loads((docs/'E-01_hash_audit.json').read_text(encoding='utf-8'))
sha=lambda data:hashlib.sha256(data).hexdigest()
names=['Buffer','Conv_MAC','requant_stage','gelu_stage','Pool','CNN_Encoder']
refdir=work/'reference';newdir=work/'work_encoder';sim=work/'sim'
for directory in [refdir,newdir,sim]:directory.mkdir(exist_ok=True)
archive=docs/'E-01_encoder_candidate.zip'
assert sha(archive.read_bytes())==manifest['candidate_archive_sha256']
with zipfile.ZipFile(archive) as z:
    assert set(z.namelist())=={n+'.v' for n in names}
    for entry in manifest['candidate']:
        filename=entry['file']
        original=(root/'cnn_rtl/others/CNN_Encoder'/filename).read_bytes()
        candidate=z.read(filename)
        assert sha(original)==entry['original_sha256'],filename+' original changed'
        assert sha(candidate)==entry['candidate_sha256'],filename+' candidate changed'
        (newdir/filename).write_bytes(candidate)
        text=original.decode('utf-8').replace('\r\n','\n')
        if '`timescale' not in text:text='`timescale 1ns / 1ps\n'+text
        text=re.sub(r'\b('+'|'.join(names)+r')\b',lambda m:m.group(0)+'_e01_ref',text)
        (refdir/filename).write_text(text,encoding='utf-8',newline='\n')
blob=root/'wifi-csi-pose-main/HLS/pl_accel_v6/pl_accel_v6_weights.bin'
assert sha(blob.read_bytes())==manifest['blob']['sha256']
print('PREPARED hash-identical validated candidate and logic-identical reference:',work,flush=True)
blocks=[]
def run(tool,arguments,cwd,simulation=False):
    command=[str(args.vivado_bin/(tool+'.bat'))]+list(map(str,arguments))
    print('COMMAND:',subprocess.list2cmdline(command),flush=True)
    start=time.perf_counter()
    result=subprocess.run(command,cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    text=result.stdout.decode('utf-8',errors='replace').replace('\r\n','\n')
    elapsed=time.perf_counter()-start
    blocks.append('CWD: '+str(cwd)+'\nCOMMAND: '+subprocess.list2cmdline(command)+'\n'+text+
                  f'\nEXIT_CODE: {result.returncode}\nWALL_CLOCK_SECONDS: {elapsed:.6f}\n')
    (work/'reproduce_run.txt').write_text('\n'.join(blocks),encoding='utf-8')
    print('\n'.join(line for line in text.splitlines() if line.startswith(('PASS:','OBS:','ERROR:','WARNING:','E01_','LATCH count'))),flush=True)
    assert result.returncode==0 and not re.search(r'\b(?:ERROR|FAIL|Fatal):',text)
    if simulation:assert not re.search(r'\bWARNING:',text)
    return text
if args.mode in ['equiv','all']:
    loaders=['blob_decoder','conv_weight_ram','param_ram','gelu_lut_ram','fcw_ram','weight_param_loader']
    run('xvlog',[refdir/(n+'.v') for n in names]+[newdir/(n+'.v') for n in names]+
        [root/f'cnn_rtl/rtl/{n}.v' for n in loaders],sim,True)
    run('xvlog',['-sv',root/'cnn_rtl/tb/tb_encoder_equiv.v'],sim,True)
    run('xelab',['work.tb_encoder_equiv','-s','e01_equiv'],sim,True)
    result=run('xsim',['e01_equiv','-runall','-onerror','quit','-testplusarg','BLOB='+blob.as_posix()],sim,True)
    assert 'PASS: E-01 ALL cases=2' in result and '$finish called' in result
if args.mode in ['synth','all']:
    tcl=work/'encoder_syn.tcl'
    tcl.write_text('source {'+(root/'cnn_rtl/syn/syn_check.tcl').as_posix()+'}\n'+
        'set mac_regs [filter [all_registers] {NAME =~ u_conv_mac/*}]\n'+
        'puts "E01_MAC_INTERNAL_TIMING"\nreport_timing -from $mac_regs -to $mac_regs -max_paths 1\n'+
        'puts "E01_MAC_LAUNCH_TIMING"\nreport_timing -from $mac_regs -max_paths 1\n'+
        'puts "E01_MAC_CAPTURE_TIMING"\nreport_timing -to $mac_regs -max_paths 1\n'+
        'foreach c [get_cells -hier -filter {REF_NAME =~ RAMB*}] { puts "E01_BRAM $c [get_property REF_NAME $c]" }\n'+
        'write_checkpoint -force {'+(work/'encoder_e01.dcp').as_posix()+'}\nputs "E01_SYN_DONE"\n',encoding='utf-8')
    # Existing workspace cwd avoids Vivado 2020.2's observed TEMP cleanup error.
    result=run('vivado',['-mode','batch','-source',tcl,'-nojournal','-nolog','-tclargs',
        'CNN_Encoder','xc7z020clg400-1']+[newdir/(n+'.v') for n in names],root/'cnn_rtl/syn')
    assert 'E01_SYN_DONE' in result
    print('Synthesis success is NOT timing closure; inspect WNS in the complete log.',flush=True)
print('RESULTS:',work,flush=True)
