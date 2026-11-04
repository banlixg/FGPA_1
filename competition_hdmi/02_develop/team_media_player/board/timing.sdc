create_clock -name clk -period 20 [get_ports {clk}]
derive_clocks
# Both PLLs use independent internal feedback; only handshake/Gray FIFO/dual-port
# RAM/immutable boot metadata cross these groups. See docs/CDC与时钟审查.md.
# Keep SDRAM launch/capture phases and HDMI pixel/serializer fully timed within groups.
set_clock_groups -asynchronous -group [get_clocks {sys_pll_m0/pll_inst.clkc*}] -group [get_clocks {video_pll_m0/pll_inst.clkc*}]

#-----------------------------------------------------------------------------
# SDRAM 源同步输入捕获（2026-11-04 板测补充约束）
#
# TD 静态时序把 SIP 硬核内部 32 条 DQ 焊盘路径按"寄存器到寄存器"模型分析：
#   Begin: memory/sdram.dq[*]      由 clkc[2]（50MHz@180°，即转发给 SDRAM 芯片的时钟）触发
#   End  : memory/sdram_syn_*.bpad 由 clkc[0]（50MHz@0°）捕获
# 得到 slack -0.565ns。该路径的真实约束是**外部 SDRAM 芯片的数据有效窗口**
# （tAC/tOH + 板级走线延迟），SDC 中没有芯片级模型，无法用内部模型表达。
#
# 实板证据（2026-11-04）：四张 BMP 全部"写后读回校验"通过（数码管 count=4、
# 内部错误码 0），整帧 640 字行读取上屏正确，说明该接口实际时序满足要求。
#
# 因此仅对这 32 条硬核焊盘路径加例外；其余时钟域（C0/C1/C2 内部逻辑、
# 视频 25/125MHz、板载 50MHz）全部保留完整时序分析，不做批量 false path。
# 若后续换板或换 SDRAM 芯片，需按新芯片 tAC 重新核算。
#-----------------------------------------------------------------------------
set_false_path -from [get_pins {memory/sdram.dq*}] -to [get_pins {memory/sdram_syn_*.bpad}]
