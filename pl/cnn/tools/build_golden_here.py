"""Run the unchanged G-01 tool using this repository's reference directory."""
from pathlib import Path
import subprocess
import sys
root = Path(__file__).resolve().parents[1]
args = [sys.executable, str(root/'golden/build_golden.py'),
        '--reference-dir', str(root/'reference/pl_accel_v6'),
        '--blob', str(root/'reference/pl_accel_v6/pl_accel_v6_weights.bin'),
        '--output', str(root/'runs/golden_generated')]
sys.exit(subprocess.call(args + sys.argv[1:], cwd=root))
