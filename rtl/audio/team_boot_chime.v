//=============================================================================
// team_boot_chime.v
// ---------------------------------------------------------------------------
// 自主合成的 10 秒开机音效（与参考例程的内部 I2S 测试音链无关：这里是自建 DDS，
// 两个发声单元 + 1/4 周期正弦表 + 线性包络，不读任何音频文件）。
//
//  0.00~0.90s  上升扫频 C4->C6（通电感），同时 C3 低音铺底
//  0.90~1.50s  琶音 C5-E5-G5-C6（每音 0.15s）
//  1.50~3.00s  C6 延音自然衰减 + C3 一起衰减
//  3.00~8.60s  静音（画面此时在转圈 + 走进度条）
//  8.60~9.40s  收尾和弦 C6+C3（配合画面 9.0s 闪白）
//  9.40~10.0s  静音，之后再给一拍 0，避免残留直流
//
// 接口：每个 i_tick（48 kHz）给出一个 i_tick 周期的采样；o_done 置起后
// 所有相位/包络寄存器停止翻转（真实省动态功耗），o_sample 恒为 0。
//=============================================================================
`timescale 1ns/1ps

module team_boot_chime #(
    parameter [31:0]  TOTAL_SMP = 32'd480000,   // 10 秒 @48kHz
    parameter integer VOL_SH    = 10            // 输出增益（左移位数，10 ≈ -6 dBFS）
)(
    input  wire        clk_mclk,
    input  wire        rst_n,
    input  wire        i_tick,          // 48 kHz 采样节拍
    output reg  [23:0] o_sample,        // 24bit 有符号 PCM
    output reg         o_done
);
    //=========================================================================
    // 音高表：相位增量 = round(f * 2^32 / 48000)
    //=========================================================================
    localparam [31:0] INC_C3 = 32'd11704931;   //  130.81 Hz
    localparam [31:0] INC_C4 = 32'd23409862;   //  261.63 Hz
    localparam [31:0] INC_C5 = 32'd46819716;   //  523.25 Hz
    localparam [31:0] INC_E5 = 32'd58989148;   //  659.26 Hz
    localparam [31:0] INC_G5 = 32'd70150318;   //  783.99 Hz
    localparam [31:0] INC_C6 = 32'd93639441;   // 1046.50 Hz

    localparam [31:0] SWEEP_STEP = 32'd1626;   // 0.9s 内 C4 -> C6

    // 区域边界（采样数）
    localparam [19:0] T_R1 = 20'd43200;   // 0.90s
    localparam [19:0] T_R2 = 20'd50400;   // 1.05s
    localparam [19:0] T_R3 = 20'd57600;   // 1.20s
    localparam [19:0] T_R4 = 20'd64800;   // 1.35s
    localparam [19:0] T_R5 = 20'd72000;   // 1.50s
    localparam [19:0] T_R6 = 20'd144000;  // 3.00s
    localparam [19:0] T_R7 = 20'd412800;  // 8.60s
    localparam [19:0] T_R8 = 20'd451200;  // 9.40s

    //=========================================================================
    // 时间轴
    //=========================================================================
    reg [19:0] s_cnt;
    wire       run = i_tick && !o_done;

    always @(posedge clk_mclk or negedge rst_n) begin
        if (!rst_n)
            s_cnt <= 20'd0;
        else if (run && (s_cnt < TOTAL_SMP[19:0] - 20'd1))
            s_cnt <= s_cnt + 20'd1;
    end

    always @(posedge clk_mclk or negedge rst_n) begin
        if (!rst_n)
            o_done <= 1'b0;
        else if (i_tick && !o_done && (s_cnt >= TOTAL_SMP[19:0] - 20'd1))
            o_done <= 1'b1;
    end

    wire [3:0] zone = (s_cnt < T_R1) ? 4'd0 :
                      (s_cnt < T_R2) ? 4'd1 :
                      (s_cnt < T_R3) ? 4'd2 :
                      (s_cnt < T_R4) ? 4'd3 :
                      (s_cnt < T_R5) ? 4'd4 :
                      (s_cnt < T_R6) ? 4'd5 :
                      (s_cnt < T_R7) ? 4'd6 :
                      (s_cnt < T_R8) ? 4'd7 : 4'd8;

    reg [3:0] zone_d;
    always @(posedge clk_mclk or negedge rst_n) begin
        if (!rst_n)
            zone_d <= 4'd0;
        else if (run)
            zone_d <= zone;
    end
    wire zone_new = (zone != zone_d);

    //=========================================================================
    // 正弦表：只存 1/4 周期 65 个点，靠象限对称还原
    //=========================================================================
    function signed [11:0] sinq;          // round(2047*sin(k*pi/128))
        input [6:0] k1;
        begin
            case (k1)
                7'd0:  sinq = 12'sd0;     7'd1:  sinq = 12'sd50;    7'd2:  sinq = 12'sd100;
                7'd3:  sinq = 12'sd151;   7'd4:  sinq = 12'sd201;   7'd5:  sinq = 12'sd251;
                7'd6:  sinq = 12'sd300;   7'd7:  sinq = 12'sd350;   7'd8:  sinq = 12'sd399;
                7'd9:  sinq = 12'sd449;   7'd10: sinq = 12'sd497;   7'd11: sinq = 12'sd546;
                7'd12: sinq = 12'sd594;   7'd13: sinq = 12'sd642;   7'd14: sinq = 12'sd690;
                7'd15: sinq = 12'sd737;   7'd16: sinq = 12'sd783;   7'd17: sinq = 12'sd830;
                7'd18: sinq = 12'sd875;   7'd19: sinq = 12'sd920;   7'd20: sinq = 12'sd965;
                7'd21: sinq = 12'sd1009;  7'd22: sinq = 12'sd1052;  7'd23: sinq = 12'sd1095;
                7'd24: sinq = 12'sd1137;  7'd25: sinq = 12'sd1179;  7'd26: sinq = 12'sd1219;
                7'd27: sinq = 12'sd1259;  7'd28: sinq = 12'sd1299;  7'd29: sinq = 12'sd1337;
                7'd30: sinq = 12'sd1375;  7'd31: sinq = 12'sd1411;  7'd32: sinq = 12'sd1447;
                7'd33: sinq = 12'sd1483;  7'd34: sinq = 12'sd1517;  7'd35: sinq = 12'sd1550;
                7'd36: sinq = 12'sd1582;  7'd37: sinq = 12'sd1614;  7'd38: sinq = 12'sd1644;
                7'd39: sinq = 12'sd1674;  7'd40: sinq = 12'sd1702;  7'd41: sinq = 12'sd1729;
                7'd42: sinq = 12'sd1756;  7'd43: sinq = 12'sd1781;  7'd44: sinq = 12'sd1805;
                7'd45: sinq = 12'sd1828;  7'd46: sinq = 12'sd1850;  7'd47: sinq = 12'sd1871;
                7'd48: sinq = 12'sd1891;  7'd49: sinq = 12'sd1910;  7'd50: sinq = 12'sd1927;
                7'd51: sinq = 12'sd1944;  7'd52: sinq = 12'sd1959;  7'd53: sinq = 12'sd1973;
                7'd54: sinq = 12'sd1986;  7'd55: sinq = 12'sd1997;  7'd56: sinq = 12'sd2008;
                7'd57: sinq = 12'sd2017;  7'd58: sinq = 12'sd2025;  7'd59: sinq = 12'sd2032;
                7'd60: sinq = 12'sd2037;  7'd61: sinq = 12'sd2041;  7'd62: sinq = 12'sd2045;
                7'd63: sinq = 12'sd2046;  7'd64: sinq = 12'sd2047;
                default: sinq = 12'sd0;
            endcase
        end
    endfunction

    function signed [11:0] sin_full;      // 8bit 相位（0..255 = 0..2pi）
        input [7:0] a;
        reg   [6:0] idx;
        begin
            idx = {1'b0, a[5:0]};
            case (a[7:6])
                2'b00:   sin_full =  sinq(idx);
                2'b01:   sin_full =  sinq(7'd64 - idx);
                2'b10:   sin_full = -sinq(idx);
                default: sin_full = -sinq(7'd64 - idx);
            endcase
        end
    endfunction

    //=========================================================================
    // 音序表
    //=========================================================================
    function [31:0] lead_inc;
        input [3:0] z;
        begin
            case (z)
                4'd0:    lead_inc = INC_C4;
                4'd1:    lead_inc = INC_C5;
                4'd2:    lead_inc = INC_E5;
                4'd3:    lead_inc = INC_G5;
                4'd4:    lead_inc = INC_C6;
                4'd5:    lead_inc = INC_C6;
                4'd7:    lead_inc = INC_C6;
                default: lead_inc = 32'd0;
            endcase
        end
    endfunction

    function [31:0] bass_inc;
        input [3:0] z;
        begin
            case (z)
                4'd0:    bass_inc = INC_C3;
                4'd1:    bass_inc = INC_C3;
                4'd2:    bass_inc = INC_C3;
                4'd3:    bass_inc = INC_C3;
                4'd4:    bass_inc = INC_C3;
                4'd5:    bass_inc = INC_C3;
                4'd7:    bass_inc = INC_C3;
                default: bass_inc = 32'd0;
            endcase
        end
    endfunction

    function [9:0] lead_dec;
        input [3:0] z;
        begin
            case (z)
                4'd0:    lead_dec = 10'd200;
                4'd1:    lead_dec = 10'd40;
                4'd2:    lead_dec = 10'd40;
                4'd3:    lead_dec = 10'd40;
                4'd4:    lead_dec = 10'd40;
                4'd5:    lead_dec = 10'd220;
                4'd7:    lead_dec = 10'd110;
                default: lead_dec = 10'd0;
            endcase
        end
    endfunction

    function [9:0] bass_dec;
        input [3:0] z;
        begin
            case (z)
                4'd7:    bass_dec = 10'd110;
                default: bass_dec = 10'd400;
            endcase
        end
    endfunction

    //=========================================================================
    // 两个发声单元（相位累加 + 正弦查表 + 线性包络）
    //=========================================================================
    reg [31:0] ph1, inc1;
    reg [7:0]  env1;
    reg [15:0] envc1;
    reg [31:0] ph2, inc2;
    reg [7:0]  env2;
    reg [15:0] envc2;

    wire [9:0] d1    = lead_dec(zone);
    wire [9:0] d2    = bass_dec(zone);
    wire       znew1 = zone_new && (lead_inc(zone) != 32'd0);
    wire       znew2 = zone_new && (bass_inc(zone) != 32'd0);

    always @(posedge clk_mclk or negedge rst_n) begin
        if (!rst_n) begin
            ph1   <= 32'd0;
            inc1  <= INC_C4;
            env1  <= 8'd255;
            envc1 <= 16'd0;
            ph2   <= 32'd0;
            inc2  <= INC_C3;
            env2  <= 8'd255;
            envc2 <= 16'd0;
        end
        else if (run) begin
            // ---- 主旋律 ----
            if (zone == 4'd0) begin
                if (inc1 < INC_C6)
                    inc1 <= inc1 + SWEEP_STEP;
            end
            else begin
                inc1 <= lead_inc(zone);
            end
            ph1 <= ph1 + inc1;

            if (znew1) begin
                env1  <= 8'd255;
                envc1 <= 16'd0;
            end
            else if ((d1 != 10'd0) && (env1 != 8'd0)) begin
                if (envc1 >= {6'd0, d1} - 16'd1) begin
                    envc1 <= 16'd0;
                    env1  <= env1 - 8'd1;
                end
                else begin
                    envc1 <= envc1 + 16'd1;
                end
            end

            // ---- 低音 ----
            inc2 <= bass_inc(zone);
            ph2  <= ph2 + inc2;

            if (znew2) begin
                env2  <= 8'd255;
                envc2 <= 16'd0;
            end
            else if ((d2 != 10'd0) && (env2 != 8'd0)) begin
                if (envc2 >= {6'd0, d2} - 16'd1) begin
                    envc2 <= 16'd0;
                    env2  <= env2 - 8'd1;
                end
                else begin
                    envc2 <= envc2 + 16'd1;
                end
            end
        end
    end

    //=========================================================================
    // 混音：两路相加，低音减半，左移成 24bit PCM
    //=========================================================================
    wire signed [11:0] sv1 = sin_full(ph1[31:24]);
    wire signed [11:0] sv2 = sin_full(ph2[31:24]);

    wire signed [20:0] p1 = sv1 * $signed({1'b0, env1});
    wire signed [20:0] p2 = sv2 * $signed({1'b0, env2});
    wire signed [19:0] s1 = p1 >>> 8;
    wire signed [19:0] s2 = p2 >>> 8;

    wire signed [20:0] mix = {{1{s1[19]}}, s1} + {{1{s2[19]}}, (s2 >>> 1)};
    wire signed [13:0] s14 = mix[13:0];
    wire signed [23:0] s24 = {{10{s14[13]}}, s14};

    always @(posedge clk_mclk or negedge rst_n) begin
        if (!rst_n)
            o_sample <= 24'd0;
        else if (i_tick)
            o_sample <= o_done ? 24'd0 : (s24 <<< VOL_SH);
    end
endmodule
