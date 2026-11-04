// Linear RGB888 gain. Fixed two-register latency for pixels AND metadata.
// Gain 0 = black, gain 256 = bit-exact original; larger inputs clamp to 256.
// No stalls: this belongs in the continuous video clock domain before RGB->AXIS.
module team_fade_rgb (
    input wire clk, rst_n,
    input wire [8:0] gain,
    input wire [23:0] in_rgb,
    input wire in_hs, in_vs, in_de,
    input wire [15:0] in_x, in_y,
    output reg [23:0] out_rgb,
    output reg out_hs, out_vs, out_de,
    output reg [15:0] out_x, out_y
);
    wire [8:0] bounded_gain = (gain > 9'd256) ? 9'd256 : gain;
    reg [16:0] product_r, product_g, product_b;
    reg hs_q, vs_q, de_q;
    reg [15:0] x_q, y_q;
    wire [16:0] rounded_r = product_r + 17'd128;
    wire [16:0] rounded_g = product_g + 17'd128;
    wire [16:0] rounded_b = product_b + 17'd128;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product_r<=0; product_g<=0; product_b<=0;
            hs_q<=0; vs_q<=0; de_q<=0; x_q<=0; y_q<=0;
            out_rgb<=0; out_hs<=0; out_vs<=0; out_de<=0; out_x<=0; out_y<=0;
        end else begin
            product_r <= in_rgb[23:16] * bounded_gain;
            product_g <= in_rgb[15:8] * bounded_gain;
            product_b <= in_rgb[7:0] * bounded_gain;
            hs_q<=in_hs; vs_q<=in_vs; de_q<=in_de; x_q<=in_x; y_q<=in_y;
            out_rgb <= de_q ? {rounded_r[15:8],rounded_g[15:8],rounded_b[15:8]} : 24'd0;
            out_hs<=hs_q; out_vs<=vs_q; out_de<=de_q; out_x<=x_q; out_y<=y_q;
        end
    end
endmodule
