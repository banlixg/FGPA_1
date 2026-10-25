"""Generate independent BMP fixtures and run the installed ModelSim compiler.

No SD-card access, network access, tool installation, or reference RTL import.
Build output goes to a fresh ASCII temp directory; evidence goes to a new
records directory. Existing logs/results are preserved.
"""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

from PIL import Image
from sim_support import locate_icarus, prepare_icarus

ROOT = Path(__file__).resolve().parents[1]


def make_bmp(width, height, *, top_down=False, dib_size=40, gap=0, tail=0):
    """Construct bytes from the BMP layout; Pillow independently checks colors."""
    image = Image.new("RGB", (width, height))
    for y in range(height):
        for x in range(width):
            image.putpixel((x, y), ((31*x+19*y+7)%256,
                                   (13*x+41*y+29)%256, (53*x+11*y+101)%256))
    stride = (width*3+3)//4*4
    offset = 14+dib_size+gap
    size = offset+stride*height+tail
    head = bytearray(offset)
    struct.pack_into("<2sIHHI", head, 0, b"BM", size, 0, 0, offset)
    struct.pack_into("<IiiHHIIiiII", head, 14, dib_size, width,
                     -height if top_down else height, 1, 24, 0,
                     stride*height, 2835, 2835, 0, 0)
    rows = []
    for row in range(height):
        y = row if top_down else height-1-row
        data = bytearray()
        for x in range(width):
            red, green, blue = image.getpixel((x,y))
            data.extend((blue,green,red))
        data.extend(b"\xa5"*(stride-width*3))
        rows.append(data)
    return bytes(head)+b"".join(rows)+b"\xc7"*tail, image


def write_hex(path, values, width):
    with path.open("w",encoding="ascii") as f:
        f.writelines(f"{v:0{width}x}\n" for v in values)


def run_command(args, cwd, logfile):
    completed = subprocess.run([str(a) for a in args], cwd=cwd,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    text = completed.stdout.decode("utf-8",errors="replace")
    logfile.write_text(text,encoding="utf-8")
    if completed.returncode:
        raise RuntimeError(f"Tool failed ({completed.returncode}): {logfile}\n{text[-3500:]}")
    return text


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--engine",choices=["modelsim","icarus"],default="icarus")
    parser.add_argument("--modelsim-bin",type=Path,default=Path(r"D:\modeltech64_10.4\win64"))
    parser.add_argument("--iverilog-bin",type=Path)
    parser.add_argument("--real-bmp",type=Path,default=ROOT/"sim/bmp/fixtures/team_03.bmp")
    args=parser.parse_args()
    if args.real_bmp:
        args.real_bmp=args.real_bmp.resolve(strict=True)
    if args.engine=="icarus":
        args.iverilog_bin=locate_icarus(args.iverilog_bin)
    if args.engine=="modelsim":
        for tool in ("vlib.exe","vmap.exe","vlog.exe","vsim.exe"):
            if not (args.modelsim_bin/tool).is_file():
                raise SystemExit(f"Missing installed tool: {args.modelsim_bin/tool}")
    stamp=dt.datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    evidence=ROOT/"records"/("bmp_"+stamp)
    evidence.mkdir(parents=True,exist_ok=False)
    build=Path(tempfile.mkdtemp(prefix="team_bmp_"))
    print("EVIDENCE",evidence,flush=True)
    print("BUILD",build,flush=True)
    if args.engine=="icarus":
        compiler,runtime=prepare_icarus(build,args.iverilog_bin)
    for source in [ROOT/"rtl/image/team_bmp_parser.v",ROOT/"sim/bmp/tb_team_bmp_parser.sv"]:
        shutil.copyfile(source,build/source.name)
    if args.engine=="modelsim":
        run_command([args.modelsim_bin/"vlib.exe","work"],build,evidence/"01_vlib.log")
        # Keep mapping local; do not modify the simulator installation's modelsim.ini.
        run_command([args.modelsim_bin/"vmap.exe","-c"],build,evidence/"02_vmap_copy.log")
        run_command([args.modelsim_bin/"vmap.exe","work","work"],build,evidence/"03_vmap.log")
        run_command([args.modelsim_bin/"vlog.exe","-work","work","team_bmp_parser.v"],build,evidence/"04_rtl_compile.log")
        run_command([args.modelsim_bin/"vlog.exe","-sv","-work","work","tb_team_bmp_parser.sv"],build,evidence/"05_tb_compile.log")
    else:
        run_command([compiler,"-V"],build,evidence/"01_tool_version.log")
        run_command([compiler,"-g2001","-t","null","-s","team_bmp_parser","team_bmp_parser.v"],build,evidence/"04_rtl_compile.log")

    cases=[]
    def add(name, *, width=3,height=2,top_down=False,dib_size=40,gap=0,tail=0,
            patch=None,error=0,truncate=None,abort_after=None,repeats=1):
        data,image=make_bmp(width,height,top_down=top_down,dib_size=dib_size,gap=gap,tail=tail)
        source_size=len(data)
        if patch:
            data=bytearray(data)
            for pos,payload in patch:
                data[pos:pos+len(payload)]=payload
            data=bytes(data)
        if truncate is not None:data=data[:truncate]
        cases.append(dict(name=name,width=width,height=height,data=data,image=image,
                          top_down=top_down,error=error,source_size=source_size,
                          abort_after=abort_after,repeats=repeats))

    add("bottom_up_padding",repeats=3)
    add("top_down_offset",top_down=True,gap=16)
    add("extended_dib",dib_size=108,gap=12)
    add("trailing_metadata",tail=23)
    add("one_pixel_rows",width=1,height=4)
    add("no_row_padding",width=4,height=3)
    add("bad_signature",patch=[(0,b"ZZ")],error=3)
    add("bad_dib",patch=[(14,struct.pack("<I",12))],error=4)
    add("bad_offset",patch=[(10,struct.pack("<I",20))],error=4)
    add("wrong_width",patch=[(18,struct.pack("<i",4))],error=5)
    add("wrong_height",patch=[(22,struct.pack("<i",3))],error=5)
    add("wrong_depth",patch=[(28,struct.pack("<H",32))],error=6)
    add("wrong_planes",patch=[(26,struct.pack("<H",0))],error=6)
    add("compressed",patch=[(30,struct.pack("<I",1))],error=7)
    add("declared_too_large",patch=[(2,struct.pack("<I",9999))],error=8)
    add("declared_too_small",patch=[(2,struct.pack("<I",54))],error=8)
    add("offset_overflow",patch=[(10,struct.pack("<I",0xfffffff0))],error=8)
    add("truncated_header",truncate=25,error=2)
    add("truncated_pixel_stream",truncate=64,error=2)
    add("transport_abort",abort_after=62,error=1)
    add("full_640x480",width=640,height=480)

    if args.real_bmp:
        data=args.real_bmp.read_bytes()
        with Image.open(args.real_bmp) as original:
            if original.format!="BMP" or original.size!=(640,480):
                raise ValueError("Real fixture must be an actual 640x480 BMP")
            image=original.convert("RGB")
        if struct.unpack_from("<H",data,28)[0]!=24 or struct.unpack_from("<I",data,30)[0]!=0:
            raise ValueError("Real fixture must be 24-bit BI_RGB")
        cases.append(dict(name="real_team_bmp",width=640,height=480,data=data,
                          image=image,top_down=struct.unpack_from("<i",data,22)[0]<0,
                          error=0,source_size=len(data),abort_after=None,repeats=1))

    results=[]
    for case in cases:
        name=case["name"]
        image=case["image"]
        data=case["data"]
        w,h=case["width"],case["height"]
        write_hex(build/(name+".hex"),data,2)
        def pixels():
            for row in range(h):
                y=row if case["top_down"] else h-1-row
                for x in range(w):
                    red,green,blue=image.getpixel((x,y))
                    yield (x<<40)|(y<<24)|(red<<16)|(green<<8)|blue
        write_hex(build/(name+"_expected.hex"),pixels(),14)
        # Independently decode valid generated files with Pillow too.
        if case["error"]==0:
            (build/(name+".bmp")).write_bytes(data)
            with Image.open(build/(name+".bmp")) as decoded:
                assert decoded.convert("RGB").tobytes()==image.tobytes()
        commands=["onerror {quit -force -code 1}","onbreak {quit -force -code 1}",
                  "run -all","quit -force -code 0"]
        (build/"run_case.do").write_text("\n".join(commands)+"\n",encoding="ascii")
        plusargs=["+INPUT="+name+".hex","+EXPECTED="+name+"_expected.hex",
                 "+BYTES="+str(len(data)),"+PIXELS="+str(w*h),
                 "+ERROR="+str(case["error"]),"+SOURCE_SIZE="+str(case["source_size"]),
                 "+REPEATS="+str(case["repeats"])]
        if case["abort_after"] is not None:
            plusargs.append("+ABORT_AFTER="+str(case["abort_after"]))
        if args.engine=="modelsim":
            command=[args.modelsim_bin/"vsim.exe","-c","-onfinish","stop",
                     "-gWIDTH="+str(w),"-gHEIGHT="+str(h),"-gINPUT_CAP="+str(len(data)),
                     "work.tb_team_bmp_parser",*plusargs,"-do","run_case.do"]
        else:
            run_command([compiler,"-g2012","-s","tb_team_bmp_parser",
                         "-Ptb_team_bmp_parser.WIDTH="+str(w),
                         "-Ptb_team_bmp_parser.HEIGHT="+str(h),
                         "-Ptb_team_bmp_parser.INPUT_CAP="+str(len(data)),
                         "-o",name+".vvp","team_bmp_parser.v","tb_team_bmp_parser.sv"],
                        build,evidence/(name+"_compile.log"))
            command=[runtime,name+".vvp",*plusargs]
        text=run_command(command,build,evidence/(name+".log"))
        if "TEST_PASS" not in text or "Fatal:" in text:
            raise RuntimeError(f"No verified pass for {name}: {text[-3000:]}")
        marker=next(line for line in text.splitlines() if "TEST_PASS" in line)
        results.append(dict(case=name,status="PASS",marker=marker))
        print("PASS",name,flush=True)

    summary=dict(status="PASS",engine=args.engine,cases=len(results),results=results,build_directory=str(build),
                 real_fixture=str(args.real_bmp) if args.real_bmp else None,
                 rtl_sha256=hashlib.sha256((ROOT/"rtl/image/team_bmp_parser.v").read_bytes()).hexdigest(),
                 scope="Standalone RTL simulation; no TD synthesis or board verification")
    (evidence/"summary.json").write_text(json.dumps(summary,indent=2,ensure_ascii=False),encoding="utf-8")
    print(f"ALL_PASS cases={len(results)}",flush=True)
    print("EVIDENCE",evidence,flush=True)


if __name__=="__main__":
    main()
