"""Copy only platform IP from the explicitly supplied stable reference, hash provenance.
Creates a NEW board project. Refuses to overwrite vendor files with different bytes.
"""
import argparse,hashlib,json,xml.etree.ElementTree as E,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    p=argparse.ArgumentParser();p.add_argument('--reference',type=Path,required=True);a=p.parse_args()
    src=a.reference/'src/user_source/hdl_source';dest=ROOT/'board/vendor';dest.mkdir(parents=True,exist_ok=True)
    files=['IP/sys_pll.v','IP/video_pll.v','hdmi_phy_warpper.v','lane_lvds_10_1.v',
           'hdmi1.4b_transmitter_core/hdmi_1_4b_transmitter_core_wrapper.enc.v',
           'include/global_def.v','include/sdr_as_ram.enc.v','include/sdr_init_ref.enc.v','include/sdr_wrrd.enc.v','SD/sdram.v']
    manifest=[]
    for name in files:
        original=(src/name).read_bytes();content=original.replace(b'"../user_source/hdl_source/include/global_def.v"',b'"global_def.v"');out=dest/Path(name).name
        if name=='include/global_def.v':content=content.replace(b'125000000',b'50000000')
        if name=='SD/sdram.v':
            content=original.replace(b'module sdram(',b'module team_board_sdram(').replace(b'"../user_source/hdl_source/include/global_def.v"',b'"global_def.v"')
            out=dest/'team_board_sdram.v'
        if out.exists() and out.read_bytes() not in (original,content):raise SystemExit('Refusing to overwrite '+str(out))
        out.write_bytes(content)
        manifest.append(dict(source=str(src/name),file=str(out.relative_to(ROOT)),original_sha256=hashlib.sha256(original).hexdigest(),sha256=hashlib.sha256(content).hexdigest(),
                             modifications='module renamed and include path made local' if name=='SD/sdram.v' else 'refresh period configured for 50 MHz' if name=='include/global_def.v' else 'plaintext include path made local' if content!=original else 'none'))
    (ROOT/'board/vendor_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
    pll=(src/'IP/sys_pll.v').read_text(encoding='utf8').replace('module sys_pll (','module team_mem_pll (')
    pll=pll.replace('.FEEDBK_MODE("NORMAL")','.FEEDBK_MODE("NOCOMP")').replace('.FEEDBK_PATH("CLKC0_EXT")','.FEEDBK_PATH("VCO_PHASE_0")').replace('.fbclk(clk0_out)',".fbclk(1'b0)")
    pll=pll.replace('.FBCLK_DIV(2)','.FBCLK_DIV(20)').replace('.CLKC0_DIV(10)','.CLKC0_DIV(20)').replace('.CLKC0_CPHASE(9)','.CLKC0_CPHASE(19)')
    pll=pll.replace('.CLKC1_DIV(8)','.CLKC1_DIV(20)').replace('.CLKC1_CPHASE(7)','.CLKC1_CPHASE(19)')
    pll=pll.replace('.CLKC2_DIV(8)','.CLKC2_DIV(20)').replace('.CLKC2_CPHASE(3)','.CLKC2_CPHASE(7)')
    pll=pll.replace('wire clk0_buf;','wire clk0_buf;\n  wire clk2_buf;\n  EG_LOGIC_BUFG bufg_shift (.i(clk2_buf),.o(clk2_out));')
    pll=pll.replace('.clkc({open, open, clk2_out, clk1_out, clk0_buf})','.clkc({open, open, clk2_buf, clk1_out, clk0_buf})')
    pll='// Team: internal VCO feedback, NOCOMP, VCO=50*20=1000 MHz.\n// C0/C1 50 MHz at 0 degrees; C2 50 MHz at 144 degrees.\n// 8 ns write launch window and 12 ns SDRAM read-return window, both timed.\n// Derived from vendor sys_pll primitive template; original retained.\n'+pll
    (ROOT/'board/team_mem_pll.v').write_text(pll,encoding='utf8')
    vp=(src/'IP/video_pll.v').read_text(encoding='utf8').replace('module video_pll (','module team_video_pll (')
    vp=vp.replace('.FEEDBK_MODE("NORMAL")','.FEEDBK_MODE("NOCOMP")').replace('.FEEDBK_PATH("CLKC0_EXT")','.FEEDBK_PATH("VCO_PHASE_0")').replace('.fbclk(clk0_out)',".fbclk(1'b0)").replace('.FBCLK_DIV(1)','.FBCLK_DIV(40)')
    vp='// Team: internal VCO feedback, NOCOMP, VCO=50/2*40=1000 MHz.\n// 25 MHz pixel and 125 MHz serializer; no external feedback route.\n'+vp
    (ROOT/'board/team_video_pll.v').write_text(vp,encoding='utf8')
    (ROOT/'board/global_def.v').write_bytes((dest/'global_def.v').read_bytes())
    pin=(a.reference/'src/user_source/constraints_source/pin.adc').read_text(encoding='utf8')
    pin+='\nset_pin_assignment { key_period } { LOCATION = B1; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }\n'
    (ROOT/'board/pin.adc').write_text(pin,encoding='utf8')
    # Keep all related PLL clocks timed. No copied exclusive clock-group shortcut.
    (ROOT/'board/timing.sdc').write_text('''create_clock -name clk -period 20 [get_ports {clk}]
derive_clocks
# Both PLLs use independent internal feedback; only handshake/Gray FIFO/dual-port
# RAM/immutable boot metadata cross these groups. See docs/CDC与时钟审查.md.
# Keep SDRAM launch/capture phases and HDMI pixel/serializer fully timed within groups.
set_clock_groups -asynchronous -group [get_clocks {sys_pll_m0/pll_inst.clkc*}] -group [get_clocks {video_pll_m0/pll_inst.clkc*}]
''',encoding='utf8')
    project=E.Element('Project',Version='3',Minor='2',Path='.')
    for tag,value in [('Project_Created_Time',''),('TD_Version','6.2.168116'),('Name','team_player')]:E.SubElement(project,tag).text=value
    hw=E.SubElement(project,'HardWare')
    for tag,value in [('Family','EG4'),('Device','EG4S20BG256'),('Speed','')]:E.SubElement(hw,tag).text=value
    sf=E.SubElement(project,'Source_Files');vf=E.SubElement(sf,'Verilog')
    sources=[*sorted((ROOT/'rtl').rglob('*.v')),*sorted((ROOT/'extensions/fade/rtl').glob('*.v')),*sorted(dest.glob('*.v')),ROOT/'board/team_mem_pll.v',ROOT/'board/team_video_pll.v',ROOT/'board/team_top.v']
    def add(parent,f,belongs):
        n=E.SubElement(parent,'File',Path=Path(__import__('os').path.relpath(f,ROOT/'board')).as_posix());info=E.SubElement(n,'FileInfo')
        for k,v in [('UsedInSyn','true'),('UsedInP&R','true'),('BelongTo',belongs),('CompileOrder',str(len(parent)))]:E.SubElement(info,'Attr',Name=k,Val=v)
    for f in sources:
        if f.name!='global_def.v':add(vf,f,'design_1')
    for tag,file in [('ADC_FILE','pin.adc'),('SDC_FILE','timing.sdc')]:add(E.SubElement(sf,tag),ROOT/'board'/file,'constraint_1')
    fs=E.SubElement(project,'FileSets')
    E.SubElement(fs,'FileSet',Name='design_1',Type='DesignFiles');E.SubElement(fs,'FileSet',Name='constraint_1',Type='ConstrainFiles')
    top=E.SubElement(project,'TOP_MODULE')
    for tag,value in [('LABEL','team_top'),('MODULE','team_top'),('CREATEINDEX','user')]:E.SubElement(top,tag).text=value
    for tag in ['Property','Device_Settings','Configurations']:E.SubElement(project,tag)
    runs=E.SubElement(project,'Runs')
    for name,typ in [('syn_1','Synthesis'),('phy_1','PhysicalDesign')]:
        attrs=dict(Name=name,Type=typ,ConstraintSet='constraint_1',Description='',Active='true')
        if name=='phy_1':attrs['SynRun']='syn_1'
        run=E.SubElement(runs,'Run',**attrs);E.SubElement(run,'Strategy',Name='Default_Synthesis_Strategy' if name=='syn_1' else 'Default_PhysicalDesign_Strategy');E.SubElement(run,'UserParams')
    E.SubElement(project,'Project_Settings');E.indent(project)
    # TD's project reader expects its own literal Attr names (including raw &)
    # and explicit container end tags. Match a project generated by TD itself.
    xml=E.tostring(project,encoding='unicode',short_empty_elements=False).replace('&amp;','&')
    xml=re.sub(r'<Attr ([^>]+)></Attr>',r'<Attr \1/>',xml)
    (ROOT/'board/team_player.al').write_text('<?xml version="1.0" encoding="UTF-8"?>\n'+xml+'\n',encoding='utf8')
    # Direct flow uses the same commands as local TD-generated scripts.
    text=['set here [file dirname [info script]]','cd $here',
          'import_device eagle_s20.db -package EG4S20BG256']
    rels=[Path(__import__('os').path.relpath(f,ROOT/'board')).as_posix() for f in sources if f.name!='global_def.v']
    text.append('read_verilog -file {'+' '.join(rels)+'} -include_dir {vendor} -top team_top')
    text += ['read_adc pin.adc','read_sdc timing.sdc','optimize_rtl',
             'report_area -file team_player_rtl.area','optimize_gate -packarea team_player_gate.area',
             'legalize_phy_inst','export_db team_player_gate.db','place','route','update_timing -mode final','fix_hold','update_timing -mode final',
             'report_area -io_info -file team_player_phy.area','report_timing_summary -file team_player_pr.timing',
             'check_timing -file team_player_check.timing','bitgen -bit team_player.bit','puts TEAM_BUILD_COMPLETE','exit']
    (ROOT/'board/build.tcl').write_text('\n'.join(text)+'\n',encoding='utf8')
    print('Prepared',ROOT/'board/team_player.al')
if __name__=='__main__':main()
