`timescale 1ns/1ps
module tb_core;
    parameter WIDTH=31,HEIGHT=17,HTOTAL=48,VTOTAL=24,MAX_LBA=6000;
    localparam N=WIDTH*HEIGHT;
    reg mc=0,vc=0;always #10 mc=~mc;always #20 vc=~vc;
    reg rst_n=0,next_key=1,auto_key=1,period_key=1;
    wire req,cancel,rr;wire [31:0] lba;reg sector_active=0;integer sector=0,pos=0,requests=0;
    reg [7:0] card[0:(MAX_LBA+1)*512-1];reg present[0:MAX_LBA];
    reg [55:0] pixels[0:4*N-1];reg [31:0] expected_mem[0:4*N-1],memory[0:4*N-1];
    wire aw,ar;wire [20:0] wa,ra;wire [31:0] wd;
    reg [8:0] read_pipe=0;reg [31:0] data_pipe[0:8];
    integer cycles=0,write_delay=0,writes=0;reg [20:0] pending_addr;reg [31:0] pending_data;
    wire refresh=(cycles%521)<27;
    wire [23:0] rgb,al,art;wire hs,vs,de,av,acr;wire [15:0] x,y;wire [19:0] an,cts;
    wire [3:0] bs,be,as,ae;wire [2:0] count;wire done,failed,visible,auto_play,fault;
    wire [1:0] slot,period;wire [31:0] vu,au;
    team_player_core #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.HTOTAL(HTOTAL),.VTOTAL(VTOTAL),
        .HFP(2),.HSA(3),.VFP(2),.VSA(2),.DEBOUNCE_CYCLES(3)) dut(
        .mem_clk(mc),.mem_rst_n(rst_n),.video_clk(vc),.video_rst_n(rst_n),.sd_initialized(1'b1),.sd_failed(1'b0),
        .next_key_n(next_key),.auto_key_n(auto_key),.period_key_n(period_key),
        .sd_req(req),.sd_cancel(cancel),.sd_req_ready(!sector_active),.sd_lba(lba),.sd_valid(sector_active),
        .sd_ready(rr),.sd_data(card[sector*512+pos]),.sd_last(pos==511),.sd_error(1'b0),
        .mem_initialized(1'b1),.mem_busy(refresh),.mem_refresh(refresh),.app_wr_en(aw),.app_wr_addr(wa),.app_wr_data(wd),
        .app_rd_en(ar),.app_rd_addr(ra),.mem_rd_valid(read_pipe[8]),.mem_rd_data(data_pipe[8]),
        .rgb(rgb),.hs(hs),.vs(vs),.de(de),.x(x),.y(y),.audio_valid(av),.audio_left(al),.audio_right(art),
        .acr_valid(acr),.acr_n(an),.acr_cts(cts),.boot_stage(bs),.boot_error(be),.audio_stage(as),.audio_error(ae),
        .image_count(count),.boot_done(done),.boot_failed(failed),.active_slot(slot),.active_valid(visible),
        .auto_play(auto_play),.period_setting(period),.fade_fault(fault),.video_underruns(vu),.audio_underruns(au));
    reg [31:0] samples[0:499];integer audio_count=0,video_count=0,frames=0;
    reg [23:0] exp_rgb;reg [8:0] gain_at_pixel;
    reg [23:0] rgb_pipe[0:1];reg [15:0] x_pipe[0:1],y_pipe[0:1];reg [1:0] de_pipe=0;
    function [7:0] scale(input [7:0] value,input [8:0] gain);integer n;begin n=value*gain+128;scale=n>>8;end endfunction
    // Compare the actual connected pixel pipeline, including fade gain and timing.
    always @(posedge vc)if(rst_n)begin
        gain_at_pixel=dut.fade.gain;
        exp_rgb=(dut.scanout.de&&visible)?expected_mem[slot*N+dut.scanout.y*WIDTH+dut.scanout.x][31:8]:0;
        rgb_pipe[0]<={scale(exp_rgb[23:16],gain_at_pixel),scale(exp_rgb[15:8],gain_at_pixel),scale(exp_rgb[7:0],gain_at_pixel)};
        rgb_pipe[1]<=rgb_pipe[0];x_pipe[0]<=dut.scanout.x;x_pipe[1]<=x_pipe[0];y_pipe[0]<=dut.scanout.y;y_pipe[1]<=y_pipe[0];
        de_pipe<={de_pipe[0],dut.scanout.de};
    end
    always @(posedge mc)if(rst_n)begin
        cycles<=cycles+1;
        if(cancel)sector_active<=0;
        else if(sector_active&&rr)begin if(pos==511)sector_active<=0;else pos<=pos+1;end
        else if(!sector_active&&req)begin
            if(lba>MAX_LBA||present[lba]!==1)$fatal(1,"unknown sector %0d",lba);
            sector<=lba;pos<=0;sector_active<=1;requests=requests+1;
        end
        if(write_delay>0)begin write_delay=write_delay-1;if(write_delay==0)memory[pending_addr]<=pending_data;end
        if(aw)begin
            if(write_delay||done||wd!==expected_mem[wa])$fatal(1,"memory write contract");
            pending_addr=wa;pending_data=wd;write_delay=20;writes=writes+1;
        end
        read_pipe<={read_pipe[7:0],ar};data_pipe[0]<=memory[ra];
        for(integer i=1;i<9;i++)data_pipe[i]<=data_pipe[i-1];
    end
    always @(negedge vc)if(rst_n)begin
        if(dut.frame_tick)frames=frames+1;
        if(de!==de_pipe[1]||x!==x_pipe[1]||y!==y_pipe[1])$fatal(1,"video timing alignment");
        if(de&&visible)begin
            if(rgb!==rgb_pipe[1])$fatal(1,"connected fade RGB mismatch xy=%0d,%0d got=%h expected=%h gain=%0d",x,y,rgb,rgb_pipe[1],dut.fade.gain);
            video_count=video_count+1;
        end
        if(av)begin
            if({al[23:8],art[23:8]}!==samples[audio_count%500]||al[7:0]||art[7:0])$fatal(1,"file PCM sample %0d",audio_count);
            audio_count=audio_count+1;
        end
        if(acr&&(an!=6144||cts!=25000))$fatal(1,"audio clock regeneration");
        if(fault||vu||au)$fatal(1,"runtime error video=%0d audio=%0d fade=%0d",vu,au,fault);
    end
    task press_next;
        begin @(negedge vc);next_key=0;repeat(12)@(negedge vc);next_key=1;repeat(12)@(negedge vc);end
    endtask
    string base;reg [55:0] p;
    initial begin
        if(!$value$plusargs("BASE=%s",base))$fatal(1,"BASE");
        $readmemh({base,"/card.hex"},card);$readmemh({base,"/present.hex"},present);$readmemh({base,"/pixels.hex"},pixels);$readmemh({base,"/samples.hex"},samples);
        for(integer i=0;i<2;i++)begin rgb_pipe[i]=0;x_pipe[i]=0;y_pipe[i]=0;end
        for(integer f=0;f<4;f++)for(integer i=0;i<N;i++)begin p=pixels[f*N+i];expected_mem[f*N+p[39:24]*WIDTH+p[55:40]]={p[23:0],8'd0};end
        repeat(4)@(negedge vc);rst_n=1;wait(done);
        if(failed||count!=4||be||writes!=4*N)$fatal(1,"boot failed");
        wait(visible);repeat(3)@(posedge dut.frame_tick);press_next();
        wait(slot==1);wait(!dut.fade.busy);repeat(3)@(posedge dut.frame_tick);
        press_next();wait(slot==2);wait(!dut.fade.busy);
        // Configurable period: default 5s -> 10s -> 2s; then auto advances once.
        @(negedge vc);period_key=0;repeat(12)@(negedge vc);period_key=1;repeat(12)@(negedge vc);
        @(negedge vc);period_key=0;repeat(12)@(negedge vc);period_key=1;repeat(12)@(negedge vc);
        if(period!=0)$fatal(1,"period key");
        auto_key=0;repeat(12)@(negedge vc);auto_key=1;repeat(12)@(negedge vc);wait(auto_play);
        wait(slot==3);auto_key=0;repeat(12)@(negedge vc);auto_key=1;repeat(12)@(negedge vc);
        wait(!dut.fade.busy);if(auto_play)$fatal(1,"auto stop");
        wait(audio_count>=1200);repeat(4)@(negedge vc);
        if(as==7||ae||video_count<8*N)$fatal(1,"end result");
        $display("TEST_PASS core frames=%0d boot_writes=%0d video_pixels=%0d PCM_samples=%0d sectors=%0d fade_switches=3 underruns=0",frames,writes,video_count,audio_count,requests);$finish;
    end
    initial begin #2000000000;$fatal(1,"core watchdog stage=%0d audio=%0d count=%0d",bs,as,audio_count);end
endmodule
