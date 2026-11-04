// All signals are synchronous to the video clock. The external committer owns
// read-FIFO flushing and frame adoption; its reply MUST mean new pixels ready.
// A token prevents stale replies from completing later transitions.
module team_fade_ctrl #(
    parameter integer WATCHDOG_CYCLES = 50400000
)(
    input wire clk, rst_n,
    input wire frame_tick,
    input wire request_valid,
    output wire request_ready,
    input wire [1:0] request_slot,
    input wire request_slot_valid,
    input wire effect_enable,
    input wire [8:0] request_step,
    input wire abort_transition,
    output wire switch_valid,
    input wire switch_ready,
    output reg [1:0] switch_slot,
    output reg [31:0] switch_token,
    output reg switch_cancel,
    input wire reply_valid,
    input wire [31:0] reply_token,
    input wire [1:0] reply_slot,
    input wire reply_error,
    input wire recover_valid,
    output wire recover_ready,
    input wire [1:0] recover_slot,
    output reg [8:0] gain,
    output wire busy,
    output wire fault,
    output wire blackout,
    output reg done,
    output reg failed,
    output reg [1:0] result_slot,
    output reg [3:0] error_code,
    output reg [2:0] phase
);
    localparam [2:0] IDLE=0, FADE_OUT=1, BLACK_HOLD=2, ISSUE=3,
                     WAIT_REPLY=4, FADE_IN=5, FAULT=6;
    localparam integer WATCHDOG_LAST = (WATCHDOG_CYCLES < 1) ? 0 : WATCHDOG_CYCLES-1;
    reg enabled;
    reg [8:0] step;
    reg confirmed, recovery_seen;
    reg [1:0] recovery_slot_q;
    reg [31:0] watchdog;
    assign request_ready = (phase==IDLE) && !abort_transition;
    assign switch_valid = (phase==ISSUE);
    assign recover_ready = (phase==FAULT) && !recovery_seen;
    assign busy = (phase!=IDLE);
    assign fault = (phase==FAULT);
    assign blackout = (gain==0);
    wire take_request = request_valid && request_ready;
    wire take_switch = switch_valid && switch_ready;
    wire reply_context = (phase==WAIT_REPLY) || take_switch;
    wire matching_reply = reply_valid && reply_context && (reply_token==switch_token);
    wire reply_wrong_slot = matching_reply && (reply_slot!=switch_slot);
    wire reply_bad = matching_reply && reply_error;
    wire reply_good = matching_reply && !reply_error && !reply_wrong_slot;
    wire progress = ((phase==FADE_OUT || phase==BLACK_HOLD || phase==FADE_IN) && frame_tick) ||
                    take_switch || reply_good ||
                    ((phase==WAIT_REPLY) && confirmed && frame_tick);
    wire timed_out = busy && !fault && !progress && (watchdog>=WATCHDOG_LAST);
    wire [9:0] increased = {1'b0,gain}+{1'b0,step};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase<=IDLE; gain<=256; enabled<=1; step<=8;
            confirmed<=0; recovery_seen<=0; recovery_slot_q<=0;
            watchdog<=0; switch_slot<=0; switch_token<=0; switch_cancel<=0;
            done<=0; failed<=0; result_slot<=0; error_code<=0;
        end else begin
            done<=0; failed<=0; switch_cancel<=0;
            if (!busy || fault || progress) watchdog<=0;
            else watchdog<=watchdog+1'b1;
            if (busy && !fault && (abort_transition || reply_bad || reply_wrong_slot || timed_out)) begin
                phase<=FAULT; gain<=0; failed<=1; switch_cancel<=1;
                confirmed<=0; recovery_seen<=0;
                if (abort_transition) error_code<=6;
                else if (reply_bad) error_code<=5;
                else if (reply_wrong_slot) error_code<=4;
                else if (phase==FADE_OUT || phase==BLACK_HOLD || phase==FADE_IN || confirmed)
                    error_code<=2;
                else error_code<=3;
            end else case (phase)
                IDLE: if (take_request) begin
                    switch_slot<=request_slot; result_slot<=request_slot;
                    switch_token<=switch_token+1'b1;
                    enabled<=effect_enable;
                    step<=(request_step==0) ? 9'd8 :
                          ((request_step>256) ? 9'd256 : request_step);
                    confirmed<=0; recovery_seen<=0; error_code<=0; gain<=256;
                    if (!request_slot_valid) begin
                        failed<=1; done<=1; error_code<=1;
                    end else if (effect_enable) phase<=FADE_OUT;
                    else phase<=ISSUE;
                end
                FADE_OUT: if (frame_tick) begin
                    if (gain<=step) begin gain<=0; phase<=BLACK_HOLD; end
                    else gain<=gain-step;
                end
                BLACK_HOLD: if (frame_tick) phase<=ISSUE;
                ISSUE: if (take_switch) begin
                    phase<=WAIT_REPLY;
                    confirmed<=reply_good; // A same-cycle successful reply is legal.
                end
                WAIT_REPLY: begin
                    if (reply_good) confirmed<=1;
                    if (frame_tick && (confirmed || reply_good)) begin
                        confirmed<=0;
                        if (!enabled || step==256) begin
                            gain<=256; phase<=IDLE; done<=1;
                        end else begin gain<=step; phase<=FADE_IN; end
                    end
                end
                FADE_IN: if (frame_tick) begin
                    if (increased>=256) begin gain<=256; phase<=IDLE; done<=1; end
                    else gain<=increased[8:0];
                end
                FAULT: begin
                    if (recover_valid && recover_ready) begin
                        recovery_seen<=1; recovery_slot_q<=recover_slot;
                    end
                    // Supervisor certifies coherent pixels AND drains old jobs.
                    // Do not infer recovery from a late commit acknowledgement.
                    if (frame_tick && (recovery_seen || (recover_valid && recover_ready))) begin
                        result_slot<=recovery_seen ? recovery_slot_q : recover_slot;
                        recovery_seen<=0;
                        if (!enabled || step==256) begin gain<=256; phase<=IDLE; done<=1; end
                        else begin gain<=step; phase<=FADE_IN; end
                    end
                end
                default: begin
                    phase<=FAULT; gain<=0; failed<=1; error_code<=7; switch_cancel<=1;
                end
            endcase
        end
    end
endmodule
