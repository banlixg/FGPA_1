"""Check the immutable fade delivery snapshot; subsequent edits will differ."""
from pathlib import Path
import hashlib
import json

root=Path(__file__).resolve().parents[1]
manifest=json.loads((root/'MANIFEST.json').read_text(encoding='utf-8'))
bad=[]
for item in manifest['files']:
    p=root/item['path']
    if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=item['sha256']:
        bad.append(item['path'])
if bad:
    print('\n'.join(bad));raise SystemExit('FADE_VERIFY_FAIL')
print('FADE_VERIFY_PASS files='+str(len(manifest['files'])))
