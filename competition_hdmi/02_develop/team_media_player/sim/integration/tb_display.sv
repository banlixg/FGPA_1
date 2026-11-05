`timescale 1ns/1ps
module tb_display;
    parameter WIDTH=31,HEIGHT=17,HTOTAL=48,VTOTAL=24;
    reg mc=0,vc=0;always #10 mc=~mc;always #20 vc=~vc;
    reg rst_n=0;wire lv,lr,lpv,ld,le;wire [20:0] la;wire [9:0] pi;wire [23:0] pd;
    wire ar,aw;wire [20:0] ra,wa;wire [31:0] wd;
    reg [8:0] valid_pipe=0;reg [31:0] data_pipe[0:8];integer cycles=0;
    wire refresh=(cycles%521)<27;
    wire [23:0] rgb;wire hs,vs,de;wire [15:0] x,y;wire ft,reply;wire [31:0] rt,underruns;wire [1:0] rs,slot;
    wire reply_error,active,sready;
    reg switch_valid=0;reg [1:0] target=0;reg [31:0] token=0;
    string mode;integer checks=0,frames=0,replies=0;
    function [23:0] pixel(input integer address);
        integer s,xx,yy;begin s=address/(WIDTH*HEIGHT);xx=(address% (WIDTH*HEIGHT))%WIDTH;yy=(address%(WIDTH*HEIGHT))/WIDTH;
            pixel={8'(s*53+xx*17+yy),8'(s*31+yy*29+xx),8'(s*101+xx*7+yy*11)};end
    endfunction
    team_sdram_port #(.LINE_WIDTH(WIDTH)) port(
        .clk(mc),.rst_n(rst_n),.mem_initialized(1'b1),.mem_busy(refresh),.mem_refresh(refresh),
        .wr_valid(1'b0),.wr_ready(),.wr_addr(21'd0),.wr_data(32'd0),.wr_rsp_valid(),.wr_rsp_error(),
        .line_valid(lv),.line_ready(lr),.line_addr(la),.line_pixel_valid(lpv),.line_pixel_index(pi),.line_pixel_data(pd),
        .line_done(ld),.line_error(le),.app_wr_en(aw),.app_wr_addr(wa),.app_wr_data(wd),.app_rd_en(ar),.app_rd_addr(ra),
        .mem_rd_valid(valid_pipe[8]),.mem_rd_data(data_pipe[8]));
    team_line_scanout #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.HTOTAL(HTOTAL),.VTOTAL(VTOTAL),.HFP(2),.HSA(3),.VFP(2),.VSA(2)) dut(
        .video_clk(vc),.video_rst_n(rst_n),.mem_clk(mc),.mem_rst_n(rst_n),.boot_finished(1'b1),.resident_mask(4'b1111),
        .switch_valid(switch_valid),.switch_ready(sready),.switch_slot(target),.switch_token(token),.switch_cancel(1'b0),
        .reply_valid(reply),.reply_slot(rs),.reply_token(rt),.reply_error(reply_error),.active_slot(slot),.active_valid(active),
        .frame_tick(ft),.rgb(rgb),.hs(hs),.vs(vs),.de(de),.x(x),.y(y),.underruns(underruns),
        .line_valid(lv),.line_ready(lr),.line_addr(la),.line_pixel_valid(lpv),.line_pixel_index(pi),.line_pixel_data(pd),.line_done(ld),.line_error(le));
    always @(posedge mc)begin
        cycles<=cycles+1;valid_pipe<={valid_pipe[7:0],ar};data_pipe[0]<={pixel(ra),8'd0};
        for(integer j=1;j<9;j++)data_pipe[j]<=data_pipe[j-1];
    end
    reg [1:0] old_slot=0;
    always @(negedge vc)if(rst_n)begin
        if(ft)frames=frames+1;
        if(de&&active)begin
            if(rgb!==pixel(slot*WIDTH*HEIGHT+y*WIDTH+x))$fatal(1,"scanout pixel mismatch slot=%0d x=%0d y=%0d got=%h expected=%h",slot,x,y,rgb,pixel(slot*WIDTH*HEIGHT+y*WIDTH+x));
            checks=checks+1;
        end
        if(old_slot!=slot&&de)$fatal(1,"mid-frame slot adoption");old_slot=slot;
        if(reply)begin
            if(rt!=token||rs!=target||reply_error||!dut.bank_valid[0]||dut.bank_slot0!=target)$fatal(1,"reply before prefetch ready");
            replies=replies+1;
        end
    end
    task select(input [1:0] s);
        begin wait(sready);@(negedge vc);target=s;token=token+1;switch_valid=1;@(negedge vc);switch_valid=0;
            wait(reply);repeat(2)@(negedge vc);end
    endtask
    initial begin
        if(!$value$plusargs("MODE=%s",mode))mode="display";
        repeat(4)@(negedge vc);rst_n=1;
        wait(active);wait(frames>=3);
        select(1);repeat(3)@(posedge ft);select(3);repeat(3)@(posedge ft);select(2);repeat(3)@(posedge ft);select(0);repeat(3)@(posedge ft);
        @(negedge vc);
        if(underruns||replies!=4||checks<WIDTH*HEIGHT*8)$fatal(1,"display totals underruns=%0d checks=%0d",underruns,checks);
        $display("TEST_PASS scanout_pixels=%0d changes=%0d refresh_windows=%0d underruns=%0d",checks,replies,cycles/521,underruns);$finish;
    end
    initial begin #2000000000;$fatal(1,"display watchdog");end
endmodule
