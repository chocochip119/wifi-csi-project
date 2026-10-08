<#
Windows PowerShell 5+ setup. Source download uses installed Python and PyPI;
the full portable ZIP prefers its bundled runtime and offline wheels.
No firmware access, fitting, global Python installation or policy change.
#>
[CmdletBinding()]
param(
    [string]$PythonExe = '',
    [switch]$Offline,
    [string]$WheelDirectory = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$probePath = [System.IO.Path]::Combine($projectRoot, 'environment_probe.py')
$requirementsPath = [System.IO.Path]::Combine($projectRoot, 'requirements.txt')
$lockPath = [System.IO.Path]::Combine($projectRoot, 'requirements-lock.txt')
$venvPath = [System.IO.Path]::Combine($projectRoot, '.venv')
$venvPython = [System.IO.Path]::Combine($venvPath, 'Scripts', 'python.exe')
$runtimePython = [System.IO.Path]::Combine($projectRoot, 'tools', '.runtime', 'python.exe')
$runtimeArchive = [System.IO.Path]::Combine($projectRoot, 'tools', 'python-3.14.7-amd64.zip')
$bundledWheels = [System.IO.Path]::Combine($projectRoot, 'wheels')
$originalLocation = [System.Environment]::CurrentDirectory
$savedEnvironment = @{}
$environmentSettings = @{
    PYTHONUTF8 = '1'
    PYTHONDONTWRITEBYTECODE = '1'
    PYTHONNOUSERSITE = '1'
    PIP_DISABLE_PIP_VERSION_CHECK = '1'
    PIP_REQUIRE_VIRTUALENV = 'true'
    PIP_CACHE_DIR = [System.IO.Path]::Combine($venvPath, 'pip_cache')
    IPYTHONDIR = [System.IO.Path]::Combine($venvPath, 'ipython')
    JUPYTER_CONFIG_DIR = [System.IO.Path]::Combine($venvPath, 'jupyter_config')
    JUPYTER_DATA_DIR = [System.IO.Path]::Combine($venvPath, 'share', 'jupyter')
    JUPYTER_RUNTIME_DIR = [System.IO.Path]::Combine($venvPath, 'jupyter_runtime')
}

function Invoke-Checked {
    param([string]$Executable, [string[]]$Arguments, [string]$FailureMessage)
    $previousPreference = $ErrorActionPreference
    try {
        # Native stderr can contain harmless pip warnings in PowerShell 5.
        # The native process exit code, rather than that stream, decides success.
        $ErrorActionPreference = 'Continue'
        & $Executable @Arguments
        $nativeExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($nativeExit -ne 0) { throw ($FailureMessage + ' (exit ' + $nativeExit + ')') }
}

function Test-BasePython {
    param([string]$Executable, [string[]]$PrefixArguments = @())
    Write-Host ('Checking interpreter: ' + $Executable + ' ' + ($PrefixArguments -join ' '))
    if ($null -eq (Get-Command -Name $Executable -CommandType Application -ErrorAction SilentlyContinue)) {
        Write-Host 'Interpreter executable was not found.'
        return $false
    }
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $nativeOutput = @(& $Executable @PrefixArguments -B $probePath --base-only 2>&1)
        $nativeExit = $LASTEXITCODE
        foreach ($line in $nativeOutput) { Write-Host $line }
    } catch {
        Write-Host ('Interpreter check could not run: ' + $_.Exception.Message)
        return $false
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    return ($nativeExit -eq 0)
}

# Reject incompatible/relocated environments before pip can write to them.
$checkVenvCode = @'
import json, os, sys
from pathlib import Path
expected = Path(sys.argv[1]).resolve()
norm = lambda value: os.path.normcase(os.path.abspath(str(value)))
if norm(sys.prefix) != norm(expected) or norm(sys.executable) != norm(expected / 'Scripts' / 'python.exe'):
    raise SystemExit('Existing .venv points outside this project. Preserve/rename .venv and run setup again.')
if norm(sys.prefix) == norm(sys.base_prefix):
    raise SystemExit('The existing interpreter is not an isolated virtual environment.')
config = {}
for line in (expected / 'pyvenv.cfg').read_text(encoding='utf-8').splitlines():
    if '=' in line:
        key, value = line.split('=', 1)
        config[key.strip()] = value.strip()
if config.get('include-system-site-packages', '').lower() != 'false':
    raise SystemExit('Existing .venv must disable system site packages. Preserve/rename it and retry.')
command = config.get('command', '')
if ' -m venv ' in command:
    target = command.split(' -m venv ', 1)[1].strip().strip(chr(34)).strip(chr(39))
    if os.path.isabs(target) and norm(target) != norm(expected):
        raise SystemExit('Existing .venv was created at another location. Preserve/rename it and retry.')
stamp = expected / 'csi_studio_location.json'
if stamp.exists():
    recorded = json.loads(stamp.read_text(encoding='utf-8'))
    if norm(recorded['venv_path']) != norm(expected):
        raise SystemExit('Existing .venv was moved. Preserve/rename it and retry.')
print('Project virtual environment location verified:', expected)
'@

$writeLocationCode = @'
import json, sys
from pathlib import Path
target = Path(sys.argv[1]).resolve()
stamp = target / 'csi_studio_location.json'
if not stamp.exists():
    stamp.write_text(json.dumps({'venv_path': str(target), 'python': sys.version.split()[0]}, indent=2) + '\n', encoding='utf-8')
'@

try {
    foreach ($name in $environmentSettings.Keys) {
        $savedEnvironment[$name] = [System.Environment]::GetEnvironmentVariable($name, 'Process')
        [System.Environment]::SetEnvironmentVariable($name, $environmentSettings[$name], 'Process')
    }
    [System.Environment]::CurrentDirectory = $projectRoot
    Write-Host 'CSI Studio - exact CPython 3.14.7 Windows x64 with Tcl/Tk'
    Write-Host 'Only the project .venv/runtime is installed. No COM port is opened.'
    foreach ($required in @($probePath, $requirementsPath, $lockPath)) {
        if (-not [System.IO.File]::Exists($required)) {
            throw ('Missing project file: ' + $required + '. Download/extract the complete source or portable package.')
        }
    }

    $customWheels = -not [string]::IsNullOrWhiteSpace($WheelDirectory)
    if ($customWheels) { $resolvedWheels = [System.IO.Path]::GetFullPath($WheelDirectory) }
    else { $resolvedWheels = $bundledWheels }
    $hasWheels = [System.IO.Directory]::Exists($resolvedWheels)
    if ($hasWheels) { $hasWheels = [System.IO.Directory]::GetFiles($resolvedWheels, '*.whl').Length -gt 0 }
    $autoOffline = [System.IO.File]::Exists($runtimeArchive) -and $hasWheels
    $useOffline = $Offline.IsPresent -or $customWheels -or $autoOffline
    if ($useOffline -and -not $hasWheels) {
        throw ('Offline installation requires wheels. Supply -WheelDirectory with the matching wheel folder: ' + $resolvedWheels)
    }

    # Explicit interpreter selection is authoritative, including failure.
    if ([string]::IsNullOrWhiteSpace($PythonExe)) { $PythonExe = $env:PYTHON_EXE }
    $baseExecutable = ''
    $baseArguments = @()
    if (-not [string]::IsNullOrWhiteSpace($PythonExe)) {
        if (-not (Test-BasePython -Executable $PythonExe)) {
            throw 'The selected Python is incompatible. Use exact CPython 3.14.7 x64 with Tcl/Tk; no fallback or version substitution was made.'
        }
        $baseExecutable = $PythonExe
    }

    $venvExists = [System.IO.Directory]::Exists($venvPath) -or [System.IO.File]::Exists($venvPath)
    if ($venvExists) {
        if (-not [System.IO.File]::Exists($venvPython)) {
            throw 'Existing .venv is incomplete. Preserve or rename that folder and run setup again; it was not deleted.'
        }
        if (-not (Test-BasePython -Executable $venvPython)) {
            throw 'Existing .venv uses an incompatible Python. Preserve or rename it and retry; it was not modified.'
        }
        Invoke-Checked -Executable $venvPython -Arguments @('-B', '-c', $checkVenvCode, $venvPath) -FailureMessage 'Existing .venv location/isolation check failed; preserve or rename it and retry'
        if ([string]::IsNullOrWhiteSpace($baseExecutable)) { $baseExecutable = $venvPython }
    }

    if ([string]::IsNullOrWhiteSpace($baseExecutable)) {
        if ([System.IO.File]::Exists($runtimePython) -or [System.IO.File]::Exists($runtimeArchive)) {
            if (-not [System.IO.File]::Exists($runtimePython)) {
                Write-Host 'Verifying and extracting bundled official Python runtime...'
                $bootstrap = [System.IO.Path]::Combine($projectRoot, 'tools', 'bootstrap_runtime.ps1')
                if (-not [System.IO.File]::Exists($bootstrap)) { throw 'Bundled runtime bootstrap script is missing.' }
                & $bootstrap
            }
            if (-not (Test-BasePython -Executable $runtimePython)) {
                throw 'Bundled runtime is incomplete or incompatible. Preserve it and re-extract the full portable package.'
            }
            $baseExecutable = $runtimePython
        } else {
            $launcher = Get-Command py -ErrorAction SilentlyContinue
            if ($null -ne $launcher) {
                if (Test-BasePython -Executable $launcher.Source -PrefixArguments @('-3.14')) {
                    $baseExecutable = $launcher.Source
                    $baseArguments = @('-3.14')
                }
            }
            if ([string]::IsNullOrWhiteSpace($baseExecutable)) {
                $pathPython = Get-Command python -ErrorAction SilentlyContinue
                if ($null -ne $pathPython) {
                    if (Test-BasePython -Executable $pathPython.Source) { $baseExecutable = $pathPython.Source }
                }
            }
            if ([string]::IsNullOrWhiteSpace($baseExecutable)) {
                throw 'Exact CPython 3.14.7 Windows x64 with Tcl/Tk was not found. Install that version, or pass -PythonExe with its python.exe. No other Python version is accepted.'
            }
        }
    }

    if (-not $venvExists) {
        Write-Host ('Creating project environment: ' + $venvPath)
        Invoke-Checked -Executable $baseExecutable -Arguments ($baseArguments + @('-B', '-m', 'venv', $venvPath)) -FailureMessage 'Virtual environment creation failed'
        if (-not (Test-BasePython -Executable $venvPython)) { throw 'New virtual environment failed Python/Tk validation.' }
        Invoke-Checked -Executable $venvPython -Arguments @('-B', '-c', $checkVenvCode, $venvPath) -FailureMessage 'New virtual environment location/isolation check failed'
    }
    Invoke-Checked -Executable $venvPython -Arguments @('-B', '-c', $writeLocationCode, $venvPath) -FailureMessage 'Could not record virtual environment location'

    $installArguments = @('-B', '-m', 'pip', 'install')
    if ($useOffline) {
        Write-Host ('Installing hash-locked dependencies offline from: ' + $resolvedWheels)
        $installArguments += @('--no-index', '--find-links', $resolvedWheels)
    } else {
        Write-Host 'Installing hash-locked dependencies from the configured Python package index (internet required)...'
    }
    $installArguments += @('-r', $requirementsPath)
    Invoke-Checked -Executable $venvPython -Arguments $installArguments -FailureMessage 'Pinned dependency installation failed'
    Invoke-Checked -Executable $venvPython -Arguments @('-B', '-m', 'pip', 'check') -FailureMessage 'Dependency consistency check failed'
    Invoke-Checked -Executable $venvPython -Arguments @('-B', $probePath, '--json', [System.IO.Path]::Combine($projectRoot, 'environment_check.json')) -FailureMessage 'Final runtime validation failed'
    Invoke-Checked -Executable $venvPython -Arguments @('-B', '-m', 'ipykernel', 'install', '--prefix', $venvPath, '--name', 'csi-studio-py314', '--display-name', 'CSI Studio - Python 3.14.7') -FailureMessage 'Local notebook kernel registration failed'
    Write-Host ''
    Write-Host 'Setup completed. In VS Code, select this exact notebook interpreter:'
    Write-Host $venvPython
    Write-Host 'Keep the project in its final folder after setup. Recreate .venv when moving to another PC.'
    exit 0
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message)
    Write-Host 'Setup failed. Existing files were preserved; no firmware or model was changed.'
    exit 1
} finally {
    [System.Environment]::CurrentDirectory = $originalLocation
    foreach ($name in $savedEnvironment.Keys) {
        [System.Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
}
