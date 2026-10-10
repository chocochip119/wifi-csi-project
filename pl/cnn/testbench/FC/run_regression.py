"""Run FC unit and three-layer integration tests without writing generated files to git."""
import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--iverilog", default="iverilog")
    parser.add_argument("--vvp", default="vvp")
    parser.add_argument("--ivl-base", help="Icarus -B installation directory")
    parser.add_argument("--rtl-dir", type=Path, default=ROOT / "pl/cnn/rtl/FC",
                        help="also accepts an integration IP src directory")
    parser.add_argument("--waves", type=Path, help="copy per-test VCD files here")
    args = parser.parse_args()
    for name in ("iverilog", "vvp"):
        value = getattr(args, name)
        if "/" in value or "\\" in value:
            setattr(args, name, str(Path(value).resolve()))
    compiler = [args.iverilog]
    if args.ivl_base:
        compiler += ["-B", str(Path(args.ivl_base).resolve())]
    compiler += ["-g2012", "-Wall"]
    rtl = args.rtl_dir.resolve()
    if args.waves:
        args.waves = args.waves.resolve()
        args.waves.mkdir(parents=True, exist_ok=True)
    sources = {
        "fifo": ["fc_fifo.v"], "mac": ["fc_mac.v"],
        "requant": ["requant_core.v"], "gelu": ["gelu_core.v"],
        "memories": ["Hidden_Ram.v", "pose_buffer.v", "flatten.v"],
        "controller": ["fc_controller.v"],
        "top": ["fc_fifo.v", "fc_mac.v", "requant_core.v", "gelu_core.v",
                "Hidden_Ram.v", "pose_buffer.v", "flatten.v", "fc_controller.v", "fc_top.v"],
    }
    def run(command, work):
        subprocess.run([str(x) for x in command], cwd=work, check=True, timeout=180)
    with tempfile.TemporaryDirectory(prefix="wise-fc-") as directory:
        work = Path(directory)
        run([sys.executable, HERE / "gen_vectors.py", "--rx", 5], work)
        for name, files in sources.items():
            configurations = ([(3, None), (5, None)] if name == "top" else
                              [(5, depth) for depth in (3, 8, 512)] if name == "fifo" else [(5, None)])
            for rx, depth in configurations:
                label = f"{name}_depth{depth}" if depth else f"{name}_rx{rx}"
                if name == "top":
                    run([sys.executable, HERE / "gen_vectors.py", "--rx", rx], work)
                run(compiler + ["-s", f"tb_fc_{name}", "-o", work / label,
                                *([f"-Ptb_fc_top.RX={rx}"] if name == "top" else []),
                                *([f"-Ptb_fc_fifo.DEPTH={depth}"] if depth else []),
                                HERE / f"tb_fc_{name}.v"] + [rtl / f for f in files], work)
                run([args.vvp, work / label] + (["+waves"] if args.waves else []), work)
                if args.waves:
                    shutil.copy2(work / f"tb_fc_{name}.vcd", args.waves / f"{label}.vcd")
    print("PASS FC regression: 8 unit runs (6 benches) + RX3/RX5 integration", flush=True)


if __name__ == "__main__":
    main()
