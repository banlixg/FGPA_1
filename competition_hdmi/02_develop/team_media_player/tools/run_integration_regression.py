"""New physical SPI protocol and complete boot-to-resident-frame scoreboards."""
from __future__ import annotations
import argparse,datetime as dt,hashlib,json,shutil,subprocess,tempfile,struct
from pathlib import Path
from sim_support import prepare_icarus
from run_fat32_regression import make_case,create_fixture,dir_entry
ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser();p.add_argument('--iverilog-bin',type=Path);p.add_argument('--case',action='append');a=p.parse_args()
    evidence=ROOT/'records'/('integration_'+dt.datetime.now().strftime('%Y%m%d_%H%M%S_%f'));evidence.mkdir()
    build=Path(tempfile.mkdtemp(prefix='team_integrate_'));iv,vvp=prepare_icarus(build,a.iverilog_bin)
    sources=sorted((ROOT/'rtl').rglob('*.v'))+sorted((ROOT/'extensions/fade/rtl').glob('*.v'))+sorted((ROOT/'sim/integration').glob('*.sv'))
    for s in sources:shutil.copyfile(s,build/s.name)
    results=[]
    def run(args,name):
        r=subprocess.run(list(map(str,args)),cwd=build,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=360)
        t=r.stdout.decode('utf8','replace');(evidence/(name+'.log')).write_text(t,encoding='utf8')
        if r.returncode or 'FATAL:' in t:raise RuntimeError(name+'\n'+t[-4000:])
        return t
    cases=['sdhc','sdsc','bad_r7','no_response','crc_error','r1_error','token_error','token_timeout','cancel_physical','cancel_stream',
           'boot_four','boot_skip_bad','boot_insufficient','boot_empty','boot_full',
           'display','display_full','pcm','core','control','memory_ok','memory_bad_readback','memory_timeout','line_timeout',
           'wav_mono','wav_stereo','wav_chunks','wav_rate','wav_depth','wav_truncated','wav_no_fmt','wav_bounds']
    chosen=a.case or cases
    if set(chosen)-set(cases):raise SystemExit('Unknown cases')
    run([iv,'-g2012','-s','tb_sd_spi','-o','spi.vvp','team_spi_byte.v','team_sd_spi_reader.v','tb_sd_spi.sv'],'spi_compile')
    for name in chosen:
        if name=='control' or name.startswith('memory_') or name=='line_timeout':
            top='tb_control' if name=='control' else 'tb_memory_port'
            run([iv,'-g2012','-s',top,'-o','extra.vvp',*[s.name for s in sources]],name+'_compile')
            t=run([vvp,'extra.vvp','+MODE='+name],name)
        elif name=='core':
            c=make_case(name);meta=create_fixture(c,build/name)
            lines=(build/name/'card.hex').read_text().splitlines();card={};at=0
            for line in lines:
                if line.startswith('@'):at=int(line[1:],16)
                else:card[at]=int(line,16);at+=1
            samples=[];pcm=bytearray()
            for i in range(500):
                l=(i*101+0x8000)&65535;r=(i*317+0xf000)&65535;samples.append((l<<16)|r);pcm+=struct.pack('<HH',l,r)
            fmt=struct.pack('<HHIIHH',1,2,48000,192000,4,16)
            chunks=b'fmt '+struct.pack('<I',16)+fmt+b'data'+struct.pack('<I',len(pcm))+pcm
            wav=b'RIFF'+struct.pack('<I',4+len(chunks))+b'WAVE'+chunks
            first=2000;needed=(len(wav)+511)//512
            for i in range(needed):
                cl=first+i*2;fatat=(meta['fat']+cl//128)*512+(cl%128)*4
                for off in range(512):card.setdefault((meta['fat']+cl//128)*512+off,0)
                for j,b in enumerate(struct.pack('<I',cl+2 if i+1<needed else 0x0fffffff)):card[fatat+j]=b
                for j,b in enumerate(wav[i*512:(i+1)*512].ljust(512,b'\xcc')):card[(meta['data']+cl-2)*512+j]=b
            for j,b in enumerate(dir_entry(b'AUDIO   WAV',first,len(wav))):card[(meta['data']+7)*512+96+j]=b
            with (build/name/'card.hex').open('w') as f:
                prev=-2
                for at,b in sorted(card.items()):
                    if at!=prev+1:f.write(f'@{at:x}\n')
                    f.write(f'{b:02x}\n');prev=at
            max_lba=max(card)//512
            (build/name/'present.hex').write_text(''.join(f'@{l:x}\n1\n' for l in sorted({at//512 for at in card})))
            (build/name/'samples.hex').write_text(''.join(f'{v:08x}\n' for v in samples))
            run([iv,'-g2012','-s','tb_core',f'-Ptb_core.MAX_LBA={max_lba}','-o','core.vvp',*[s.name for s in sources]],name+'_compile')
            t=run([vvp,'core.vvp','+BASE='+name],name)
        elif name=='pcm':
            run([iv,'-g2012','-s','tb_pcm','-o','pcm.vvp',*[s.name for s in sources]],name+'_compile')
            t=run([vvp,'pcm.vvp'],name)
        elif name.startswith('display'):
            gs=dict(WIDTH=640,HEIGHT=480,HTOTAL=800,VTOTAL=525) if name.endswith('full') else {}
            run([iv,'-g2012','-s','tb_display',*[f'-Ptb_display.{k}={v}' for k,v in gs.items()],'-o','display.vvp',*[s.name for s in sources]],name+'_compile')
            t=run([vvp,'display.vvp','+MODE='+name],name)
        elif name.startswith('wav_'):
            folder=build/name;folder.mkdir();channels=1 if name=='wav_mono' else 2;ns=99;frames=[];pcm=bytearray()
            for i in range(ns):
                l=(i*1009+0x8000)&65535;r=(i*337+0xff00)&65535 if channels==2 else l
                frames.append((l<<16)|r);pcm+=struct.pack('<H',l)
                if channels==2:pcm+=struct.pack('<H',r)
            fmt=struct.pack('<HHIIHH',1,channels,44100 if name=='wav_rate' else 48000,channels*96000,channels*2,8 if name=='wav_depth' else 16)
            def chunk(id,data):return id+struct.pack('<I',len(data))+data+(b'\x00' if len(data)%2 else b'')
            chunks=(chunk(b'JUNK',b'abcde') if name=='wav_chunks' else b'')
            if name!='wav_no_fmt':chunks+=chunk(b'fmt ',fmt+(b'\0\0' if name=='wav_chunks' else b''))
            chunks+=chunk(b'data',pcm)
            raw=b'RIFF'+struct.pack('<I',4+len(chunks))+b'WAVE'+chunks
            error=5 if name in ['wav_rate','wav_depth'] else 6 if name=='wav_no_fmt' else 4 if name in ['wav_truncated','wav_bounds'] else 0
            if name=='wav_truncated':raw=raw[:-17]
            if name=='wav_bounds':raw=raw[:4]+struct.pack('<I',0xffffffff)+raw[8:]
            (folder/'wav.hex').write_text(''.join(f'{v:02x}\n' for v in raw));(folder/'samples.hex').write_text(''.join(f'{v:08x}\n' for v in frames))
            gs=dict(SIZE=len(raw),SAMPLES=ns,ERROR=error)
            run([iv,'-g2012','-s','tb_wav',*[f'-Ptb_wav.{k}={v}' for k,v in gs.items()],'-o','wav.vvp',*[s.name for s in sources]],name+'_compile')
            t=run([vvp,'wav.vvp','+BASE='+name],name)
        elif name.startswith('boot_'):
            full=name=='boot_full';w,h=(640,480) if full else (31,17)
            expected=2 if name=='boot_insufficient' else 0 if name=='boot_empty' else 4
            c=make_case(name);c.update(width=w,height=h,spc=8 if full else 1,files=expected)
            meta=create_fixture(c,build/name)
            rejected=2 if name=='boot_skip_bad' else 0
            if rejected:
                # Keep all four real files; prepend two descriptors with truncated lengths.
                lines=(build/name/'card.hex').read_text().splitlines();sectors={};at=0
                for line in lines:
                    if line.startswith('@'):at=int(line[1:],16)
                    else:sectors[at]=int(line,16);at+=1
                root1=(meta['data']+3*c['spc'])*512;root2=(meta['data']+7*c['spc'])*512
                entries=[bytes(sectors[root1+480+j] for j in range(32))]
                entries += [bytes(sectors[root2+i*32+j] for j in range(32)) for i in range(3)]
                bad=dir_entry(b'BROKEN01BMP',130,54)
                for j,b in enumerate(bad):sectors[root1+480+j]=b
                payload=dir_entry(b'BROKEN02BMP',130,55)+b''.join(entries)+bytes(512-160)
                for j,b in enumerate(payload):sectors[root2+j]=b
                with (build/name/'card.hex').open('w') as f:
                    previous=-2
                    for at,b in sorted(sectors.items()):
                        if at!=previous+1:f.write(f'@{at:x}\n')
                        f.write(f'{b:02x}\n');previous=at
            generics=dict(WIDTH=w,HEIGHT=h,MAX_LBA=meta['max_lba'],EXPECTED=expected,REJECTED=rejected)
            run([iv,'-g2012','-s','tb_boot',*[f'-Ptb_boot.{k}={v}' for k,v in generics.items()],'-o','boot.vvp',*[s.name for s in sources]],name+'_compile')
            t=run([vvp,'boot.vvp','+BASE='+name],name)
        else:t=run([vvp,'spi.vvp','+MODE='+name],name)
        if 'TEST_PASS' not in t:raise RuntimeError(name+' missing pass')
        results.append(dict(case=name,status='PASS',marker=next(l for l in t.splitlines() if 'TEST_PASS' in l)))
        print('PASS',name,flush=True)
    summary=dict(status='PASS',cases=len(results),results=results,source_sha256={str(s.relative_to(ROOT)):hashlib.sha256(s.read_bytes()).hexdigest() for s in sources},
                 scope='Digital SPI card model and sector/RAM boot model; not board verification',build_directory=str(build))
    (evidence/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf8');print('ALL_PASS',len(results),evidence,flush=True)
if __name__=='__main__':main()
