//=============================================================================
// team_volume_osd.v
// ---------------------------------------------------------------------------
// 本机音量 OSD：拨码开关 SW1/SW2 -> 16 级数字音量 + 右侧竖条显示。
//
// 为什么不用白板自己的音量键：
//   本板 HDMI 输出口（HDMI B）没有 CEC 连线（手册引脚表只有 HDMIA_CEC），
//   白板音量键作用在白板内部功放，FPGA 收不到事件，也无法读取其音量值。
//   因此"画面音量条"由本机音量驱动：SW1 拨动一次 +1 级，SW2 拨动一次 -1 级，
//   竖条高度/颜色 = 当前本机增益；该增益同时作用到 PCM 输出（见 team_player_core）。
//
// 行为细节：
//   * SW1/SW2 各自两级同步 + 20 ms（50MHz 下 1,000,000 拍）去抖，检测到开关状态变化才计一次；
//   * 音量 0..15，上电默认 10；
//   * 每次调节后竖条保持 VISIBLE_FRM 帧（默认 120 帧 ≈ 2 秒），随后自动隐藏；
//   * 纯组合叠加，只改 rgb，de/hs/vs 原样透传。
//=============================================================================
`timescale 1ns/1ps

module team_volume_osd #(
    parameter integer WIDTH       = 640,
    parameter integer HEIGHT      = 480,
    parameter integer BAR_X0      = 588,
    parameter integer BAR_W       = 24,
    parameter integer BAR_Y0      = 140,
    parameter integer BAR_H       = 200,
    parameter integer VISIBLE_FRM = 120,
    parameter integer DEB_CYC     = 1000000      // 20 ms @50MHz
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_tick,
    input  wire        sw1_i,           // 拨码：每变化一次 音量 +1
    input  wire        sw2_i,           // 拨码：每变化一次 音量 -1
    input  wire        de,
    input  wire [15:0] x,
    input  wire [15:0] y,
    input  wire [23:0] in_rgb,
    input  wire        in_de,
    input  wire        in_hs,
    input  wire        in_vs,
    output wire [23:0] out_rgb,
    output wire        out_de,
    output wire        out_hs,
    output wire        out_vs,
    output reg  [3:0]  level,           // 0..15，供音频增益使用
    output wire        osd_visible
);
    //---------------------------------------------------------------
    // 1. 拨码同步 + 去抖 + 变化检测
    //---------------------------------------------------------------
    reg [1:0] sw1_sync, sw2_sync;
    reg       sw1_stable, sw2_stable;
    reg [19:0] deb_cnt;
    reg       up_pulse, dn_pulse;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sw1_sync  <= 2'b00;
            sw2_sync  <= 2'b00;
            sw1_stable<= 1'b0;
            sw2_stable<= 1'b0;
            deb_cnt   <= 20'd0;
            up_pulse  <= 1'b0;
            dn_pulse  <= 1'b0;
        end else begin
            sw1_sync <= {sw1_sync[0], sw1_i};
            sw2_sync <= {sw2_sync[0], sw2_i};
            up_pulse <= 1'b0;
            dn_pulse <= 1'b0;

            if (deb_cnt != DEB_CYC[19:0]) begin
                deb_cnt <= deb_cnt + 20'd1;
            end else begin
                deb_cnt <= 20'd0;
                if (sw1_sync[1] != sw1_stable) begin
                    sw1_stable <= sw1_sync[1];
                    up_pulse   <= 1'b1;          // 拨动一次 -> +1 级
                end
                if (sw2_sync[1] != sw2_stable) begin
                    sw2_stable <= sw2_sync[1];
                    dn_pulse   <= 1'b1;          // 拨动一次 -> -1 级
                end
            end
        end
    end

    //---------------------------------------------------------------
    // 2. 音量 + OSD 保持计时
    //---------------------------------------------------------------
    reg [7:0] hold_cnt;
    reg       visible;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            level    <= 4'd10;
            hold_cnt <= 8'd0;
            visible  <= 1'b0;
        end else begin
            if (up_pulse) begin
                if (level != 4'd15) level <= level + 4'd1;
                hold_cnt <= VISIBLE_FRM[7:0];
                visible  <= 1'b1;
            end else if (dn_pulse) begin
                if (level != 4'd0) level <= level - 4'd1;
                hold_cnt <= VISIBLE_FRM[7:0];
                visible  <= 1'b1;
            end else if (frame_tick) begin
                if (hold_cnt != 8'd0) hold_cnt <= hold_cnt - 8'd1;
                else if (visible)     visible  <= 1'b0;
            end
        end
    end

    assign osd_visible = visible;

    //---------------------------------------------------------------
    // 3. 竖条几何与画法（屏幕右侧安全区）
    //---------------------------------------------------------------
    wire [15:0] bx0 = BAR_X0;
    wire [15:0] bx1 = BAR_X0 + BAR_W - 1;
    wire [15:0] by0 = BAR_Y0;
    wire [15:0] by1 = BAR_Y0 + BAR_H - 1;

    wire in_box  = (x >= bx0) && (x <= bx1) && (y >= by0) && (y <= by1);
    wire on_edge = in_box && ((x == bx0) || (x == bx1) || (y == by0) || (y == by1));

    // 填充高度 = level/15 * (BAR_H-6)
    wire [15:0] inner_h  = (level * (BAR_H - 6)) / 15;
    wire [15:0] fill_top = by1 - 16'd2 - inner_h;
    wire        on_fill  = in_box && (x > bx0 + 16'd2) && (x < bx1 - 16'd1) &&
                           (y > fill_top) && (y < by1 - 16'd1) && (level != 4'd0);

    wire [23:0] bar_color = (level >= 4'd10) ? 24'h00e000 :
                            (level >= 4'd5)  ? 24'hffff00 : 24'hff8000;
    wire        draw      = visible && de && (on_edge || on_fill);

    assign out_rgb = draw ? (on_edge ? 24'hffffff : bar_color) : in_rgb;
    assign out_de  = in_de;
    assign out_hs  = in_hs;
    assign out_vs  = in_vs;
endmodule
