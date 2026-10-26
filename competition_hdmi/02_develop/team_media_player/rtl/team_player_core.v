// Independent application. Board PHY/IP are outside this module.
module team_player_core #(
    parameter WIDTH=640,HEIGHT=480,HTOTAL=800,VTOTAL=525,
    parameter HFP=16,HSA=96,VFP=10,VSA=2,DEBOUNCE_CYCLES=250000
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
    output wire [1:0] active_slot,output wire active_valid,auto_play,
    output wire [1:0] period_setting,output wire fade_fault,
    output wire [31:0] video_underruns,audio_underruns
);
    wire [3:0] mask;wire wvalid,wready,wrsp,werror;wire [20:0] waddr;wire [31:0] wdata;
    wire b_req,b_cancel,b_ready;wire [31:0] b_lba;
    wire a_req,a_cancel,a_ready;wire [31:0] a_lba;
    wire [31:0] fat,data,clusters,a_size;wire [7:0] spc;wire [27:0] a_cluster;wire a_found;
    assign sd_req=boot_done?a_req:b_req;assign sd_lba=boot_done?a_lba:b_lba;
    assign sd_cancel=boot_done?a_cancel:b_cancel;assign sd_ready=boot_done?a_ready:b_ready;
    reg boot_started;
    wire boot_start=sd_initialized&&mem_initialized&&!boot_started;
    always @(posedge mem_clk or negedge mem_rst_n)
        if(!mem_rst_n)boot_started<=0;else if(boot_start)boot_started<=1;
    team_boot_loader #(.IMAGE_WIDTH(WIDTH),.IMAGE_HEIGHT(HEIGHT)) boot(
        .clk(mem_clk),.rst_n(mem_rst_n),.start(boot_start),.slot_valid(mask),.image_count(image_count),
        .finished(boot_done),.failed(boot_failed),.stage(boot_stage),.error_code(boot_error),.rejected_count(),
        .fat_lba(fat),.data_lba(data),.cluster_count(clusters),.spc(spc),
        .audio_found(a_found),.audio_cluster(a_cluster),.audio_size(a_size),
        .rd_req_valid(b_req),.rd_cancel(b_cancel),.rd_req_ready(sd_req_ready&&!boot_done),.rd_req_lba(b_lba),
        .rd_valid(sd_valid&&!boot_done),.rd_ready(b_ready),.rd_data(sd_data),.rd_last(sd_last),.rd_error(sd_error&&!boot_done),
        .wr_valid(wvalid),.wr_ready(wready),.wr_addr(waddr),.wr_data(wdata),.wr_rsp_valid(wrsp),.wr_rsp_error(werror));
    wire lv,lr,lpv,ld,le;wire [20:0] la;wire [9:0] lpi;wire [23:0] lpd;
    team_sdram_port #(.LINE_WIDTH(WIDTH)) memory_port(
        .clk(mem_clk),.rst_n(mem_rst_n),.mem_initialized(mem_initialized),.mem_busy(mem_busy),.mem_refresh(mem_refresh),
        .wr_valid(wvalid),.wr_ready(wready),.wr_addr(waddr),.wr_data(wdata),.wr_rsp_valid(wrsp),.wr_rsp_error(werror),
        .line_valid(lv),.line_ready(lr),.line_addr(la),.line_pixel_valid(lpv),.line_pixel_index(lpi),
        .line_pixel_data(lpd),.line_done(ld),.line_error(le),.app_wr_en(app_wr_en),.app_wr_addr(app_wr_addr),
        .app_wr_data(app_wr_data),.app_rd_en(app_rd_en),.app_rd_addr(app_rd_addr),.mem_rd_valid(mem_rd_valid),.mem_rd_data(mem_rd_data));
    wire swv,swr,swcancel,reply,reply_error,frame_tick;
    wire [1:0] swslot,rslot;wire [31:0] swtoken,rtoken;
    wire [23:0] raw_rgb;wire raw_hs,raw_vs,raw_de;wire [15:0] raw_x,raw_y;
    team_line_scanout #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.HTOTAL(HTOTAL),.VTOTAL(VTOTAL),
        .HFP(HFP),.HSA(HSA),.VFP(VFP),.VSA(VSA)) scanout(
        .video_clk(video_clk),.video_rst_n(video_rst_n),.mem_clk(mem_clk),.mem_rst_n(mem_rst_n),
        .boot_finished(boot_done),.resident_mask(mask),.switch_valid(swv),.switch_ready(swr),
        .switch_slot(swslot),.switch_token(swtoken),.switch_cancel(swcancel),.reply_valid(reply),
        .reply_slot(rslot),.reply_token(rtoken),.reply_error(reply_error),.active_slot(active_slot),
        .active_valid(active_valid),.frame_tick(frame_tick),.rgb(raw_rgb),.hs(raw_hs),.vs(raw_vs),.de(raw_de),
        .x(raw_x),.y(raw_y),.underruns(video_underruns),.line_valid(lv),.line_ready(lr),.line_addr(la),
        .line_pixel_valid(lpv),.line_pixel_index(lpi),.line_pixel_data(lpd),.line_done(ld),.line_error(le));
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
        .recover_valid(1'b0),.recover_ready(),.recover_slot(2'd0),.in_rgb(raw_rgb),.in_hs(raw_hs),.in_vs(raw_vs),
        .in_de(raw_de),.in_x(raw_x),.in_y(raw_y),.out_rgb(rgb),.out_hs(hs),.out_vs(vs),.out_de(de),
        .out_x(x),.out_y(y),.gain(),.busy(),.fault(fade_fault),.blackout(),.done(),.failed(),.result_slot(),.error_code(),.phase());
    wire sv,sr;wire [31:0] sample;wire fifo_empty,fifo_read;wire [31:0] fifo_data;wire [11:0] level;
    team_audio_file audio_source(
        .clk(mem_clk),.rst_n(mem_rst_n),.enable(boot_done),.state(audio_stage),.error_code(audio_error),
        .found(a_found),.fat(fat),.data(data),.clusters(clusters),.spc(spc),.first_cluster(a_cluster),.file_size(a_size),
        .sample_valid(sv),.sample_ready(sr),.sample_data(sample),.rd_req_valid(a_req),.rd_cancel(a_cancel),
        .rd_req_ready(sd_req_ready&&boot_done),.rd_req_lba(a_lba),.rd_valid(sd_valid&&boot_done),
        .rd_ready(a_ready),.rd_data(sd_data),.rd_last(sd_last),.rd_error(sd_error&&boot_done));
    team_pcm_fifo fifo(.wr_clk(mem_clk),.wr_rst_n(mem_rst_n),.wr_valid(sv),.wr_ready(sr),.wr_data(sample),
        .rd_clk(video_clk),.rd_rst_n(video_rst_n),.rd_enable(fifo_read),.rd_data(fifo_data),.empty(fifo_empty),.rd_level(level));
    team_pcm_hdmi audio_out(.clk(video_clk),.rst_n(video_rst_n),.fifo_data(fifo_data),.fifo_empty(fifo_empty),
        .fifo_level(level),.fifo_read(fifo_read),.audio_valid(audio_valid),.audio_left(audio_left),.audio_right(audio_right),
        .acr_valid(acr_valid),.acr_n(acr_n),.acr_cts(acr_cts),.underruns(audio_underruns));
endmodule
