"""Package a new reviewable board candidate only from matching passing evidence.
Keeps originals, creates new output paths, never programs any device or card.
"""
import argparse,hashlib,json,shutil,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
VERSION='2026-10-26_candidate_01'
SUITES=[('BMP','records/bmp_20261025_064207_055210',22),
        ('FAT32','records/fat32_20261025_064207_041765',29),
        ('Frames','records/frame_20261025_064207_050759',25),
        ('Fade','extensions/fade/records/fade_20261025_064207_116977',30),
        ('Integration','records/integration_20261026_230512_357096',32)]
def digest(f):return hashlib.sha256(f.read_bytes()).hexdigest()
def check_sources(summary,base=ROOT):
    hashes=summary.get('source_sha256')
    if hashes is None and 'rtl_sha256' in summary:hashes={'rtl/image/team_bmp_parser.v':summary['rtl_sha256']}
    if not hashes:raise SystemExit('Missing source identity in evidence')
    for name,sha in hashes.items():
        f=(base/name.replace('\\','/')).resolve()
        if not f.is_relative_to(ROOT) or not f.is_file() or digest(f)!=sha:
            raise SystemExit('Evidence/source mismatch: '+name)
def copy_new(src,dst):
    dst.parent.mkdir(parents=True,exist_ok=True)
    if dst.exists():
        if digest(dst)!=digest(src):raise SystemExit('Refusing to replace '+str(dst))
    else:shutil.copyfile(src,dst)
def main():
    p=argparse.ArgumentParser();p.add_argument('--build',type=Path,required=True)
    p.add_argument('--standalone',type=Path,required=True);p.add_argument('--zip',type=Path,required=True);a=p.parse_args()
    if a.standalone.exists() or a.zip.exists():raise SystemExit('Use new output paths; no overwrites')
    build=a.build.resolve();b=json.loads((build/'summary.json').read_text())
    if not b.get('implemented') or not b.get('timing_pass') or b['setup_wns_ns']<0 or b['hold_wns_ns']<0:raise SystemExit('Build/timing gate failed')
    check_sources(b)
    bit=build/'team_player.bit'
    if digest(bit)!=b['bit_sha256']:raise SystemExit('Bit hash mismatch')
    opened=(build/'project_open.log').read_text(encoding='utf8',errors='replace')
    if 'TEAM_PROJECT_OPEN_PASS' not in opened or ' ERROR:' in opened:raise SystemExit('Project entry gate failed')
    suites=[]
    for name,folder,count in SUITES:
        s=json.loads((ROOT/folder/'summary.json').read_text(encoding='utf8'))
        if s['status']!='PASS' or s['cases']!=count:raise SystemExit('Regression gate failed '+name)
        check_sources(s,ROOT/'extensions/fade' if name=='Fade' else ROOT)
        suites.append(dict(name=name,cases=count,summary=folder+'/summary.json'))
    release=ROOT/'release'/VERSION
    copy_new(bit,release/'team_player.bit')
    for f in build.iterdir():
        if f.is_file() and f.suffix in ['.json','.timing','.area','.log']:
            copy_new(f,release/'evidence/TD'/f.name)
    result=dict(version=VERSION,progress=90,board_verified=False,implementation_verified=True,
                source_build=str(build.relative_to(ROOT)),bit_sha256=b['bit_sha256'],
                setup_wns_ns=b['setup_wns_ns'],hold_wns_ns=b['hold_wns_ns'],
                regression_cases=sum(s['cases'] for s in suites),suites=suites,
                scope='Model regressions and TD under supplied constraints; physical board and external I/O acceptance pending')
    summary=release/'BUILD_AND_TEST.json'
    if summary.exists():raise SystemExit('Candidate summary already exists')
    summary.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
    out=a.standalone.resolve();out.mkdir(parents=True)
    # Include sources, independent test entrypoints and only reviewed evidence.
    for folder in ['rtl','sim','tools','docs','extensions/fade','release/'+VERSION]:
        for f in (ROOT/folder).rglob('*'):
            if f.is_file() and '__pycache__' not in f.parts and f.suffix!='.pyc':copy_new(f,out/f.relative_to(ROOT))
    for name,folder,count in SUITES:
        for f in (ROOT/folder).rglob('*'):
            if f.is_file():copy_new(f,out/f.relative_to(ROOT))
    for f in (ROOT/'board').rglob('*'):
        if f.is_file() and f.suffix in ['.v','.al','.adc','.sdc','.tcl','.json']:copy_new(f,out/f.relative_to(ROOT))
    for f in ['README.md','HANDOFF.md','NEXT_TASKS.md','PROGRESS.md','requirements-sim.txt','.gitignore','.gitattributes']:
        copy_new(ROOT/f,out/f)
    files={str(f.relative_to(out)).replace('\\','/'):digest(f) for f in sorted(out.rglob('*')) if f.is_file()}
    manifest=dict(**result,files=files)
    (out/'CANDIDATE_MANIFEST.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
    a.zip.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(a.zip,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for f in sorted(out.rglob('*')):
            if f.is_file():z.write(f,str(f.relative_to(out)))
    with zipfile.ZipFile(a.zip) as z:
        assert z.testzip() is None
        for name,sha in files.items():assert hashlib.sha256(z.read(name)).hexdigest()==sha
    # Repository manifest covers the same current file set and can verify the clone.
    copy_new(out/'CANDIDATE_MANIFEST.json',ROOT/'CANDIDATE_MANIFEST.json')
    print('PACKAGE_PASS files='+str(len(files))+' tests='+str(result['regression_cases']))
    print('STANDALONE',out);print('ZIP',a.zip,'SHA256',digest(a.zip))
if __name__=='__main__':main()
