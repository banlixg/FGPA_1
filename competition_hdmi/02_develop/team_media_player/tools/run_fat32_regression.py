"""Sparse FAT32 sector fixtures -> production RTL -> byte/pixel scoreboards.

This program never opens a Windows physical drive or an SD-card drive letter.
All card content is generated in a fresh temporary simulation directory.
"""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import io
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
from PIL import Image
from sim_support import prepare_icarus

ROOT=Path(__file__).resolve().parents[1]


def command(args,cwd,log):
    p=subprocess.run([str(a) for a in args],cwd=cwd,stdout=subprocess.PIPE,
                     stderr=subprocess.STDOUT,timeout=240)
    text=p.stdout.decode('utf-8',errors='replace')
    log.write_text(text,encoding='utf-8')
    if p.returncode or 'FATAL:' in text or 'Fatal:' in text:
        raise RuntimeError(f'Tool failed: {log}\n{text[-4000:]}')
    return text


def bmp(width,height,seed):
    im=Image.new('RGB',(width,height))
    for y in range(height):
        for x in range(width):
            im.putpixel((x,y),((x*17+y*31+seed*53)%256,
                              (x*29+y*7+seed*101)%256,
                              (x*11+y*43+seed*37)%256))
    stride=(width*3+3)//4*4
    size=54+stride*height
    head=bytearray(54)
    struct.pack_into('<2sIHHI',head,0,b'BM',size,0,0,54)
    struct.pack_into('<IiiHHIIiiII',head,14,40,width,-height if seed%2 else height,
                     1,24,0,stride*height,2835,2835,0,0)
    data=bytearray(head)
    for row in range(height):
        y=row if seed%2 else height-1-row
        for x in range(width):
            r,g,b=im.getpixel((x,y));data.extend((b,g,r))
        data.extend(b'\xa9'*(stride-width*3))
    with Image.open(io.BytesIO(data)) as check:
        assert check.convert('RGB').tobytes()==im.tobytes()
    return bytes(data),im


def dir_entry(name,cluster,size,attr=0x20):
    assert len(name)==11
    b=bytearray(32);b[:11]=name;b[11]=attr
    struct.pack_into('<H',b,20,(cluster>>16)&0xffff)
    struct.pack_into('<H',b,26,cluster&0xffff)
    struct.pack_into('<I',b,28,size)
    return bytes(b)


def make_case(name,**options):
    return dict(name=name,volume=2048,spc=1,active=0,width=31,height=17,
                files=4,image_mode=1,mount_error=0,scan_error=0,file_error=0,
                inject=0,close_after=-1,**options)


def create_fixture(c,folder):
    volume=c['volume'];spc=c['spc'];fat_size=600;reserved=32;fats=c.get('fats',2)
    total=70000*spc
    count=(total-reserved-fats*fat_size)//spc
    fat_start=volume+reserved+c['active']*fat_size
    data_start=volume+reserved+fats*fat_size
    sectors={}
    def put(lba,data):
        assert len(data)==512
        sectors[lba]=bytearray(data)
    boot=bytearray(512);boot[:3]=b'\xeb\x58\x90';boot[3:11]=b'TEAMFPGA'
    struct.pack_into('<HBHBHHBHHHII',boot,11,512,spc,reserved,fats,0,0,0xf8,0,63,255,volume,total)
    struct.pack_into('<IHHIHH',boot,36,fat_size,0x80|c['active'] if c['active'] else 0,0,5,1,6)
    boot[64]=0x80;boot[66]=0x29
    struct.pack_into('<I',boot,67,0x1234abcd)
    boot[71:82]=b'TEAM_MEDIA ';boot[82:90]=b'FAT32   ';boot[510:]=b'\x55\xaa'
    if c.get('boot_patch'):
        for pos,value in c['boot_patch']:boot[pos:pos+len(value)]=value
    put(volume,boot)
    info=bytearray(512)
    for pos,value in [(0,0x41615252),(484,0x61417272),(488,0xffffffff),(492,0xffffffff),(508,0xaa550000)]:
        struct.pack_into('<I',info,pos,value)
    put(volume+1,info);put(volume+6,boot);put(volume+7,info)
    if volume:
        mbr=bytearray(512);mbr[510:]=b'\x55\xaa'
        mbr[450]=0x07;struct.pack_into('<II',mbr,454,16,32)
        mbr[482]=0x0c
        struct.pack_into('<II',mbr,486,volume,total-1 if c.get('partition_short') else total)
        if c.get('no_partition'):mbr[482]=0x07
        put(0,mbr)

    def fat(cluster,value):
        lba=fat_start+cluster//128
        if lba not in sectors:put(lba,bytes(512))
        struct.pack_into('<I',sectors[lba],(cluster%128)*4,value)
    fat(0,0x0ffffff8);fat(1,0xffffffff);fat(5,9);fat(9,0x0fffffff)
    if c.get('dir_loop'):fat(5,9);fat(9,5)
    if c.get('dir_bad'):fat(5,0)

    payloads=[];images=[];entries=[];clusters=[]
    for i in range(c['files']):
        if c['image_mode']:
            if c.get('real_first') and i==0:
                payload=(ROOT/'sim/bmp/fixtures/team_03.bmp').read_bytes()
                with Image.open(io.BytesIO(payload)) as image:im=image.convert('RGB')
            else:payload,im=bmp(c['width'],c['height'],i)
        else:
            payload=bytes(j%256 for j in range(c.get('raw_size',2000)))
            im=None
        needed=(len(payload)+512*spc-1)//(512*spc)
        chain=[130+i+4*j for j in range(needed)]
        if c.get('short_chain'):chain=chain[:1]
        if c.get('file_loop'):chain=chain[:2]
        for n,cl in enumerate(chain):
            following=chain[n+1] if n+1<len(chain) else 0x0fffffff
            if c.get('file_loop') and n==len(chain)-1:following=chain[0]
            if c.get('file_bad') and n==0:following=c['file_bad']
            # The high reserved nibble must not change the cluster value.
            fat(cl,0xa0000000|following)
            chunk=payload[n*512*spc:(n+1)*512*spc]
            chunk=chunk.ljust(512*spc,b'\xcc')
            base=data_start+(cl-2)*spc
            for j in range(spc):put(base+j,chunk[j*512:(j+1)*512])
        name=f'TEAM{i+1:04d}'.encode()+[b'BMP',b'bmp',b'BmP',b'BMP'][i%4]
        entries.append(dir_entry(name,chain[0],len(payload)))
        clusters.append(chain[0]);payloads.append(payload);images.append(im)

    # A full first directory cluster forces traversal to a nonadjacent cluster.
    # It also contains LFN, deleted, directory, volume-label and non-BMP records.
    root1=bytearray(b''.join(dir_entry(b'IGNORE  BMP',0,100,attr=0x20) for _ in range(16*spc)))
    for i in range(16*spc):root1[i*32]=0xe5
    root1[0:32]=dir_entry(b'LONGNAMEBMP',130,100,attr=0x0f)
    root1[32:64]=dir_entry(b'SUBDIR  BMP',130,100,attr=0x10)
    root1[64:96]=dir_entry(b'VOLUME  BMP',130,100,attr=0x08)
    root1[96:128]=dir_entry(b'NOTIMAGE' + b'TXT',130,100)
    root2=bytearray(512*spc)
    if c.get('dir_loop') or c.get('dir_bad'):
        root2[:]=b''.join(bytes([0xe5])+bytes(31) for _ in range(16*spc))
    elif entries:
        root1[-32:]=entries[0]
        for i,entry in enumerate(entries[1:]):root2[i*32:(i+1)*32]=entry
    else:root1[0]=0
    for cl,content in [(5,root1),(9,root2)]:
        base=data_start+(cl-2)*spc
        for j in range(spc):put(base+j,content[j*512:(j+1)*512])

    folder.mkdir()
    with (folder/'card.hex').open('w',encoding='ascii') as f:
        for lba,data in sorted(sectors.items()):
            f.write(f'@{lba*512:x}\n');f.writelines(f'{b:02x}\n' for b in data)
    with (folder/'present.hex').open('w',encoding='ascii') as f:
        for lba in sorted(sectors):f.write(f'@{lba:x}\n1\n')
    with (folder/'entries.hex').open('w',encoding='ascii') as f:
        for entry in entries:
            first=(struct.unpack_from('<H',entry,20)[0]<<16)|struct.unpack_from('<H',entry,26)[0]
            size=struct.unpack_from('<I',entry,28)[0]
            v=(int.from_bytes(entry[:11],'big')<<60)|(first<<32)|size
            f.write(f'{v:037x}\n')
    with (folder/'bytes.hex').open('w',encoding='ascii') as f:
        for payload in payloads:f.writelines(f'{b:02x}\n' for b in payload)
    with (folder/'pixels.hex').open('w',encoding='ascii') as f:
        for payload,im in zip(payloads,images):
            if im is None:continue
            w,h=im.size;top_down=struct.unpack_from('<i',payload,22)[0]<0
            for row in range(h):
                y=row if top_down else h-1-row
                for x in range(w):
                    red,green,blue=im.getpixel((x,y))
                    v=(x<<40)|(y<<24)|(red<<16)|(green<<8)|blue
                    f.write(f'{v:014x}\n')
    return dict(max_lba=max(sectors),expected_bytes=max(1,sum(map(len,payloads))),
                volume=volume,fat=fat_start,data=data_start,spc=spc,clusters=count,
                payload_sha256=[hashlib.sha256(p).hexdigest() for p in payloads])


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--case',action='append',help='Run only selected named cases')
    p.add_argument('--iverilog-bin',type=Path,help='Existing Icarus bin directory; otherwise private runtime, IVERILOG_BIN or PATH')
    args=p.parse_args()
    evidence=ROOT/'records'/('fat32_'+dt.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    evidence.mkdir(parents=True,exist_ok=False)
    build=Path(tempfile.mkdtemp(prefix='team_fat32_'))
    compiler,runtime=prepare_icarus(build,args.iverilog_bin)
    sources=sorted((ROOT/'rtl/storage').glob('*.v'))+[ROOT/'rtl/image/team_bmp_parser.v',ROOT/'sim/fat32/tb_team_fat32.sv']
    for source in sources:shutil.copyfile(source,build/source.name)
    cases=[]
    def add(name,**kw):
        c=make_case(name);c.update(kw);cases.append(c)
    add('mbr_fragmented_four_images')
    add('superfloppy',volume=0)
    add('active_fat1',active=1)
    add('one_fat_copy',fats=1)
    add('two_sector_clusters',spc=2)
    add('eight_sector_clusters',spc=8)
    add('empty_directory',files=0)
    add('boot_signature',volume=0,boot_patch=[(510,b'\x00\x00')],mount_error=4)
    add('no_fat32_partition',no_partition=True,mount_error=5)
    add('sector_size_1024',volume=0,boot_patch=[(11,struct.pack('<H',1024))],mount_error=6)
    add('non_power_of_two_cluster',volume=0,boot_patch=[(13,b'\x03')],mount_error=6)
    add('not_enough_fat32_clusters',volume=0,boot_patch=[(32,struct.pack('<I',62000))],mount_error=6)
    add('fat_table_too_small',volume=0,boot_patch=[(36,struct.pack('<I',1))],mount_error=6)
    add('root_cluster_out_of_range',volume=0,boot_patch=[(44,struct.pack('<I',100000))],mount_error=6)
    add('unsupported_fs_version',volume=0,boot_patch=[(42,struct.pack('<H',1))],mount_error=6)
    add('invalid_active_fat',volume=0,boot_patch=[(40,struct.pack('<H',0x82))],mount_error=6)
    add('unsupported_fat_count',volume=0,boot_patch=[(16,b'\x03')],mount_error=6)
    add('partition_bounds',partition_short=True,mount_error=6)
    add('sector_io_error',inject=1,mount_error=1)
    add('short_sector',inject=2,mount_error=2)
    add('sector_timeout',inject=3,mount_error=3)
    add('directory_cycle',files=0,dir_loop=True,scan_error=8)
    add('directory_free_cluster',files=0,dir_bad=True,scan_error=7)
    add('file_premature_eoc',files=1,image_mode=0,short_chain=True,file_error=7)
    add('file_cycle',files=1,image_mode=0,raw_size=4000,file_loop=True,file_error=8)
    add('file_bad_cluster',files=1,image_mode=0,file_bad=0x0ffffff7,file_error=7)
    add('file_cluster_out_of_range',files=1,image_mode=0,file_bad=100000,file_error=7)
    add('file_early_close',files=1,image_mode=0,close_after=73)
    add('four_full_resolution_images',width=640,height=480,spc=8,active=1,real_first=True)
    if args.case:
        unknown=set(args.case)-{c['name'] for c in cases}
        if unknown:raise SystemExit('Unknown cases: '+str(unknown))
        cases=[c for c in cases if c['name'] in args.case]
    print('BUILD',build,flush=True);print('EVIDENCE',evidence,flush=True)
    result=[]
    for c in cases:
        name=c['name'];meta=create_fixture(c,build/name)
        generics={'WIDTH':c['width'],'HEIGHT':c['height'],'MAX_LBA':meta['max_lba'],
                  'EXPECTED_BYTES':meta['expected_bytes'],'FILES':max(c['files'],1)}
        command([compiler,'-g2012','-s','tb_team_fat32',
                 *[f'-Ptb_team_fat32.{k}={v}' for k,v in generics.items()],
                 '-o',name+'.vvp',*[s.name for s in sources]],build,evidence/(name+'_compile.log'))
        switches={'IMAGE':name+'/card.hex','PRESENT':name+'/present.hex',
                  'ENTRIES':name+'/entries.hex','BYTES':name+'/bytes.hex','PIXELS':name+'/pixels.hex',
                  'MOUNT_ERROR':c['mount_error'],'SCAN_ERROR':c['scan_error'],
                  'FILE_ERROR':c['file_error'],'INJECT':c['inject'],'NUM_FILES':c['files'],
                  'IMAGE_MODE':c['image_mode'],'CLOSE_AFTER':c['close_after'],
                  'VOLUME':meta['volume'],'FAT':meta['fat'],'DATA':meta['data'],
                  'SPC':meta['spc'],'CLUSTERS':meta['clusters']}
        text=command([runtime,name+'.vvp',*[f'+{k}={v}' for k,v in switches.items()]],
                     build,evidence/(name+'.log'))
        if 'TEST_PASS' not in text:raise RuntimeError('No pass marker for '+name)
        marker=next(line for line in text.splitlines() if 'TEST_PASS' in line)
        result.append(dict(case=name,status='PASS',marker=marker,fixture=meta))
        print('PASS',name,flush=True)
    hashes={str(s.relative_to(ROOT)):hashlib.sha256(s.read_bytes()).hexdigest() for s in sources}
    summary=dict(status='PASS',cases=len(result),results=result,source_sha256=hashes,
                 build_directory=str(build),scope='Sparse card-model RTL integration; no physical card or board access')
    (evidence/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    print('ALL_PASS cases='+str(len(result)),flush=True)


if __name__=='__main__':main()
