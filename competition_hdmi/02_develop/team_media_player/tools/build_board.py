"""Build in an ASCII temporary path (TD 6.2 cannot cd to this Unicode workspace).
No installation, device programming, flash writing, or source-directory mutation.
"""
import argparse,datetime as dt,hashlib,json,shutil,subprocess,tempfile,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    p=argparse.ArgumentParser();p.add_argument('--td-bin',type=Path,required=True);a=p.parse_args()
    out=ROOT/'records'/('td_'+dt.datetime.now().strftime('%Y%m%d_%H%M%S_%f'));out.mkdir()
    temp=Path(tempfile.mkdtemp(prefix='team_td_'))
    for folder in ['rtl','extensions/fade/rtl','board']:
        target=temp/folder;target.mkdir(parents=True,exist_ok=True)
        for f in (ROOT/folder).rglob('*'):
            if f.is_file() and f.suffix in ['.v','.al','.adc','.sdc','.tcl']:
                dst=target/f.relative_to(ROOT/folder);dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(f,dst)
    sources={str(f.relative_to(temp)):hashlib.sha256(f.read_bytes()).hexdigest() for f in temp.rglob('*') if f.is_file()}
    print('BUILD',temp,'EVIDENCE',out,flush=True)
    original_project=(temp/'board/team_player.al').read_bytes()
    preflight=temp/'board/project_open_check.tcl'
    preflight.write_text('import_device eagle_s20.db -package EG4S20BG256\nopen_project team_player.al\nelaborate -top team_top\nputs TEAM_PROJECT_OPEN_PASS\nexit\n',encoding='ascii')
    with (out/'project_open.log').open('wb') as log:
        opened=subprocess.run([str(a.td_bin),'./project_open_check.tcl'],cwd=temp/'board',stdout=log,stderr=subprocess.STDOUT,timeout=120)
    check=(out/'project_open.log').read_text(encoding='utf8',errors='replace')
    if opened.returncode or 'TEAM_PROJECT_OPEN_PASS' not in check or ' ERROR:' in check:
        print(check[-5000:]);raise SystemExit('Project open/elaboration failed; no implementation started')
    (temp/'board/team_player.al').write_bytes(original_project)
    with (out/'build.log').open('wb') as log:
        r=subprocess.run([str(a.td_bin),'./board/build.tcl'],cwd=temp,stdout=log,stderr=subprocess.STDOUT,timeout=1800)
    log=(out/'build.log').read_text(encoding='utf8',errors='replace')
    for f in (temp/'board').glob('team_player*'):
        if f.suffix in ['.bit','.area','.timing','.ts']:shutil.copyfile(f,out/f.name)
    bit=out/'team_player.bit';implemented='TEAM_BUILD_COMPLETE' in log and bit.is_file() and bit.stat().st_size>0
    timing=out/'team_player_pr.timing'
    text=timing.read_text(encoding='utf8',errors='replace') if timing.exists() else ''
    setup=re.search(r'SWNS:\s*([-\d.]+)ns',text);hold=re.search(r'HWNS:\s*([-\d.]+)ns',text)
    setup_ns=float(setup[1]) if setup else None;hold_ns=float(hold[1]) if hold else None
    timing_pass=setup_ns is not None and hold_ns is not None and setup_ns>=0 and hold_ns>=0
    success=implemented and timing_pass
    summary=dict(status='PASS' if success else 'FAIL',returncode=r.returncode,build_directory=str(temp),
                 source_sha256=sources,bit_sha256=hashlib.sha256(bit.read_bytes()).hexdigest() if bit.is_file() else None,
                 implemented=implemented,timing_pass=timing_pass,setup_wns_ns=setup_ns,hold_wns_ns=hold_ns,
                 scope='TD internal timing check under supplied constraints; physical I/O and board acceptance separately required')
    (out/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf8')
    print(log[-6000:]);print(summary['status'],out,flush=True)
    if not success:raise SystemExit(1)
if __name__=='__main__':main()
