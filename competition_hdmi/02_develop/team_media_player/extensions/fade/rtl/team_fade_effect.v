// Integration wrapper. Every control/video signal is in clk (video domain).
// This has internal logical ports, not a standalone board-pin assignment.
module team_fade_effect #(
    parameter integer WATCHDOG_CYCLES = 50400000
)(
    input wire clk, rst_n, frame_tick,
    input wire request_valid,
    output wire request_ready,
    input wire [1:0] request_slot,
    input wire request_slot_valid, effect_enable,
    input wire [8:0] request_step,
    input wire abort_transition,
    output wire switch_valid,
    input wire switch_ready,
    output wire [1:0] switch_slot,
    output wire [31:0] switch_token,
    output wire switch_cancel,
    input wire reply_valid,
    input wire [31:0] reply_token,
    input wire [1:0] reply_slot,
    input wire reply_error,
    input wire recover_valid,
    output wire recover_ready,
    input wire [1:0] recover_slot,
    input wire [23:0] in_rgb,
    input wire in_hs, in_vs, in_de,
    input wire [15:0] in_x, in_y,
    output wire [23:0] out_rgb,
    output wire out_hs, out_vs, out_de,
    output wire [15:0] out_x, out_y,
    output wire [8:0] gain,
    output wire busy, fault, blackout, done, failed,
    output wire [1:0] result_slot,
    output wire [3:0] error_code,
    output wire [2:0] phase
);
    team_fade_ctrl #(.WATCHDOG_CYCLES(WATCHDOG_CYCLES)) controller(
        .clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),
        .request_valid(request_valid),.request_ready(request_ready),.request_slot(request_slot),
        .request_slot_valid(request_slot_valid),.effect_enable(effect_enable),.request_step(request_step),
        .abort_transition(abort_transition),.switch_valid(switch_valid),.switch_ready(switch_ready),
        .switch_slot(switch_slot),.switch_token(switch_token),.switch_cancel(switch_cancel),
        .reply_valid(reply_valid),.reply_token(reply_token),.reply_slot(reply_slot),.reply_error(reply_error),
        .recover_valid(recover_valid),.recover_ready(recover_ready),.recover_slot(recover_slot),
        .gain(gain),.busy(busy),.fault(fault),.blackout(blackout),.done(done),.failed(failed),
        .result_slot(result_slot),.error_code(error_code),.phase(phase));
    team_fade_rgb pixels(
        .clk(clk),.rst_n(rst_n),.gain(gain),.in_rgb(in_rgb),.in_hs(in_hs),.in_vs(in_vs),.in_de(in_de),
        .in_x(in_x),.in_y(in_y),.out_rgb(out_rgb),.out_hs(out_hs),.out_vs(out_vs),.out_de(out_de),
        .out_x(out_x),.out_y(out_y));
endmodule
