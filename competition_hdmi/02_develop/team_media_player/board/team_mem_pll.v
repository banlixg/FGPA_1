// Team: 50 MHz clock + 50 MHz phase-shifted (for SIP SDRAM). Feedback structure
// copied from the BASELINE sys_pll.v that already produced working SDRAM/HDMI on
// this exact board (FEEDBK_MODE NORMAL / FEEDBK_PATH CLKC0_EXT / fbclk=clk0_out).
//
// 2026-11-03 fix: the previous revision used FEEDBK_MODE("NOCOMP") +
// FEEDBK_PATH("VCO_PHASE_0") with .fbclk(1'b0). That combination never asserted
// extlock on hardware, and team_top holds the whole design in reset while
// (sys_lock && video_lock) is false -> all 7-seg dark, no HDMI. Restored to the
// proven NORMAL/CLKC0_EXT feedback loop.
//
// VCO = 1000 MHz: FIN 50 / REFCLK_DIV 1 x CLKC0_DIV 20 = 1000, out = 50 MHz.
// C2 phase = (CLKC2_CPHASE+1) / CLKC2_DIV x 360 = 10/20 x 360 = 180 deg.
// 2026-11-03: 180 deg 是基线(125MHz@180)与本次独立自检实测通过的相位；144 deg 未通过。
`timescale 1 ns / 100 fs

module team_mem_pll (
  refclk,
  reset,
  extlock,
  clk0_out,
  clk1_out,
  clk2_out
);

  input refclk;
  input reset;
  output extlock;
  output clk0_out;
  output clk1_out;
  output clk2_out;

  wire clk0_buf;
  wire clk2_buf;
  EG_LOGIC_BUFG bufg_shift (.i(clk2_buf), .o(clk2_out));

  EG_LOGIC_BUFG bufg_feedback (
    .i(clk0_buf),
    .o(clk0_out)
  );

  EG_PHY_PLL #(
    .DPHASE_SOURCE("DISABLE"),
    .DYNCFG("DISABLE"),
    .FIN("50.000000"),
    .FEEDBK_MODE("NORMAL"),
    .FEEDBK_PATH("CLKC0_EXT"),
    .STDBY_ENABLE("DISABLE"),
    .PLLRST_ENA("ENABLE"),
    .SYNC_ENABLE("DISABLE"),
    .GMC_GAIN(4),
    .ICP_CURRENT(29),
    .KVCO(4),
    .LPF_CAPACITOR(1),
    .LPF_RESISTOR(2),
    .REFCLK_DIV(1),
    .FBCLK_DIV(1),
    .CLKC0_ENABLE("ENABLE"),
    .CLKC0_DIV(20),
    .CLKC0_CPHASE(19),
    .CLKC0_FPHASE(0),
    .CLKC1_ENABLE("ENABLE"),
    .CLKC1_DIV(20),
    .CLKC1_CPHASE(19),
    .CLKC1_FPHASE(0),
    .CLKC2_ENABLE("ENABLE"),
    .CLKC2_DIV(20),
    .CLKC2_CPHASE(9),
    .CLKC2_FPHASE(0)
  ) pll_inst (
    .refclk(refclk),
    .reset(reset),
    .stdby(1'b0),
    .extlock(extlock),
    .load_reg(1'b0),
    .psclk(1'b0),
    .psdown(1'b0),
    .psstep(1'b0),
    .psclksel(3'b000),
    .psdone(open),
    .dclk(1'b0),
    .dcs(1'b0),
    .dwe(1'b0),
    .di(8'b00000000),
    .daddr(6'b000000),
    .do({open, open, open, open, open, open, open, open}),
    .fbclk(clk0_out),
    .clkc({open, open, clk2_buf, clk1_out, clk0_buf})
  );

endmodule
