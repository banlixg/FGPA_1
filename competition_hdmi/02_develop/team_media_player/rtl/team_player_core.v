// Independent application. Board PHY/IP are outside this module.
//
// 2026-11-04 增加开机序列（按需求）：
//   上电 -> 开机动画 + 开机音效（约 10 s）
//        -> 「识别图片中 + 转圈」画面，同时开始读卡装图（数码管倒计时可见 0->1->..->4）
//        -> 装图完成（boot_done）立刻切到实时图片显示
//
// 实现要点：
//   * team_boot_layer 插在 line_scanout 与 fade 之间：PH_BOOT 动画 / PH_LOAD 加载画面 /
//     PH_IMG 透传；o_boot_done(动画结束) 用来门控 boot_loader 的 start，
//     这样"先动画、再读图"的顺序是硬保证的，不靠延时。
//   * team_boot_chime 用视频域合成的 48 kHz 节拍发声，开机音响 10 s；
//     boot_done 之前音频选 chime，之后切回文件 PCM（AUDIO.WAV 循环）。
//   * x/y 打一拍与 boot_layer 的寄存输出对齐，避免淡入淡出期间 1 像素错位。
module team_player_core #(
    parameter WIDTH=640,HEIGHT=480,HTOTAL=800,VTOTAL=525,
    parameter HFP=16,HSA=96,VFP=10,VSA=2,DEBOUNCE_CYCLES=250000,
    parameter BOOT_FRM=600                  // 开机动画帧数（60Hz => 10 秒）
)(
    input wire mem_clk,mem_rst_n,video_clk,video_rst_n,
    input wire sd_initialized,sd_failed,
    input wire next_key_n,auto_key_n,period_key_n,
    output wire sd_req,sd_cancel,input wire sd_req_ready,output wire [31:0] sd_lba,
    input wire sd_valid,output wire sd_ready,input wire [7:0] sd_data,input wire sd_last,sd_error,
    input wire mem_initialized,mem_busy,mem_refresh,
    output wire app_wr_en,output wire [20:0] app_wr_addr,output wire [31:0] app_wr_data,
    output wire app_rd_en,output wire [20:0] app_rd_addr,input wire mem_rd_valid,input wire [31:0] mem_rd_data,
    output wire [23:0] rgb,output wire hs,vs,de,output wire [15:0] x,y,
    output wire audio_valid,output wire [23:0] audio_left,audio_right,
    output wire acr_valid,output wire [19:0] acr_n,acr_cts,
    output wire [3:0] boot_stage,boot_error,audio_stage,audio_error,
    output wire [2:0] image_count,output wire boot_done,boot_failed,
    output wire [3:0] boot_detail,   // 图片加载器最近错误码（诊断）
    output wire [1:0] active_slot,output wire active_valid,auto_play,
    output wire [1:0] period_setting,output wire fade_fault,
    output wire [31:0] video_underruns,audio_underruns,
    output wire [1:0] boot_phase,    // 0=动画 1=加载画面 2=图片（诊断用）
    output wire       boot_wdog,
    input  wire       vol_sw1,       // SW1(C8)：拨动一次 音量 +1
    input  wire       vol_sw2        // SW2(C7)：拨动一次 音量 -1
);
    wire [3:0] mask;wire [3:0] dcode;assign boot_detail=dcode;wire wvalid,wready,wrsp,werror;wire [20:0] waddr;wire [31:0] wdata;
    wire b_req,b_cancel,b_ready;wire [31:0] b_lba;
    wire a_req,a_cancel,a_ready;wire [31:0] a_lba;
    wire [31:0] fat,data,clusters,a_size;wire [7:0] spc;wire [27:0] a_cluster;wire a_found;
    assign sd_req=boot_done?a_req:b_req;assign sd_lba=boot_done?a_lba:b_lba;
    assign sd_cancel=boot_done?a_cancel:b_cancel;assign sd_ready=boot_done?a_ready:b_ready;

    //--------------------------------------------------------------------------
    // 视频域 48 kHz 节拍（25MHz / 48000 = 520.83，用累加器）
    //   供开机音效取样 + boot_layer 看门狗时基
    //--------------------------------------------------------------------------
    reg [24:0] aud_acc;
    reg        aud_tick;
    always @(posedge video_clk or negedge video_rst_n) begin
        if (!video_rst_n) begin
            aud_acc  <= 25'd0;
            aud_tick <= 1'b0;
        end else if (aud_acc + 25'd48000 >= 25'd25000000) begin
            aud_acc  <= aud_acc + 25'd48000 - 25'd25000000;
            aud_tick <= 1'b1;
        end else begin
            aud_acc  <= aud_acc + 25'd48000;
            aud_tick <= 1'b0;
        end
    end

    //--------------------------------------------------------------------------
    // 开机动画层：动画 -> 加载画面 -> 图片透传
    // 输出比输入晚一拍；x/y 也打一拍对齐
    //--------------------------------------------------------------------------
    wire [23:0] raw_rgb;wire raw_hs,raw_vs,raw_de;wire [15:0] raw_x,raw_y;
    wire [23:0] lay_rgb;wire lay_hs,lay_vs,lay_de;
    wire        anim_done;          // 动画结束（= boot_loader 允许启动）
    wire        frame_tick;
    reg  [15:0] rx_d,ry_d;
    reg         av_d;
    wire        commit_pulse = active_valid & ~av_d;

    always @(posedge video_clk or negedge video_rst_n)
        if (!video_rst_n) begin rx_d<=16'd0; ry_d<=16'd0; av_d<=1'b0; end
        else begin rx_d<=raw_x; ry_d<=raw_y; av_d<=active_valid; end

    //--------------------------------------------------------------------------
    // 启动流程：动画播完才允许读卡装图
    //--------------------------------------------------------------------------
    reg boot_started;
    wire boot_start = sd_initialized && mem_initialized && anim_done && !boot_started;
    always @(posedge mem_clk or negedge mem_rst_n)
        if(!mem_rst_n)boot_started<=0;else if(boot_start)boot_started<=1;

    team_boot_loader #(.IMAGE_WIDTH(WIDTH),.IMAGE_HEIGHT(HEIGHT)) boot(
        .clk(mem_clk),.rst_n(mem_rst_n),.start(boot_start),.slot_valid(mask),.image_count(image_count),
        .finished(boot_done),.failed(boot_failed),.stage(boot_stage),.error_code(boot_error),.rejected_count(),.last_image_error(dcode),
        .fat_lba(fat),.data_lba(data),.cluster_count(clusters),.spc(spc),
        .audio_found(a_found),.audio_cluster(a_cluster),.audio_size(a_size),
        .rd_req_valid(b_req),.rd_cancel(b_cancel),.rd_req_ready(sd_req_ready&&!boot_done),.rd_req_lba(b_lba),
        .rd_valid(sd_valid&&!boot_done),.rd_ready(b_ready),.rd_data(sd_data),.rd_last(sd_last),.rd_error(sd_error&&!boot_done),
        .wr_valid(wvalid),.wr_ready(wready),.wr_addr(waddr),.wr_data(wdata),.wr_rsp_valid(wrsp),.wr_rsp_error(werror));

    wire lv,lr,lpv,ld,le;wire [20:0] la;wire [9:0] lpi;wire [23:0] lpd;
    team_sdram_port #(.VERIFY_ENABLE(1),.LINE_WIDTH(WIDTH)) memory_port(
        .clk(mem_clk),.rst_n(mem_rst_n),.mem_initialized(mem_initialized),.mem_busy(mem_busy),.mem_refresh(mem_refresh),
        .wr_valid(wvalid),.wr_ready(wready),.wr_addr(waddr),.wr_data(wdata),.wr_rsp_valid(wrsp),.wr_rsp_error(werror),
        .line_valid(lv),.line_ready(lr),.line_addr(la),.line_pixel_valid(lpv),.line_pixel_index(lpi),
        .line_pixel_data(lpd),.line_done(ld),.line_error(le),.app_wr_en(app_wr_en),.app_wr_addr(app_wr_addr),
        .app_wr_data(app_wr_data),.app_rd_en(app_rd_en),.app_rd_addr(app_rd_addr),.mem_rd_valid(mem_rd_valid),.mem_rd_data(mem_rd_data));

    wire swv,swr,swcancel,reply,reply_error;
    wire [1:0] swslot,rslot;wire [31:0] swtoken,rtoken;
    team_line_scanout #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.HTOTAL(HTOTAL),.VTOTAL(VTOTAL),
        .HFP(HFP),.HSA(HSA),.VFP(VFP),.VSA(VSA)) scanout(
        .video_clk(video_clk),.video_rst_n(video_rst_n),.mem_clk(mem_clk),.mem_rst_n(mem_rst_n),
        .boot_finished(boot_done),.resident_mask(mask),.switch_valid(swv),.switch_ready(swr),
        .switch_slot(swslot),.switch_token(swtoken),.switch_cancel(swcancel),.reply_valid(reply),
        .reply_slot(rslot),.reply_token(rtoken),.reply_error(reply_error),.active_slot(active_slot),
        .active_valid(active_valid),.frame_tick(frame_tick),.rgb(raw_rgb),.hs(raw_hs),.vs(raw_vs),.de(raw_de),
        .x(raw_x),.y(raw_y),.underruns(video_underruns),.line_valid(lv),.line_ready(lr),.line_addr(la),
        .line_pixel_valid(lpv),.line_pixel_index(lpi),.line_pixel_data(lpd),.line_done(ld),.line_error(le));

    // 开机动画 / 加载画面 / 图片 三层合成
    team_boot_layer #(
        .H_ACTIVE(WIDTH), .V_ACTIVE(HEIGHT), .BOOT_FRM(BOOT_FRM),
        .FAST_SWITCH(1), .CELL(64), .WDOG_TICKS(24000)
    ) boot_layer(
        .clk(video_clk),.rst_n(video_rst_n),
        .de(raw_de),.hs(raw_hs),.vs(raw_vs),.x(raw_x[11:0]),.y(raw_y[11:0]),.frame_start(frame_tick),
        .i_img_rgb(raw_rgb),.i_img_valid(raw_de),
        .i_active_valid(active_valid),.i_active_slot(active_slot),.i_commit_pulse(commit_pulse),
        .i_loading_req(!boot_done),.i_skip_boot(1'b0),.i_boot_en(1'b1),.i_audio_tick(aud_tick),
        .o_rgb(lay_rgb),.o_de(lay_de),.o_hs(lay_hs),.o_vs(lay_vs),
        .o_phase(boot_phase),.o_boot_done(anim_done),.o_frm(),.o_wdog(boot_wdog),.o_active_slot());

    wire [23:0] fv_rgb;wire fv_hs,fv_vs,fv_de;wire [15:0] fv_x,fv_y;
    wire reqv,reqr;wire [1:0] reqslot;wire [9:0] period_frames;
    reg [3:0] mask1,mask2;
    always @(posedge video_clk or negedge video_rst_n)
        if(!video_rst_n)begin mask1<=0;mask2<=0;end else begin mask1<=mask;mask2<=mask1;end
    team_player_control #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) control(
        .clk(video_clk),.rst_n(video_rst_n),.frame_tick(frame_tick),.next_key_n(next_key_n),
        .auto_key_n(auto_key_n),.period_key_n(period_key_n),.active_valid(active_valid),
        .active_slot(active_slot),.resident_mask(mask2),.request_ready(reqr),.request_valid(reqv),
        .request_slot(reqslot),.auto_play(auto_play),.period_setting(period_setting),.period_frames(period_frames));
    team_fade_effect #(.WATCHDOG_CYCLES(50000000)) fade(
        .clk(video_clk),.rst_n(video_rst_n),.frame_tick(frame_tick),.request_valid(reqv),.request_ready(reqr),
        .request_slot(reqslot),.request_slot_valid(mask2[reqslot]),.effect_enable(1'b1),.request_step(9'd8),
        .abort_transition(1'b0),.switch_valid(swv),.switch_ready(swr),.switch_slot(swslot),.switch_token(swtoken),
        .switch_cancel(swcancel),.reply_valid(reply),.reply_token(rtoken),.reply_slot(rslot),.reply_error(reply_error),
        .recover_valid(1'b0),.recover_ready(),.recover_slot(2'd0),.in_rgb(lay_rgb),.in_hs(lay_hs),.in_vs(lay_vs),
        .in_de(lay_de),.in_x(rx_d),.in_y(ry_d),.out_rgb(fv_rgb),.out_hs(fv_hs),.out_vs(fv_vs),.out_de(fv_de),
        .out_x(fv_x),.out_y(fv_y),.gain(),.busy(),.fault(fade_fault),.blackout(),.done(),.failed(),.result_slot(),.error_code(),.phase());

    //-----------------------------------------------------------------
    // 音量 OSD：拨码 SW1/SW2 调本机音量，右侧竖条显示，并输出增益电平
    //-----------------------------------------------------------------
    wire [23:0] vol_rgb;
    wire        vol_de,vol_hs,vol_vs;
    wire [3:0]  vol_level;
    team_volume_osd #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) vol_osd(
        .clk(video_clk),.rst_n(video_rst_n),.frame_tick(frame_tick),
        .sw1_i(vol_sw1),.sw2_i(vol_sw2),
        .de(fv_de),.x(fv_x),.y(fv_y),
        .in_rgb(fv_rgb),.in_de(fv_de),.in_hs(fv_hs),.in_vs(fv_vs),
        .out_rgb(vol_rgb),.out_de(vol_de),.out_hs(vol_hs),.out_vs(vol_vs),
        .level(vol_level),.osd_visible());
    assign rgb = vol_rgb; assign de = vol_de; assign hs = vol_hs; assign vs = vol_vs;
    assign x = fv_x; assign y = fv_y;

    //--------------------------------------------------------------------------
    // 音频：boot_done 之前放开机音效，之后放文件 PCM（AUDIO.WAV 循环）
    //--------------------------------------------------------------------------
    wire [23:0] chime_smp;
    wire        chime_done;
    team_boot_chime chime(
        .clk_mclk(video_clk),.rst_n(video_rst_n),.i_tick(aud_tick),.o_sample(chime_smp),.o_done(chime_done));

    wire sv,sr;wire [31:0] sample;wire fifo_empty,fifo_read;wire [31:0] fifo_data;wire [11:0] level;
    team_audio_file audio_source(
        .clk(mem_clk),.rst_n(mem_rst_n),.enable(boot_done),.state(audio_stage),.error_code(audio_error),
        .found(a_found),.fat(fat),.data(data),.clusters(clusters),.spc(spc),.first_cluster(a_cluster),.file_size(a_size),
        .sample_valid(sv),.sample_ready(sr),.sample_data(sample),.rd_req_valid(a_req),.rd_cancel(a_cancel),
        .rd_req_ready(sd_req_ready&&boot_done),.rd_req_lba(a_lba),.rd_valid(sd_valid&&boot_done),
        .rd_ready(a_ready),.rd_data(sd_data),.rd_last(sd_last),.rd_error(sd_error&&boot_done));
    team_pcm_fifo fifo(.wr_clk(mem_clk),.wr_rst_n(mem_rst_n),.wr_valid(sv),.wr_ready(sr),.wr_data(sample),
        .rd_clk(video_clk),.rd_rst_n(video_rst_n),.rd_enable(fifo_read),.rd_data(fifo_data),.empty(fifo_empty),.rd_level(level));
    wire        pcm_valid;
    wire [23:0] pcm_left,pcm_right;
    team_pcm_hdmi audio_out(.clk(video_clk),.rst_n(video_rst_n),.fifo_data(fifo_data),.fifo_empty(fifo_empty),
        .fifo_level(level),.fifo_read(fifo_read),.audio_valid(pcm_valid),.audio_left(pcm_left),.audio_right(pcm_right),
        .acr_valid(acr_valid),.acr_n(acr_n),.acr_cts(acr_cts),.underruns(audio_underruns));

    // 数字音量：PCM * level / 16（16 级），竖条高度即该增益
    wire signed [27:0] gain_l = ($signed(pcm_left)  * $signed({1'b0,vol_level}));
    wire signed [27:0] gain_r = ($signed(pcm_right) * $signed({1'b0,vol_level}));
    wire boot_audio = (!boot_done) && (!chime_done);
    assign audio_valid = boot_audio ? aud_tick : pcm_valid;
    assign audio_left  = boot_audio ? chime_smp : gain_l[27:4];
    assign audio_right = boot_audio ? chime_smp : gain_r[27:4];
endmodule
