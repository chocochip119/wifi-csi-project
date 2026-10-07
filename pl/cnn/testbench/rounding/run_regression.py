"""Run rounding and RX5 Encoder tests in a temporary directory (NumPy + Icarus)."""
import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
parser = argparse.ArgumentParser()
parser.add_argument("--iverilog", default="iverilog")
parser.add_argument("--vvp", default="vvp")
parser.add_argument("--ivl-base", help="optional Icarus -B installation directory")
args = parser.parse_args()


def run(command, cwd):
    subprocess.run([str(part) for part in command], cwd=cwd, check=True)


with tempfile.TemporaryDirectory(prefix="wise-rounding-") as directory:
    work = Path(directory)
    compiler = [args.iverilog] + (["-B", args.ivl_base] if args.ivl_base else []) + ["-g2012"]
    run([sys.executable, ROOT / "pl/cnn/testbench/rounding/gen_vectors.py"], work)
    cases = [
        ("rounding", ["CNN_Encoder/requant_stage.v", "FC/Common/requant_core.v"]),
        ("pool_rounding", ["CNN_Encoder/Pool.v"]),
    ]
    for name, sources in cases:
        run(compiler + ["-s", "tb_" + name, "-o", work / name,
                        ROOT / f"pl/cnn/testbench/rounding/tb_{name}.v"] +
            [ROOT / "pl/cnn/rtl" / source for source in sources], work)
        run([args.vvp, work / name], work)
    run([sys.executable, ROOT / "pl/cnn/testbench/CNN_Encoder/gen_requant_stage.py"], work)
    run(compiler + ["-s", "tb_requant_stage", "-o", work / "requant",
                    ROOT / "pl/cnn/testbench/CNN_Encoder/tb_requant_stage.v",
                    ROOT / "pl/cnn/rtl/CNN_Encoder/requant_stage.v"], work)
    run([args.vvp, work / "requant"], work)
    run([sys.executable, ROOT / "pl/cnn/testbench/CNN_Encoder/gen_CNN_Encoder.py", "5"], work)
    run(compiler + ["-s", "tb_CNN_Encoder", "-Ptb_CNN_Encoder.RX=5", "-o", work / "encoder",
                    ROOT / "pl/cnn/testbench/CNN_Encoder/tb_CNN_Encoder.v"] +
        sorted((ROOT / "pl/cnn/rtl/CNN_Encoder").glob("*.v")), work)
    run([args.vvp, work / "encoder"], work)
