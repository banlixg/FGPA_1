// First-day practice only. Same clock domain; no SD/SDRAM/HDMI connection.
module team_frame_latch (
    input        clk,
    input        rst_n,
    input        frame_accept,
    input  [1:0] frame_id_in,
    output reg [1:0] frame_id_out,
    output reg      frame_valid,
    output reg      accepted_pulse
);
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        frame_id_out  <= 2'd0;
        frame_valid   <= 1'b0;
        accepted_pulse <= 1'b0;
    end else begin
        accepted_pulse <= frame_accept;
        if (frame_accept) begin
            frame_id_out <= frame_id_in;
            frame_valid  <= 1'b1;
        end
    end
end
endmodule
