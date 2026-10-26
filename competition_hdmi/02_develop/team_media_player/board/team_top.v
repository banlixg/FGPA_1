// HX4S20C physical shell. Application is team_player_core, not the reference top.
module team_top(
    input wire clk,rst_n,key1,key2,key_period,
    output wire [5:0] seg_sel,output wire [7:0] seg_data,
    output wire HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P,
    output wire HDMI_DDC_SCL,inout wire HDMI_DDC_SDA,
    output wire sd_ncs,sd_dclk,sd_mosi,input wire sd_miso
);
    wire mem_clk,mem_shift,unused_clk,video_clk,serial_clk,sys_lock,video_lock;
    team_mem_pll sys_pll_m0(.refclk(clk),.reset(1'b0),.extlock(sys_lock),
        .clk0_out(mem_clk),.clk1_out(unused_clk),.clk2_out(mem_shift));
    team_video_pll video_pll_m0(.refclk(clk),.reset(1'b0),.extlock(video_lock),
        .clk0_out(video_clk),.clk1_out(serial_clk));
    wire raw_rst_n=rst_n&&sys_lock&&video_lock;
    wire mrst_n,vrst_n,crst_n;
    team_reset_sync rm(mem_clk,raw_rst_n,mrst_n),rv(video_clk,raw_rst_n,vrst_n),rc(clk,raw_rst_n,crst_n);
    wire sd_initialized,sd_failed;wire [3:0] sd_code;
    wire sd_req,sd_req_ready,sd_cancel,sd_valid,sd_ready,sd_last,sd_error;
    wire [31:0] sd_lba;wire [7:0] sd_data;
    team_sd_spi_reader #(.POWER_CYCLES(500000),.SLOW_DIV(63),.FAST_DIV(2)) card(
        .clk(mem_clk),.rst_n(mrst_n),.initialized(sd_initialized),.init_failed(sd_failed),.error_code(sd_code),
        .high_capacity(),.rd_req_valid(sd_req),.rd_req_ready(sd_req_ready),.rd_req_lba(sd_lba),.rd_cancel(sd_cancel),
        .rd_valid(sd_valid),.rd_ready(sd_ready),.rd_data(sd_data),.rd_last(sd_last),.rd_error(sd_error),
        .sd_ncs(sd_ncs),.sd_dclk(sd_dclk),.sd_mosi(sd_mosi),.sd_miso(sd_miso));
    wire mi,mb,mr,aw,ar,rdv;wire [20:0] wa,ra;wire [31:0] wd,rd;
    team_board_sdram memory(.Clk(mem_clk),.Clk_sft(mem_shift),.Rst(!mrst_n),
        .Sdr_init_done(mi),.Sdr_init_ref_vld(mr),.Sdr_busy(mb),.App_wr_en(aw),.App_wr_addr(wa),
        .App_wr_dm(4'd0),.App_wr_din(wd),.App_rd_en(ar),.App_rd_addr(ra),.Sdr_rd_en(rdv),.Sdr_rd_dout(rd));
    wire [23:0] rgb;wire hs,vs,de;wire [15:0] x,y;
    wire av,acr;wire [23:0] al,art;wire [19:0] n,cts;
    wire [3:0] bs,be,as,ae;wire [2:0] count;wire bdone,bfailed;
    wire [1:0] slot,period;wire visible,auto_play,fault;wire [31:0] vu,au;
    team_player_core player(.mem_clk(mem_clk),.mem_rst_n(mrst_n),.video_clk(video_clk),.video_rst_n(vrst_n),
        .sd_initialized(sd_initialized),.sd_failed(sd_failed),.next_key_n(key1),.auto_key_n(key2),.period_key_n(key_period),
        .sd_req(sd_req),.sd_cancel(sd_cancel),.sd_req_ready(sd_req_ready),.sd_lba(sd_lba),.sd_valid(sd_valid),
        .sd_ready(sd_ready),.sd_data(sd_data),.sd_last(sd_last),.sd_error(sd_error),
        .mem_initialized(mi),.mem_busy(mb),.mem_refresh(mr),.app_wr_en(aw),.app_wr_addr(wa),.app_wr_data(wd),
        .app_rd_en(ar),.app_rd_addr(ra),.mem_rd_valid(rdv),.mem_rd_data(rd),
        .rgb(rgb),.hs(hs),.vs(vs),.de(de),.x(x),.y(y),.audio_valid(av),.audio_left(al),.audio_right(art),
        .acr_valid(acr),.acr_n(n),.acr_cts(cts),.boot_stage(bs),.boot_error(be),.audio_stage(as),.audio_error(ae),
        .image_count(count),.boot_done(bdone),.boot_failed(bfailed),.active_slot(slot),.active_valid(visible),
        .auto_play(auto_play),.period_setting(period),.fade_fault(fault),.video_underruns(vu),.audio_underruns(au));
    wire [9:0] ch0,ch1,ch2,chclk;wire axis_ready;
    reg [19:0] edid_count;reg edid_pulse;
    always @(posedge video_clk or negedge vrst_n)
        if(!vrst_n)begin edid_count<=0;edid_pulse<=0;end
        else begin edid_pulse<=0;if(edid_count<100000)edid_count<=edid_count+1'b1;else if(edid_count==100000)begin edid_pulse<=1;edid_count<=edid_count+1'b1;end end
    hdmi_1_4b_transmitter_core_wrapper #(
        .DEVICE("EG"),.HTOTAL(800),.HSA(96),.HFP(16),.HBP(48),.HACTIVE(640),
        .VTOTAL(525),.VSA(2),.VFP(10),.VBP(33),.VACTIVE(480),.VIDEO_VIC(1),
        .VIDEO_TPG("Disable"),.VIDEO_FORMAT("RGB"),.AUDIO_SAMPLE_RATE("48K"),.IIC_SCL_DIV(250)
    ) hdmi(.I_pixel_clk(video_clk),.I_rst(!vrst_n),.I_edid_read_trig(edid_pulse),
        .O_edid_read_valid(),.O_edid_read_data(),.I_axis_s_user(de&&x==0&&y==0),
        .I_axis_s_valid(de),.I_axis_s_last(de&&x==639),.I_axis_s_data(rgb),.O_axis_s_ready(axis_ready),
        .I_audio_valid(av),.I_audio_left_data(al),.I_audio_right_data(art),
        .I_acr_valid(acr),.I_acr_cts(cts),.I_acr_n(n),.O_video_locked(),
        .O_ddc_scl(HDMI_DDC_SCL),.IO_ddc_sda(HDMI_DDC_SDA),
        .O_ch0_tmds_data(ch0),.O_ch1_tmds_data(ch1),.O_ch2_tmds_data(ch2),.O_clk_tmds_data(chclk));
    hdmi_phy_wrapper #(.DEVICE("EG")) phy(.I_pixel_clk(video_clk),.I_serial_clk(serial_clk),.I_rst(!vrst_n),
        .I_tmds_channel_0(ch0),.I_tmds_channel_1(ch1),.I_tmds_channel_2(ch2),.I_tmds_channel_clk(chclk),
        .O_tmds_ch0_p(HDMI_D0_P),.O_tmds_ch1_p(HDMI_D1_P),.O_tmds_ch2_p(HDMI_D2_P),.O_tmds_clk_p(HDMI_CLK_P));
    reg axis_fault;
    always @(posedge video_clk or negedge vrst_n)
        if(!vrst_n)axis_fault<=0;else if(visible&&de&&!axis_ready)axis_fault<=1;
    wire [3:0] err=sd_failed?sd_code:fault?4'he:(vu!=0)?4'hd:(au!=0)?4'hc:axis_fault?4'hb:be;
    team_status_display display(.clk(mem_clk),.rst_n(mrst_n),
        .digits({bs,{1'b0,count},{2'd0,slot}+4'd1,{2'd0,auto_play,visible},as,err}),
        .seg_sel(seg_sel),.seg_data(seg_data));
endmodule

module team_reset_sync(input wire clk,raw_rst_n,output wire rst_n);
    reg [2:0] sync;
    always @(posedge clk or negedge raw_rst_n)if(!raw_rst_n)sync<=0;else sync<={sync[1:0],1'b1};
    assign rst_n=sync[2];
endmodule
module team_status_display(input wire clk,rst_n,input wire [23:0] digits,
    output reg [5:0] seg_sel,output reg [7:0] seg_data);
    reg [23:0] meta,sync;reg [15:0] ticks;reg [2:0] digit;
    function [7:0] glyph;
        input [3:0] value;
        begin case(value)
            0:glyph=8'hc0;1:glyph=8'hf9;2:glyph=8'ha4;3:glyph=8'hb0;
            4:glyph=8'h99;5:glyph=8'h92;6:glyph=8'h82;7:glyph=8'hf8;
            8:glyph=8'h80;9:glyph=8'h90;10:glyph=8'h88;11:glyph=8'h83;
            12:glyph=8'hc6;13:glyph=8'ha1;14:glyph=8'h86;15:glyph=8'h8e;
        endcase end
    endfunction
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin meta<=0;sync<=0;ticks<=0;digit<=0;seg_sel<=6'b111111;seg_data<=8'hff;end
        else begin
            meta<=digits;sync<=meta;ticks<=ticks+1'b1;
            if(ticks==49999)begin ticks<=0;digit<=(digit==5)?0:digit+1'b1;end
            seg_sel<=~(6'b000001<<digit);seg_data<=glyph((sync>>(digit*4))&15);
        end
    end
endmodule
