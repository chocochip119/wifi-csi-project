"""Verify the uploaded CNN snapshot without depending on the original PC."""
from pathlib import Path
import hashlib
import json
import sys
root = Path(__file__).resolve().parents[1]
repository = root.parents[1]
manifest = json.loads((root / 'UPLOAD_MANIFEST_SHA256.json').read_text(encoding='utf-8'))
bad = []
for entry in manifest['files']:
    path = repository / entry['path']
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != entry['sha256']:
        bad.append(entry['path'])
for name in bad: print('FAIL: ' + name)
print(f'{"FAIL" if bad else "PASS"}: upload SHA-256 files={len(manifest["files"])}, mismatches={len(bad)}')
sys.exit(bool(bad))
