create_clock -name clk -period 20 [get_ports {clk}]
derive_clocks
# Both PLLs use independent internal feedback; only handshake/Gray FIFO/dual-port
# RAM/immutable boot metadata cross these groups. See docs/CDC与时钟审查.md.
# Keep SDRAM launch/capture phases and HDMI pixel/serializer fully timed within groups.
set_clock_groups -asynchronous -group [get_clocks {sys_pll_m0/pll_inst.clkc*}] -group [get_clocks {video_pll_m0/pll_inst.clkc*}]
