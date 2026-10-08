"""Read-only runtime checks. Never opens a COM port, Tk window, or a model."""
from __future__ import annotations

import argparse
import importlib
from importlib import metadata
import json
import platform
from pathlib import Path
import re
import struct
import sys
import sysconfig
import time
import warnings

ROOT = Path(__file__).resolve().parent
REQUIRED_PYTHON = (3, 14, 7)
PRIMARY_VERSIONS = {
    'numpy': '2.5.3', 'scipy': '1.18.1', 'scikit-learn': '1.9.1',
    'pandas': '3.0.6', 'joblib': '1.6.0', 'pyserial': '3.5',
    'ipykernel': '7.4.0', 'ipywidgets': '8.1.9', 'nbformat': '5.11.1',
    'nbclient': '0.11.0', 'Pillow': '12.3.0',
}


def _lock_versions() -> dict[str, str]:
    path = ROOT / 'requirements-lock.txt'
    if not path.is_file():
        raise FileNotFoundError('requirements-lock.txt is missing. Download/extract the complete source or portable package again.')
    pairs = {}
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        match = re.fullmatch(r'([A-Za-z0-9_.-]+)==([^\s]+)\s+--hash=sha256:[a-f0-9]{64}', line.strip())
        if not match:
            raise ValueError('Invalid pinned dependency line: ' + line)
        pairs[match.group(1)] = match.group(2)
    return pairs


def _base_report() -> dict:
    errors = []
    if tuple(sys.version_info[:3]) != REQUIRED_PYTHON:
        errors.append(f'Python 3.14.7 is required; current interpreter is {platform.python_version()}. '
                      'Run setup_windows.ps1 (or setup_windows.cmd) and select this project .venv/Scripts/python.exe in VS Code.')
    if platform.python_implementation() != 'CPython':
        errors.append('The supported interpreter is CPython 3.14.7, not ' + platform.python_implementation())
    if sys.platform != 'win32' or struct.calcsize('P') * 8 != 64 or platform.machine().lower() not in ('amd64', 'x86_64'):
        errors.append('This project supports Windows x64 (AMD64) with exact CPython 3.14.7. Other platforms are not supported by this dependency lock.')
    if sysconfig.get_config_var('Py_GIL_DISABLED'):
        errors.append('Use the standard CPython build. Free-threaded Python 3.14t is not the tested runtime.')
    tk = {}
    try:
        import tkinter
        tk = {'import_ok': True, 'tk_version': tkinter.TkVersion, 'tcl_version': tkinter.TclVersion,
              'window_created': False}
    except Exception as exc:
        errors.append('Tkinter is unavailable. Use the bundled full Python runtime or Python 3.14.7 with Tcl/Tk installed: ' + str(exc))
        tk = {'import_ok': False, 'error': str(exc), 'window_created': False}
    clock = {}
    for name in ('time', 'monotonic', 'perf_counter'):
        info = time.get_clock_info(name)
        clock[name] = {'implementation': info.implementation, 'resolution_s': info.resolution,
                       'monotonic': info.monotonic, 'adjustable': info.adjustable}
    return {
        'python': platform.python_version(), 'python_full': sys.version,
        'required_python': '3.14.7', 'executable': str(Path(sys.executable).resolve()),
        'implementation': platform.python_implementation(), 'platform': platform.platform(),
        'machine': platform.machine(), 'bits': struct.calcsize('P') * 8,
        'free_threaded': bool(sysconfig.get_config_var('Py_GIL_DISABLED')),
        'prefix': sys.prefix, 'base_prefix': sys.base_prefix,
        'tkinter': tk, 'clock': clock, 'dependencies': {}, 'errors': errors,
        'warnings': [], 'physical_serial_test': False, 'model_loaded': False,
    }


def check_environment(strict: bool = True) -> dict:
    """Check exact Python and every locked dependency without opening hardware.

    strict=True raises RuntimeError with actionable messages; strict=False returns
    the same diagnostic report with ok=False. Version metadata and core binary
    module imports are checked. No fitting, GUI window, file writes, or serial IO.
    """
    report = _base_report()
    try:
        expected = _lock_versions()
    except (OSError, ValueError) as exc:
        report['errors'].append(str(exc))
        expected = PRIMARY_VERSIONS
    for name, version in expected.items():
        try:
            actual = metadata.version(name)
        except metadata.PackageNotFoundError:
            actual = None
        report['dependencies'][name] = actual
        if actual != version:
            report['errors'].append(f'{name}: required {version}, installed {actual or "MISSING"}. '
                                    'Run setup_windows.ps1 (or setup_windows.cmd) in this project folder.')
    report['expected_dependencies'] = expected
    report['imports'] = {}
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter('always')
        for name in ('numpy', 'scipy', 'sklearn', 'pandas', 'joblib', 'serial', 'ipykernel', 'ipywidgets', 'nbformat', 'nbclient', 'PIL'):
            try:
                importlib.import_module(name)
                report['imports'][name] = True
            except Exception as exc:
                report['imports'][name] = False
                report['errors'].append(f'{name} import failed: {type(exc).__name__}: {exc}')
        report['warnings'] = [{'category': w.category.__name__, 'message': str(w.message)} for w in caught]
    report['ok'] = not report['errors']
    if strict and not report['ok']:
        raise RuntimeError('Environment check failed:\n- ' + '\n- '.join(report['errors']))
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-only', action='store_true', help='Check Python/Tk only, before dependencies are installed.')
    parser.add_argument('--json', type=Path, help='Explicitly save the check report to this file.')
    args = parser.parse_args()
    report = _base_report() if args.base_only else check_environment(strict=False)
    report['ok'] = not report['errors']
    text = json.dumps(report, ensure_ascii=False, indent=2)
    print(text)
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(text + '\n', encoding='utf-8')
    return 0 if report['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
