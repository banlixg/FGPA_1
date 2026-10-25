"""Verify independent fade RTL and render a preview FROM simulated RGB output.

No physical SD-card access, board programming, package installation or licences.
Existing simulation tools are resolved by the main project's sim_support helper.
"""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

EXT=Path(__file__).resolve().parents[1]
ROOT=EXT.parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from sim_support import prepare_icarus
from PIL import Image,ImageDraw,ImageChops

MODES=['normal_step8','normal_step7','normal_step1','normal_step0','normal_step256',
       'normal_step511','disabled','latched_config','immediate_reply','stale_reply_then_correct',
       'delayed_reply','repeat_two','queued_request','invalid_target','request_timeout',
       'missing_frame_tick','reply_timeout','fault_recovery','reply_error','wrong_slot',
       'missing_frame_after_reply','abort_out','abort_issue','abort_wait','abort_in','reset_out','reset_wait']

def command(args,cwd,log):
    p=subprocess.run(list(map(str,args)),cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=360)
    text=p.stdout.decode('utf-8',errors='replace')
    log.write_text(text,encoding='utf-8')
    if p.returncode or 'FATAL:' in text or 'Fatal:' in text:
        raise RuntimeError(str(log)+'\n'+text[-3500:])
    return text

def make_preview(build):
    raw=(build/'preview.rgb').read_bytes();w,h,n=160,120,75
    assert len(raw)==w*h*n*3,(len(raw),w*h*n*3)
    rows=[list(map(int,x.split())) for x in (build/'preview_frames.txt').read_text().splitlines()]
    assert len(rows)==n and [r[0] for r in rows]==list(range(n))
    frames=[Image.frombytes('RGB',(w,h),raw[i*w*h*3:(i+1)*w*h*3]) for i in range(n)]
    # Every frame is checked, separately from the SV pixel scoreboard.
    for image,(_,gain,phase,slot) in zip(frames,rows):
        if gain==0:assert not any(image.tobytes()),'nonblack output in black hold'
    for i in range(1,n):
        if rows[i][3]!=rows[i-1][3]:continue
        if rows[i][1]<=rows[i-1][1]:
            assert ImageChops.subtract(frames[i],frames[i-1]).getbbox() is None,'fade-out pixel increased'
        else:
            assert ImageChops.subtract(frames[i-1],frames[i]).getbbox() is None,'fade-in pixel decreased'
    assert sum(r[1]==0 for r in rows)>=1
    assert rows[-1][1]==256 and rows[-1][3]==1
    target=EXT/'preview';target.mkdir(exist_ok=True)
    durations=[20,10,20]*(n//3)
    frames[0].save(target/'rtl_fade.gif',save_all=True,append_images=frames[1:],
                   duration=durations,loop=0,optimize=False,disposal=2)
    picks=[2,10,18,26,34,38,46,54,62,74]
    sheet=Image.new('RGB',(5*w,2*(h+22)),(238,238,238));draw=ImageDraw.Draw(sheet)
    for tile,index in enumerate(picks):
        x=(tile%5)*w;y=(tile//5)*(h+22)
        sheet.paste(frames[index],(x,y));r=rows[index]
        draw.text((x+3,y+h+3),f'frame {index} gain {r[1]} slot {r[3]}',fill=(20,20,20))
    sheet.save(target/'rtl_contact_sheet.png')
    shutil.copyfile(build/'preview_frames.txt',target/'preview_frames.txt')
    return dict(frames=n,width=w,height=h,raw_sha256=hashlib.sha256(raw).hexdigest(),
                gif_sha256=hashlib.sha256((target/'rtl_fade.gif').read_bytes()).hexdigest(),
                scope='RGB from RTL simulation; display at nominal 60fps; not board capture')

def main():
    p=argparse.ArgumentParser();p.add_argument('--iverilog-bin',type=Path);p.add_argument('--case',action='append')
    a=p.parse_args();available=['rgb_exhaustive']+['ctrl_'+m for m in MODES]+['video_640x480','rtl_preview']
    if a.case and set(a.case)-set(available):raise SystemExit('Unknown cases: '+str(set(a.case)-set(available)))
    cases=[c for c in available if not a.case or c in a.case]
    evidence=EXT/'records'/('fade_'+dt.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    evidence.mkdir(parents=True,exist_ok=False);build=Path(tempfile.mkdtemp(prefix='team_fade_'))
    iv,vvp=prepare_icarus(build,a.iverilog_bin)
    sources=sorted((EXT/'rtl').glob('*.v'))+sorted((EXT/'sim').glob('*.sv'))
    for f in sources:shutil.copyfile(f,build/f.name)
    rtl=[p.name for p in (EXT/'rtl').glob('*.v')]
    print('BUILD',build,flush=True);print('EVIDENCE',evidence,flush=True)
    command([iv,'-g2001','-t','null','-s','team_fade_effect',*rtl],build,evidence/'production_verilog2001.log')
    result=[];compiled=set();preview=None
    for case in cases:
        if case=='rgb_exhaustive':
            command([iv,'-g2012','-s','tb_team_fade_rgb','-o','rgb.vvp',*rtl,'tb_team_fade_rgb.sv'],build,evidence/'rgb_compile.log')
            text=command([vvp,'rgb.vvp'],build,evidence/(case+'.log'))
        elif case.startswith('ctrl_'):
            if 'ctrl' not in compiled:
                command([iv,'-g2012','-s','tb_team_fade_ctrl','-o','ctrl.vvp',*rtl,'tb_team_fade_ctrl.sv'],build,evidence/'ctrl_compile.log')
                compiled.add('ctrl')
            text=command([vvp,'ctrl.vvp','+MODE='+case[5:]],build,evidence/(case+'.log'))
        else:
            w,h,n,step,capture=(640,480,12,128,0) if case=='video_640x480' else (160,120,75,8,1)
            generic=[f'-Ptb_team_fade_effect.{k}={v}' for k,v in dict(WIDTH=w,HEIGHT=h,FRAMES=n,STEP=step,CAPTURE=capture).items()]
            command([iv,'-g2012','-s','tb_team_fade_effect',*generic,'-o','effect.vvp',*rtl,'tb_team_fade_effect.sv'],build,evidence/(case+'_compile.log'))
            text=command([vvp,'effect.vvp','+RAW=preview.rgb','+META=preview_frames.txt'],build,evidence/(case+'.log'))
            if capture:preview=make_preview(build)
        if 'TEST_PASS' not in text:raise RuntimeError('No success marker: '+case)
        marker=next(x for x in text.splitlines() if 'TEST_PASS' in x)
        result.append(dict(case=case,status='PASS',marker=marker));print('PASS',case,flush=True)
    summary=dict(status='PASS',cases=len(result),results=result,
                 source_sha256={f.relative_to(EXT).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in sources},
                 preview=preview,build_directory=str(build),scope='Independent RTL simulation only; no TD timing or physical display evidence')
    (evidence/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('ALL_PASS cases='+str(len(result)),flush=True)

if __name__=='__main__':main()
