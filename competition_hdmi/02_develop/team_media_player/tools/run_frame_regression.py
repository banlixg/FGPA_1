"""Exercise production frame writer and CDC mailbox. No board/drive access."""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from PIL import Image
from run_fat32_regression import bmp,make_case,create_fixture
from sim_support import prepare_icarus

ROOT=Path(__file__).resolve().parents[1]

def run(args,cwd,log):
    p=subprocess.run([str(a) for a in args],cwd=cwd,stdout=subprocess.PIPE,
                     stderr=subprocess.STDOUT,timeout=360)
    text=p.stdout.decode('utf-8',errors='replace');log.write_text(text,encoding='utf-8')
    if p.returncode or 'FATAL:' in text:raise RuntimeError(str(log)+'\n'+text[-3000:])
    return text

def fixture(folder,width,height,real):
    folder.mkdir()
    data=[];images=[]
    for n in range(4):
        if n==0 and real:
            raw=(ROOT/'sim/bmp/fixtures/team_03.bmp').read_bytes()
            image=Image.open(io.BytesIO(raw)).convert('RGB')
            assert image.size==(width,height)
        else:raw,image=bmp(width,height,n)
        data.append(raw);images.append(image)
    (folder/'sizes.hex').write_text(''.join(f'{len(b):08x}\n' for b in data),encoding='ascii')
    with (folder/'bytes.hex').open('w',encoding='ascii') as f:
        for raw in data:f.writelines(f'{b:02x}\n' for b in raw)
    # Load order is slot 2,0,3,1. Expected addresses are independent top-down RGB.
    with (folder/'expected.hex').open('w',encoding='ascii') as f:
        for n in (1,3,0,2):
            f.writelines(f'{r:02x}{g:02x}{b:02x}\n' for r,g,b in images[n].getdata())
    return sum(map(len,data))

def main():
    p=argparse.ArgumentParser();p.add_argument('--case',action='append')
    p.add_argument('--iverilog-bin',type=Path,help='Existing Icarus bin directory; otherwise private runtime, IVERILOG_BIN or PATH')
    a=p.parse_args()
    evidence=ROOT/'records'/('frame_'+dt.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    evidence.mkdir(parents=True,exist_ok=False)
    build=Path(tempfile.mkdtemp(prefix='team_frame_'))
    iv,vvp=prepare_icarus(build,a.iverilog_bin)
    sources=sorted((ROOT/'rtl/storage').glob('*.v'))+[
             ROOT/'rtl/video/team_frame_commit_bridge.v',ROOT/'rtl/image/team_bmp_parser.v',
             ROOT/'sim/frame/tb_team_frame_store.sv',ROOT/'sim/frame/tb_team_frame_commit.sv',
             ROOT/'sim/frame/tb_team_image_loader.sv']
    for s in sources:shutil.copyfile(s,build/s.name)
    modes=['four_images','late_write_ack','late_file_done','zero_latency',
           'bad_first_coordinate','duplicate_coordinate','out_of_range','early_image_done',
           'abort_held_request','abort_outstanding_response','write_error','unsolicited_response',
           'late_write_error','late_file_error','retry_failed_slot','reset_pending','full_resolution']
    loader_cases=['loader_fragmented','loader_drain_error_retry','loader_bad_bmp_retry',
                  'loader_memory_error_retry','loader_full_resolution']
    cases=modes+['bridge_src_fast','bridge_video_fast','bridge_equal_clocks']+loader_cases
    if a.case:
        if set(a.case)-set(cases):raise SystemExit('Unknown case')
        cases=[c for c in cases if c in a.case]
    print('BUILD',build,flush=True);print('EVIDENCE',evidence,flush=True)
    result=[];compiled=set();made={}
    for name in cases:
        if name in modes:
            full=name=='full_resolution';w,h=(640,480) if full else (31,17)
            if full not in made:made[full]=fixture(build/('full' if full else 'small'),w,h,full)
            key='full' if full else 'small'
            if key not in compiled:
                run([iv,'-g2012','-s','tb_team_frame_store',f'-Ptb_team_frame_store.WIDTH={w}',
                     f'-Ptb_team_frame_store.HEIGHT={h}',f'-Ptb_team_frame_store.BYTE_COUNT={made[full]}',
                     '-o',key+'.vvp','team_frame_store_writer.v','team_bmp_parser.v','tb_team_frame_store.sv'],
                    build,evidence/(key+'_compile.log'));compiled.add(key)
            text=run([vvp,key+'.vvp',f'+BASE={key}',f'+MODE={name}'],build,evidence/(name+'.log'))
        elif name in loader_cases:
            full=name=='loader_full_resolution';w,h=(640,480) if full else (31,17)
            c=make_case(name);c.update(width=w,height=h,spc=8 if full else 1,
                                      active=1 if full else 0,real_first=full)
            meta=create_fixture(c,build/name)
            run([iv,'-g2012','-s','tb_team_image_loader',f'-Ptb_team_image_loader.WIDTH={w}',
                 f'-Ptb_team_image_loader.HEIGHT={h}',f'-Ptb_team_image_loader.MAX_LBA={meta["max_lba"]}',
                 '-o','loader.vvp','team_sector_guard.v','team_fat32_file_reader.v',
                 'team_bmp_parser.v','team_frame_store_writer.v','team_image_loader.v','tb_team_image_loader.sv'],
                build,evidence/(name+'_compile.log'))
            text=run([vvp,'loader.vvp',f'+BASE={name}',f'+MODE={name}',f'+FAT={meta["fat"]}',
                      f'+DATA={meta["data"]}',f'+SPC={meta["spc"]}',f'+CLUSTERS={meta["clusters"]}'],
                     build,evidence/(name+'.log'))
        else:
            src,vid={'bridge_src_fast':(3,7),'bridge_video_fast':(11,4),'bridge_equal_clocks':(5,5)}[name]
            run([iv,'-g2012','-s','tb_team_frame_commit',f'-Ptb_team_frame_commit.SRC_HALF={src}',
                 f'-Ptb_team_frame_commit.VIDEO_HALF={vid}','-o','bridge.vvp',
                 'team_frame_commit_bridge.v','tb_team_frame_commit.sv'],build,evidence/(name+'_compile.log'))
            text=run([vvp,'bridge.vvp'],build,evidence/(name+'.log'))
        if 'TEST_PASS' not in text:raise RuntimeError('No pass marker '+name)
        marker=next(t for t in text.splitlines() if 'TEST_PASS' in t)
        result.append(dict(case=name,status='PASS',marker=marker));print('PASS',name,flush=True)
    hashes={str(s.relative_to(ROOT)):hashlib.sha256(s.read_bytes()).hexdigest() for s in sources}
    summary=dict(status='PASS',cases=len(result),results=result,source_sha256=hashes,
                 build_directory=str(build),scope='BMP -> resident slots through acknowledged RAM model; frame-boundary CDC simulation only')
    (evidence/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    print('ALL_PASS cases='+str(len(result)),flush=True)

if __name__=='__main__':main()
