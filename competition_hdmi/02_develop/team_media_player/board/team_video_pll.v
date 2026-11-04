// Team: 25 MHz pixel clock + 125 MHz TMDS serializer clock.
// This file is now a VERBATIM copy of the baseline video_pll.v (lab_ex5) that
// already produced working 640x480 HDMI on this exact board.
//
// 2026-11-03 fix: the previous revision used FEEDBK_MODE("NOCOMP") +
// FEEDBK_PATH("VCO_PHASE_0") + .fbclk(1'b0), which never asserted extlock on
// hardware; team_top gates the whole design on (sys_lock && video_lock), so the
// board stayed in reset (7-seg dark, HDMI dead). Restored the proven
// NORMAL / CLKC0_EXT loop with fbclk = clk0_out.
`timescale 1 ns / 100 fs

module team_video_pll (
  refclk,
  reset,
  extlock,
  clk0_out,
  clk1_out
);

  input refclk;
  input reset;
  output extlock;
  output clk0_out;
  output clk1_out;

  wire clk0_buf;

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
    .GMC_GAIN(2),
    .ICP_CURRENT(9),
    .KVCO(2),
    .LPF_CAPACITOR(1),
    .LPF_RESISTOR(8),
    .REFCLK_DIV(2),
    .FBCLK_DIV(1),
    .CLKC0_ENABLE("ENABLE"),
    .CLKC0_DIV(40),
    .CLKC0_CPHASE(39),
    .CLKC0_FPHASE(0),
    .CLKC1_ENABLE("ENABLE"),
    .CLKC1_DIV(8),
    .CLKC1_CPHASE(7),
    .CLKC1_FPHASE(0)
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
    .clkc({open, open, open, clk1_out, clk0_buf})
  );

endmodule
