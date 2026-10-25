"""Verify the frozen handoff snapshot. No tools, network or board are needed."""
from pathlib import Path
import hashlib
import json

root=Path(__file__).resolve().parents[1]
manifest=json.loads((root/'HANDOFF_MANIFEST.json').read_text(encoding='utf-8'))
failures=[]
for entry in manifest['files']:
    path=root/entry['path']
    if not path.is_file():
        failures.append('MISSING '+entry['path'])
    elif hashlib.sha256(path.read_bytes()).hexdigest()!=entry['sha256']:
        failures.append('CHANGED '+entry['path'])
if failures:
    print('\n'.join(failures))
    raise SystemExit('HANDOFF_VERIFY_FAIL: intentional later edits also change baseline hashes')
print('HANDOFF_VERIFY_PASS files='+str(len(manifest['files'])))
