"""Read-only integrity check of the current standalone candidate."""
import argparse,hashlib,json
from pathlib import Path
def main():
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1]);a=p.parse_args()
    root=a.root.resolve();manifest=json.loads((root/'CANDIDATE_MANIFEST.json').read_text(encoding='utf8'))
    failures=[]
    for name,digest in manifest['files'].items():
        f=(root/name).resolve()
        if not f.is_relative_to(root):raise SystemExit('Unsafe manifest path')
        if not f.is_file() or hashlib.sha256(f.read_bytes()).hexdigest()!=digest:failures.append(name)
    if failures:raise SystemExit('CHECK_FAILED '+', '.join(failures))
    print('CANDIDATE_PASS files='+str(len(manifest['files'])))
    print('Board verified:',manifest['board_verified'],'Progress:',manifest['progress'])
    print('Bit SHA256:',manifest['bit_sha256'])
if __name__=='__main__':main()
