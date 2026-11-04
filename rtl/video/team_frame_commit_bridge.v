// Bundled-data toggle mailbox: source frame selection -> video frame boundary.
// Only publish immutable, completely written slots. Hold mailbox until ACK.
// Both domains must share reset assertion; release reset safely in each domain.
module team_frame_commit_bridge (
    input wire src_clk,
    input wire src_rst_n,
    input wire select_valid,
    output wire select_ready,
    input wire [1:0] select_slot,
    output reg select_done,
    input wire video_clk,
    input wire video_rst_n,
    input wire frame_boundary,
    output reg active_valid,
    output reg [1:0] active_slot,
    output reg commit_pulse
);
    reg [1:0] mailbox_slot;
    reg request_toggle;
    reg ack_toggle;
    reg ack_meta, ack_sync, ack_seen;
    reg req_meta, req_sync;
    reg pending;
    reg [1:0] pending_slot;
    assign select_ready = (request_toggle == ack_sync);

    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            mailbox_slot <= 0;
            request_toggle <= 0;
            ack_meta <= 0;
            ack_sync <= 0;
            ack_seen <= 0;
            select_done <= 0;
        end else begin
            ack_meta <= ack_toggle;
            ack_sync <= ack_meta;
            select_done <= (ack_sync != ack_seen);
            ack_seen <= ack_sync;
            if (select_valid && select_ready) begin
                mailbox_slot <= select_slot;
                request_toggle <= ~request_toggle;
            end
        end
    end
    always @(posedge video_clk or negedge video_rst_n) begin
        if (!video_rst_n) begin
            req_meta <= 0;
            req_sync <= 0;
            ack_toggle <= 0;
            pending <= 0;
            pending_slot <= 0;
            active_valid <= 0;
            active_slot <= 0;
            commit_pulse <= 0;
        end else begin
            req_meta <= request_toggle;
            req_sync <= req_meta;
            commit_pulse <= 0;
            if (!pending && (req_sync != ack_toggle)) begin
                // The payload has been stable for the toggle synchronizer delay.
                pending_slot <= mailbox_slot;
                pending <= 1;
            end
            if (pending && frame_boundary) begin
                active_slot <= pending_slot;
                active_valid <= 1;
                commit_pulse <= 1;
                pending <= 0;
                ack_toggle <= req_sync;
            end
        end
    end
endmodule
