//=============================================================================
// top_sdram_test.v  —  SDRAM 直读自检 v2（诊断用临时顶层）
//
// v1 结论：init_done=1（控制器初始化成功），但 4 次“写→读回比对”全失败。
// v2 改为直接操作 SIP 的 App_wr/App_rd 接口，把读回来的数据原样显示，
// 以便区分是“写没落地”还是“读回数据错位/损坏”。
//
// 序列：等 init_done → 写 0xA5A55A5A 到地址 0 → 等 64 拍 → 读地址 0
//       → 收到 Sdr_rd_en 时锁存数据 → 显示
//
// 数码管（每位一 nibble，左起）：
//   [0]=读回数据 bit3:0   [1]=bit7:4   [2]=bit11:8   [3]=bit15:12
//   [4]=状态(1写 2等 3读 4收到 5超时)   [5]=init_done
// 正常应显示： A 5 A 5 4 1   （0xA5A55A5A 的低 16 位 = 5A5A → 左起 A,5,A,5）
//=============================================================================
`timescale 1ns/1ps

module top_sdram_test(
    input  wire       clk,
    output wire [5:0] seg_sel,
    output wire [7:0] seg_data,
    output wire [3:0] led
);
    wire mem_clk, mem_shift, unused_clk, sys_lock;
    team_mem_pll sys_pll_m0(.refclk(clk),.reset(1'b0),.extlock(sys_lock),
        .clk0_out(mem_clk),.clk1_out(unused_clk),.clk2_out(mem_shift));

    // 锁上后再等 1,000,000 拍（与已验证基线一致）
    reg [19:0] rst_cnt;
    reg        rst_n_m;
    always @(posedge mem_clk) begin
        if (!sys_lock) begin rst_cnt <= 20'd0; rst_n_m <= 1'b0; end
        else if (rst_cnt < 20'd1_000_000) begin rst_cnt <= rst_cnt + 20'd1; rst_n_m <= 1'b0; end
        else rst_n_m <= 1'b1;
    end

    wire        mi, mr, mb;
    wire        aw, ar, rdv;
    wire [20:0] wa, ra;
    wire [31:0] wd, rd;
    wire [3:0]  wr_dm;
    assign wr_dm = 4'd0;

    team_board_sdram memory(
        .Clk(mem_clk), .Clk_sft(mem_shift), .Rst(!rst_n_m),
        .Sdr_init_done(mi), .Sdr_init_ref_vld(mr), .Sdr_busy(mb),
        .App_wr_en(aw), .App_wr_addr(wa), .App_wr_dm(wr_dm), .App_wr_din(wd),
        .App_rd_en(ar), .App_rd_addr(ra), .Sdr_rd_en(rdv), .Sdr_rd_dout(rd));

    //---------------------------------------------------------------
    // 直接驱动 App 接口的最小状态机
    //---------------------------------------------------------------
    localparam T_IDLE=3'd0, T_WRITE=3'd1, T_SETTLE=3'd2, T_READ=3'd3, T_GOT=3'd4, T_TIMEOUT=3'd5;
    reg [2:0]  st;
    reg        we, re;
    reg [20:0] addr_r;
    reg [31:0] din_r;
    reg [31:0] captured;
    reg [15:0] wait_cnt, timeout_cnt;
    reg [3:0]  rd_cnt;
    reg [1:0]  burst_idx;
    wire       pad_unused;

    always @(posedge mem_clk or negedge rst_n_m) begin
        if (!rst_n_m) begin
            st <= T_IDLE; we <= 1'b0; re <= 1'b0; addr_r <= 21'd0; din_r <= 32'd0;
            captured <= 32'hFFFF_FFFF; wait_cnt <= 16'd0; timeout_cnt <= 16'd0;
            rd_cnt <= 4'd0; burst_idx <= 2'd0;
        end else begin
            we <= 1'b0;
            re <= 1'b0;
            case (st)
                T_IDLE: begin
                    if (mi) begin
                        st <= T_WRITE; burst_idx <= 2'd0; rd_cnt <= 4'd0;
                    end
                end
                // 单笔写（1 拍脉冲），不加 busy/refresh 门控
                T_WRITE: begin
                    we      <= 1'b1;
                    addr_r  <= 21'd0;
                    din_r   <= 32'hA5A5_1234;
                    st      <= T_SETTLE;
                    wait_cnt<= 16'd0;
                end
                T_SETTLE: begin
                    if (wait_cnt == 16'd64) begin st <= T_READ; burst_idx <= 2'd0; end
                    else wait_cnt <= wait_cnt + 16'd1;
                end
                // 单笔读
                T_READ: begin
                    re     <= 1'b1;
                    addr_r <= 21'd0;
                    st     <= T_GOT;
                    timeout_cnt <= 16'd0;
                end
                T_GOT: begin
                    if (rdv) begin
                        captured <= rd;
                        rd_cnt   <= rd_cnt + 4'd1;
                        timeout_cnt <= 16'd0;
                    end else if (timeout_cnt == 16'd3000) begin
                        st <= T_TIMEOUT;
                    end else timeout_cnt <= timeout_cnt + 16'd1;
                end
                default: st <= T_TIMEOUT;
            endcase
        end
    end

    assign aw = we;
    assign ar = re;
    assign wa = addr_r;
    assign ra = addr_r;
    assign wd = din_r;
    assign pad_unused = 1'b0;

    //---------------------------------------------------------------
    // 数码管
    //---------------------------------------------------------------
    wire [23:0] digits = { {3'b000,mi}, rd_cnt,
                           captured[15:12], captured[11:8], captured[7:4], captured[3:0] };

    reg [23:0] meta, sync;
    reg [15:0] ticks;
    reg [2:0]  digit;
    always @(posedge mem_clk or negedge rst_n_m) begin
        if (!rst_n_m) begin meta<=24'd0; sync<=24'd0; ticks<=16'd0; digit<=3'd0; end
        else begin
            meta <= digits; sync <= meta; ticks <= ticks + 16'd1;
            if (ticks == 16'd49999) begin ticks <= 16'd0; digit <= (digit==3'd5)?3'd0:(digit+3'd1); end
        end
    end

    function [7:0] glyph;
        input [3:0] value;
        begin
            case (value)
                4'd0: glyph=8'hc0; 4'd1: glyph=8'hf9; 4'd2: glyph=8'ha4; 4'd3: glyph=8'hb0;
                4'd4: glyph=8'h99; 4'd5: glyph=8'h92; 4'd6: glyph=8'h82; 4'd7: glyph=8'hf8;
                4'd8: glyph=8'h80; 4'd9: glyph=8'h90; 4'd10: glyph=8'h88; 4'd11: glyph=8'h83;
                4'd12: glyph=8'hc6; 4'd13: glyph=8'ha1; 4'd14: glyph=8'h86; default: glyph=8'h8e;
            endcase
        end
    endfunction

    reg [5:0] sel_r;
    reg [7:0] data_r;
    always @(posedge mem_clk or negedge rst_n_m) begin
        if (!rst_n_m) begin sel_r <= 6'b111111; data_r <= 8'hff; end
        else begin
            sel_r  <= ~(6'b000001 << digit);
            data_r <= glyph((sync >> (digit*4)) & 4'hf);
        end
    end
    assign seg_sel  = sel_r;
    assign seg_data = data_r;

    assign led = ~{1'b0, mi, (st==T_GOT), (st==T_TIMEOUT)};
endmodule
