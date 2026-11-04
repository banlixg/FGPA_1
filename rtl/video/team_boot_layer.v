//=============================================================================
// team_boot_layer.v
// ---------------------------------------------------------------------------
// 自主播放器的“开机/加载”显示层：开机动画 -> “识别图片中”加载画面 -> 图片透传。
//
// 三层优先级（同一像素时钟域内组合选择，输出比输入晚 1 拍）：
//   PH_BOOT  : 10 秒开机动画（呼吸光点 -> 24 点圆环逐个点亮 -> 彗尾旋转 + 进度条
//              -> 闪白 -> 转黑）
//   PH_LOAD  : 中央“识别图片中”5 个 64x64 汉字 + 下方 8 点转圈 + 淡入
//   PH_IMG   : 直接透传帧区读调度器送来的 RGB888（i_img_valid=1）
//
// 相对第一版（boot_video.v）的四类优化：
//   1) 启动：动画只靠自己的行场计数开始，不依赖 SD/FAT/EDID；图片一旦被 commit
//      bridge 采纳就立刻切走（FAST_SWITCH），不硬等 10 秒；另有 i_skip_boot 可瞬跳。
//   2) 资源：圆环 24 点利用“四重镜像对称”压缩成 7 个 |dx|,|dy| 唯一测试
//      （转圈 8 点压缩成 3 个）；汉字改成 64x64 后“第几个字/第几列”变成位切片，
//      整条比较器+加法器去掉；字模 ROM 只在取行时使能。
//   3) 功耗：圆环亮度向量/点亮掩码/闪白计数器只在 PH_BOOT 推进，转圈亮度向量只在
//      PH_LOAD 推进，字模 ROM 的 ce 只在每行前 5 拍有效。
//   4) 鲁棒性：视频看门狗——用音频域 48 kHz 心跳（独立时基）做参考，0.5 秒没有
//      frame_start 就强制进 PH_LOAD 并置 o_wdog，避免“系统活着但永远黑屏”。
//=============================================================================
`timescale 1ns/1ps

module team_boot_layer #(
    parameter integer H_ACTIVE    = 640,
    parameter integer V_ACTIVE    = 480,
    parameter integer BOOT_FRM    = 600,      // 60Hz 下 600 帧 = 10 秒
    parameter integer FRM_ROT     = 4,        // 圆环每 4 帧转一格
    parameter integer CELL        = 64,       // 汉字点阵边长，必须 2 的幂
    parameter integer FAST_SWITCH = 1,        // 1 = 图片一到就切走，不等动画放完
    parameter integer WDOG_TICKS  = 24000     // 48kHz 心跳计数 => 0.5 秒
)(
    input  wire        clk,
    input  wire        rst_n,
    // 来自 team_video_timing（同域）
    input  wire        de,
    input  wire        hs,
    input  wire        vs,
    input  wire [11:0] x,
    input  wire [11:0] y,
    input  wire        frame_start,
    // 帧区读调度器送来的图像像素
    input  wire [23:0] i_img_rgb,
    input  wire        i_img_valid,
    // commit bridge 的视频侧结果
    input  wire        i_active_valid,
    input  wire [1:0]  i_active_slot,
    input  wire        i_commit_pulse,
    // 控制
    input  wire        i_loading_req,   // 1 = 上层要求显示“识别图片中”
    input  wire        i_skip_boot,     // 按键/开关：立即跳过开机动画
    input  wire        i_boot_en,       // 0 = 不播动画（直接进加载画面）
    input  wire        i_audio_tick,    // 音频域 48kHz 心跳，仅用于看门狗
    // 输出
    output reg  [23:0] o_rgb,
    output reg         o_de,
    output reg         o_hs,
    output reg         o_vs,
    output reg  [1:0]  o_phase,         // 0=boot 1=loading 2=image
    output reg         o_boot_done,
    output reg  [9:0]  o_frm,
    output reg         o_wdog,
    output reg  [1:0]  o_active_slot
);

    //=========================================================================
    // 版面常量（逻辑坐标 = 屏幕坐标，640x480 画布）
    //=========================================================================
    localparam integer CX      = H_ACTIVE / 2;              // 320
    localparam integer CY      = V_ACTIVE / 2;              // 240
    localparam [4:0]   DOT_R   = 5'd5;                      // 圆环小点半径
    localparam integer TXT_N   = 5;
    localparam integer TXT_W   = TXT_N * CELL;              // 320
    localparam integer TXT_X0  = CX - TXT_W / 2;            // 160
    localparam integer TXT_Y0  = 150;
    localparam integer SPIN_CY = 280;
    localparam [4:0]   SPIN_DR = 5'd6;
    localparam integer BAR_HW  = 220;
    localparam integer BAR_Y   = 360;
    localparam integer BAR_H   = 8;
    localparam integer BAR_X0  = CX - BAR_HW;               // 100

    // 64->6, 32->5, 128->7（避免依赖 $clog2，TD 老版本也能过）
    localparam integer CELL_SH = (CELL == 128) ? 7 :
                                 (CELL == 64)  ? 6 :
                                 (CELL == 32)  ? 5 : 6;

    localparam [12:0] CXV      = CX;
    localparam [12:0] CYV      = CY;
    localparam [12:0] SPIN_CYV = SPIN_CY;
    localparam [9:0]  TXT_X0_10 = TXT_X0;
    localparam [5:0]  CELL_LAST = CELL - 1;

    // 时间轴关键帧（10 位足够 1023 帧）
    localparam [9:0] F_VIS0   = 10'd18;
    localparam [9:0] F_ROT0   = 10'd112;
    localparam [9:0] F_BAR0   = 10'd60;
    localparam [9:0] F_FLASH  = 10'd520;
    localparam [9:0] F_FLASH2 = 10'd544;
    localparam [9:0] F_BLACK  = 10'd584;
    localparam [9:0] BF_MAX   = BOOT_FRM;                   // 参数取低 10 位
    localparam [3:0] ROT_P    = FRM_ROT;
    localparam [15:0] WDOG_P  = WDOG_TICKS;

    // 相位编码
    localparam [1:0] PH_BOOT = 2'd0;
    localparam [1:0] PH_LOAD = 2'd1;
    localparam [1:0] PH_IMG  = 2'd2;

    //=========================================================================
    // 1. 帧计数 + 视频看门狗（音频域心跳做独立时基）
    //=========================================================================
    reg  [9:0] frm;
    wire       boot_phase = (o_phase == PH_BOOT);
    wire       load_phase = (o_phase == PH_LOAD);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            frm <= 10'd0;
        else if (frame_start && (frm != 10'h3FF))
            frm <= frm + 10'd1;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            o_frm <= 10'd0;
        else
            o_frm <= frm;
    end

    reg at_meta, at_sync, at_seen;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            at_meta <= 1'b0;
            at_sync <= 1'b0;
            at_seen <= 1'b0;
        end
        else begin
            at_meta <= i_audio_tick;
            at_sync <= at_meta;
            at_seen <= at_sync;
        end
    end
    wire at_rise = at_sync & ~at_seen;

    reg [15:0] wd_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            wd_cnt <= 16'd0;
        else if (frame_start)
            wd_cnt <= 16'd0;
        else if (at_rise && (wd_cnt != 16'hFFFF))
            wd_cnt <= wd_cnt + 16'd1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            o_wdog <= 1'b0;
        else if (frame_start)
            o_wdog <= 1'b0;
        else if (at_rise && (wd_cnt >= WDOG_P))
            o_wdog <= 1'b1;
    end

    //=========================================================================
    // 2. 相位状态机（早切 / 跳过 / 看门狗兜底）
    //=========================================================================
    wire img_commit = i_commit_pulse & i_active_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            o_phase <= i_boot_en ? PH_BOOT : PH_LOAD;
        else begin
            case (o_phase)
                PH_BOOT: begin
                    if ((FAST_SWITCH != 0) && img_commit)
                        o_phase <= PH_IMG;                   // 图片已就绪，不硬等
                    else if (i_skip_boot)
                        o_phase <= i_active_valid ? PH_IMG : PH_LOAD;
                    else if (o_wdog || (frm >= BF_MAX))
                        o_phase <= PH_LOAD;
                end
                PH_LOAD: begin
                    if (img_commit)
                        o_phase <= PH_IMG;
                end
                default: begin                                   // PH_IMG
                    if (i_loading_req)
                        o_phase <= PH_LOAD;
                end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_boot_done   <= 1'b0;
            o_active_slot <= 2'd0;
        end
        else begin
            o_boot_done <= (o_phase != PH_BOOT);
            if (img_commit)
                o_active_slot <= i_active_slot;
        end
    end

    //=========================================================================
    // 3. 小圆点画刷 + 镜像对称压缩
    //=========================================================================
    function [12:0] absdiff;
        input [12:0] a, b;
        begin
            absdiff = (a > b) ? (a - b) : (b - a);
        end
    endfunction

    // 八边形近似圆点：|dx|<=r, |dy|<=r, |dx|+|dy| <= r + r/2
    function dot_hit;
        input [12:0] ax, ay, dx, dy;
        input [4:0]  r;
        reg   [12:0] ddx, ddy;
        begin
            ddx     = (ax > dx) ? (ax - dx) : (dx - ax);
            ddy     = (ay > dy) ? (ay - dy) : (dy - ay);
            dot_hit = (ddx <= {8'd0, r}) && (ddy <= {8'd0, r}) &&
                      ((ddx + ddy) <= ({8'd0, r} + {8'd0, r[4:1]}));
        end
    endfunction

    wire [12:0] ux = {1'b0, x};
    wire [12:0] uy = {1'b0, y};

    // 相对圆心的绝对偏移：一次算好，所有镜像点复用
    wire [12:0] rax = absdiff(ux, CXV);                    // |x-320|
    wire [12:0] ray = absdiff(uy, CYV);                    // |y-240|
    wire [12:0] say = absdiff(uy, SPIN_CYV);               // |y-280|
    wire        sx_neg  = (ux < CXV);
    wire        sy_neg  = (uy < CYV);
    wire        spy_neg = (uy < SPIN_CYV);

    // ---- 圆环 24 点 -> 7 个唯一 |offset| ----
    wire ring_h0 = dot_hit(rax, ray, 13'd0,  13'd88, DOT_R);
    wire ring_h1 = dot_hit(rax, ray, 13'd23, 13'd85, DOT_R);
    wire ring_h2 = dot_hit(rax, ray, 13'd44, 13'd76, DOT_R);
    wire ring_h3 = dot_hit(rax, ray, 13'd62, 13'd62, DOT_R);
    wire ring_h4 = dot_hit(rax, ray, 13'd76, 13'd44, DOT_R);
    wire ring_h5 = dot_hit(rax, ray, 13'd85, 13'd23, DOT_R);
    wire ring_h6 = dot_hit(rax, ray, 13'd88, 13'd0,  DOT_R);

    wire q_up =  sy_neg;
    wire q_dn = ~sy_neg;
    wire q_lf =  sx_neg;
    wire q_rt = ~sx_neg;
    wire q_ur = q_rt & q_up;
    wire q_dr = q_rt & q_dn;
    wire q_ul = q_lf & q_up;
    wire q_dl = q_lf & q_dn;

    wire [23:0] ring_geo;            // 几何命中（未含点亮掩码与亮度）
    assign ring_geo[ 0] = ring_h0 & q_up;    // (   0, -88)
    assign ring_geo[ 1] = ring_h1 & q_ur;    // (  23, -85)
    assign ring_geo[ 2] = ring_h2 & q_ur;
    assign ring_geo[ 3] = ring_h3 & q_ur;
    assign ring_geo[ 4] = ring_h4 & q_ur;
    assign ring_geo[ 5] = ring_h5 & q_ur;
    assign ring_geo[ 6] = ring_h6 & q_rt;    // (  88,   0)
    assign ring_geo[ 7] = ring_h5 & q_dr;
    assign ring_geo[ 8] = ring_h4 & q_dr;
    assign ring_geo[ 9] = ring_h3 & q_dr;
    assign ring_geo[10] = ring_h2 & q_dr;
    assign ring_geo[11] = ring_h1 & q_dr;
    assign ring_geo[12] = ring_h0 & q_dn;    // (   0,  88)
    assign ring_geo[13] = ring_h1 & q_dl;
    assign ring_geo[14] = ring_h2 & q_dl;
    assign ring_geo[15] = ring_h3 & q_dl;
    assign ring_geo[16] = ring_h4 & q_dl;
    assign ring_geo[17] = ring_h5 & q_dl;
    assign ring_geo[18] = ring_h6 & q_lf;    // ( -88,   0)
    assign ring_geo[19] = ring_h5 & q_ul;
    assign ring_geo[20] = ring_h4 & q_ul;
    assign ring_geo[21] = ring_h3 & q_ul;
    assign ring_geo[22] = ring_h2 & q_ul;
    assign ring_geo[23] = ring_h1 & q_ul;

    function [7:0] ring_trail;
        input [4:0] n;
        begin
            case (n)
                5'd0:    ring_trail = 8'd255;
                5'd1:    ring_trail = 8'd213;
                5'd2:    ring_trail = 8'd171;
                5'd3:    ring_trail = 8'd129;
                5'd4:    ring_trail = 8'd87;
                5'd5:    ring_trail = 8'd45;
                default: ring_trail = 8'd0;
            endcase
        end
    endfunction

    reg  [7:0]  ring_bri [0:23];
    reg  [23:0] vis_mask;
    reg  [3:0]  rot_div;
    wire        rot_tick = frame_start && boot_phase && (rot_div == ROT_P - 4'd1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rot_div <= 4'd0;
        else if (frame_start && boot_phase)
            rot_div <= (rot_div == ROT_P - 4'd1) ? 4'd0 : (rot_div + 4'd1);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            vis_mask <= 24'd0;
        else if (rot_tick && (frm >= F_VIS0))
            vis_mask <= {vis_mask[22:0], 1'b1};
    end

    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < 24; k = k + 1)
                ring_bri[k] <= 8'd150;
        end
        else if (!boot_phase) begin
            for (k = 0; k < 24; k = k + 1)
                ring_bri[k] <= 8'd150;              // 不在开机段：冻结
        end
        else if (frame_start && (frm == F_ROT0)) begin
            for (k = 0; k < 24; k = k + 1)
                ring_bri[k] <= ring_trail(k[4:0]);
        end
        else if (rot_tick && (frm > F_ROT0)) begin
            for (k = 0; k < 24; k = k + 1)
                ring_bri[k] <= ring_bri[(k + 1) % 24];
        end
    end

    reg  [7:0] ring_col;
    reg        ring_on;
    integer    i;
    always @* begin
        ring_col = 8'd0;
        ring_on  = 1'b0;
        for (i = 0; i < 24; i = i + 1) begin
            // 亮度为 0 的点不能画：否则会在渐变背景上留下纯黑圆斑
            if (ring_geo[i] && vis_mask[i] && (ring_bri[i] != 8'd0)) begin
                ring_on  = 1'b1;
                ring_col = ring_bri[i];
            end
        end
    end
    wire [23:0] ring_rgb = {2'b00, ring_col[7:2], ring_col, ring_col};

    // ---- 中心呼吸光点（开机前 1.87 秒）----
    wire [5:0]  ph6   = frm[5:0];
    wire [5:0]  tri6  = ph6[5] ? (6'd63 - ph6) : ph6;
    wire [7:0]  c_bri = (boot_phase && (frm < F_ROT0)) ? {tri6[4:0], 3'b000} : 8'd0;
    wire        c_on  = (c_bri != 8'd0) && dot_hit(rax, ray, 13'd0, 13'd0, 5'd4);
    wire [23:0] c_rgb = {c_bri, c_bri, c_bri};

    // ---- 进度条：1 帧 1 像素，440 帧走满 ----
    wire [11:0] fill = (frm <= F_BAR0)              ? 12'd0 :
                       (frm >= F_BAR0 + 10'd440)    ? 12'd440 :
                                                      ({2'b0, frm} - {2'b0, F_BAR0});
    wire bar_out  = boot_phase && (uy >= BAR_Y - 2) && (uy < BAR_Y + BAR_H + 2) &&
                    (ux >= BAR_X0 - 2) && (ux <= BAR_X0 + 2*BAR_HW + 2);
    wire bar_slot = boot_phase && (uy >= BAR_Y) && (uy < BAR_Y + BAR_H) &&
                    (ux >= BAR_X0) && (ux <= BAR_X0 + 2*BAR_HW);
    wire bar_fill = bar_slot && ((ux - BAR_X0) < fill);

    reg [23:0] bar_rgb;
    always @* begin
        if (bar_fill)      bar_rgb = {8'h12, 8'hD2, 8'hFF};
        else if (bar_slot) bar_rgb = {8'h01, 8'h0A, 8'h14};
        else if (bar_out)  bar_rgb = {8'h05, 8'h22, 8'h34};
        else               bar_rgb = 24'd0;
    end
    wire bar_hit = boot_phase && (bar_out | bar_slot);

    // ---- 收尾闪白 ----
    reg [7:0] flash;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            flash <= 8'd0;
        else if (frame_start && boot_phase) begin
            if (frm < F_FLASH)
                flash <= 8'd0;
            else if (frm < F_FLASH2)
                flash <= (flash > 8'd223) ? 8'd255 : (flash + 8'd32);
            else if (frm < F_BLACK)
                flash <= (flash > 8'd6) ? (flash - 8'd6) : 8'd0;
            else
                flash <= 8'd0;
        end
    end

    //=========================================================================
    // 4. 加载画面：5 个汉字 + 8 点转圈
    //=========================================================================
    wire [5:0]      trow   = (uy - TXT_Y0);                 // 0..CELL-1
    wire [8:0]      radr   = {x[2:0], trow};                // 取行时 ch = x[2:0]
    wire            rom_ce = de && (uy >= TXT_Y0) && (uy < TXT_Y0 + CELL) && (x < 12'd5);
    wire [CELL-1:0] rom_q;

    team_boot_font_rom #(.CELL(CELL)) u_font (
        .clk  (clk),
        .ce   (rom_ce),
        .addr (radr),
        .dout (rom_q)
    );

    reg [CELL-1:0] w0, w1, w2, w3, w4;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w0 <= {CELL{1'b0}}; w1 <= {CELL{1'b0}}; w2 <= {CELL{1'b0}};
            w3 <= {CELL{1'b0}}; w4 <= {CELL{1'b0}};
        end
        // 只在行首前 16 个像素取行：x[3:0] 会每 16 像素回绕一次，
        // 必须再用 x[11:4]==0 限定，否则后半行会用陈旧 ROM 数据覆盖 5 个字。
        else if (de && (x[11:4] == 8'd0)) begin
            case (x[3:0])
                4'd1: w0 <= rom_q;
                4'd2: w1 <= rom_q;
                4'd3: w2 <= rom_q;
                4'd4: w3 <= rom_q;
                4'd5: w4 <= rom_q;
                default: ;
            endcase
        end
    end

    wire [9:0]      tx   = ux[9:0] - TXT_X0_10;             // 0..TXT_W-1
    wire [2:0]      tch  = tx[CELL_SH+2 : CELL_SH];         // 第几个字
    wire [5:0]      txp  = tx[CELL_SH-1:0];                 // 字内第几列
    wire [5:0]      tidx = CELL_LAST - txp;

    reg [CELL-1:0] wsel;
    always @* begin
        case (tch)
            3'd0:    wsel = w0;
            3'd1:    wsel = w1;
            3'd2:    wsel = w2;
            3'd3:    wsel = w3;
            default: wsel = w4;
        endcase
    end

    wire txt_area = load_phase && (uy >= TXT_Y0) && (uy < TXT_Y0 + CELL) &&
                    (ux >= TXT_X0) && (ux < TXT_X0 + TXT_W);
    wire txt_on   = txt_area && wsel[tidx];

    wire [1:0] t_lvl = (frm < BF_MAX + 10'd6)  ? 2'd0 :
                       (frm < BF_MAX + 10'd12) ? 2'd1 :
                       (frm < BF_MAX + 10'd18) ? 2'd2 : 2'd3;
    wire [7:0] t_bri = (t_lvl == 2'd0) ? 8'd18  :
                       (t_lvl == 2'd1) ? 8'd80  :
                       (t_lvl == 2'd2) ? 8'd170 : 8'd255;
    wire [23:0] txt_rgb = {t_bri, t_bri, t_bri};

    // ---- 8 点转圈 -> 3 个唯一 |offset| ----
    wire spin_h0 = dot_hit(rax, say, 13'd0,  13'd36, SPIN_DR);
    wire spin_h1 = dot_hit(rax, say, 13'd25, 13'd25, SPIN_DR);
    wire spin_h2 = dot_hit(rax, say, 13'd36, 13'd0,  SPIN_DR);

    wire [7:0] spin_geo;
    assign spin_geo[0] = spin_h0 & load_phase & spy_neg;                  // (  0,-36)
    assign spin_geo[1] = spin_h1 & load_phase & ~sx_neg & spy_neg;
    assign spin_geo[2] = spin_h2 & load_phase & ~sx_neg;                  // ( 36,  0)
    assign spin_geo[3] = spin_h1 & load_phase & ~sx_neg & ~spy_neg;
    assign spin_geo[4] = spin_h0 & load_phase & ~spy_neg;                 // (  0, 36)
    assign spin_geo[5] = spin_h1 & load_phase & sx_neg & ~spy_neg;
    assign spin_geo[6] = spin_h2 & load_phase & sx_neg;                   // (-36,  0)
    assign spin_geo[7] = spin_h1 & load_phase & sx_neg & spy_neg;

    function [7:0] spin_trail;
        input [2:0] n;
        begin
            case (n)
                3'd0:    spin_trail = 8'd255;
                3'd1:    spin_trail = 8'd200;
                3'd2:    spin_trail = 8'd145;
                3'd3:    spin_trail = 8'd95;
                3'd4:    spin_trail = 8'd55;
                3'd5:    spin_trail = 8'd25;
                3'd6:    spin_trail = 8'd8;
                default: spin_trail = 8'd0;
            endcase
        end
    endfunction

    reg  [7:0] spin_bri [0:7];
    reg  [2:0] sp_div;
    wire       sp_tick = frame_start && load_phase && (sp_div == 3'd4);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sp_div <= 3'd0;
        else if (frame_start && load_phase)
            sp_div <= (sp_div == 3'd4) ? 3'd0 : (sp_div + 3'd1);
    end

    integer j;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (j = 0; j < 8; j = j + 1)
                spin_bri[j] <= spin_trail(j[2:0]);
        end
        else if (!load_phase) begin
            for (j = 0; j < 8; j = j + 1)
                spin_bri[j] <= spin_trail(j[2:0]);          // 不在加载段：冻结
        end
        else if (sp_tick) begin
            for (j = 0; j < 8; j = j + 1)
                spin_bri[j] <= spin_bri[(j + 1) % 8];
        end
    end

    reg [7:0] spin_col;
    reg       spin_on;
    integer   m;
    always @* begin
        spin_col = 8'd0;
        spin_on  = 1'b0;
        for (m = 0; m < 8; m = m + 1) begin
            // 同理：亮度 0 的点不画，避免黑斑
            if (spin_geo[m] && (spin_bri[m] != 8'd0)) begin
                spin_on  = 1'b1;
                spin_col = spin_bri[m];
            end
        end
    end
    wire [23:0] spin_rgb = {2'b00, spin_col[7:2], spin_col, spin_col};

    //=========================================================================
    // 5. 背景与像素合成
    //=========================================================================
    wire [7:0] bg_base = 8'd6 + {2'b0, uy[8:3]};
    wire       grid    = (ux[4:0] == 5'd0) || (uy[4:0] == 5'd0);
    wire [7:0] bg_r    = bg_base[7:2] + (grid ? 8'd5  : 8'd0);
    wire [7:0] bg_g    = bg_base[7:1] + (grid ? 8'd8  : 8'd0);
    wire [7:0] bg_b    = bg_base     + (grid ? 8'd12 : 8'd0);
    wire [23:0] bg_rgb = {bg_r, bg_g, bg_b};

    // 闪白用的加饱和（9 位中间量，避免 8 位加法溢出）
    reg [23:0] scene;
    reg [23:0] pix;
    reg [8:0]  sr, sg, sb;

    always @* begin
        // 先按“开机画面”合成
        scene = bg_rgb;
        if (bar_hit) scene = bar_rgb;
        if (ring_on) scene = ring_rgb;
        if (c_on)    scene = c_rgb;
        sr = {1'b0, scene[23:16]} + {1'b0, flash};
        sg = {1'b0, scene[15:8]}  + {1'b0, flash};
        sb = {1'b0, scene[7:0]}   + {1'b0, flash};

        if (o_phase == PH_BOOT) begin
            if (frm >= F_BLACK) begin
                pix = 24'd0;                                     // 收尾全黑
            end
            else begin
                pix = {(sr > 9'd255) ? 8'd255 : sr[7:0],
                       (sg > 9'd255) ? 8'd255 : sg[7:0],
                       (sb > 9'd255) ? 8'd255 : sb[7:0]};
            end
        end
        else if (o_phase == PH_LOAD) begin
            pix = bg_rgb;
            if (txt_on)  pix = txt_rgb;
            if (spin_on) pix = spin_rgb;
        end
        else begin
            pix = i_img_valid ? i_img_rgb : 24'd0;
        end
    end

    //=========================================================================
    // 6. 输出寄存器（比输入晚 1 个像素时钟）
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_rgb <= 24'd0;
            o_de  <= 1'b0;
            o_hs  <= 1'b0;
            o_vs  <= 1'b0;
        end
        else begin
            o_rgb <= pix;
            o_de  <= de;
            o_hs  <= hs;
            o_vs  <= vs;
        end
    end

endmodule
