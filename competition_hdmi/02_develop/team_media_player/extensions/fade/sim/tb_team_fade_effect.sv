`timescale 1ns/1ps
module tb_team_fade_effect;
    parameter WIDTH=160,HEIGHT=120,FRAMES=75,STEP=8,CAPTURE=1;
    localparam HTOTAL=(WIDTH==640)?800:WIDTH+8;
    localparam VTOTAL=(HEIGHT==480)?525:HEIGHT+4;
    localparam XSTART=(WIDTH==640)?144:4;
    localparam YSTART=(HEIGHT==480)?35:2;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,frame_tick=0,request_valid=0;
    wire request_ready;
    reg [1:0] request_slot=1;
    reg request_slot_valid=1,effect_enable=1;
    reg [8:0] request_step=STEP;
    reg abort_transition=0;
    wire switch_valid;reg switch_ready=1;
    wire [1:0] switch_slot;wire [31:0] switch_token;wire switch_cancel;
    reg reply_valid=0;reg [31:0] reply_token=0;reg [1:0] reply_slot=0;reg reply_error=0;
    reg recover_valid=0;wire recover_ready;reg [1:0] recover_slot=0;
    reg [23:0] in_rgb=0;
    reg in_hs=0,in_vs=0,in_de=0;
    reg [15:0] in_x=0,in_y=0;
    wire [23:0] out_rgb;wire out_hs,out_vs,out_de;wire [15:0] out_x,out_y;
    wire [8:0] gain;wire busy,fault,blackout,done,failed;
    wire [1:0] result_slot;wire [3:0] error_code;wire [2:0] phase;
    team_fade_effect #(.WATCHDOG_CYCLES(HTOTAL*VTOTAL*5)) dut(.*);
    integer display_slot=0,pending_frames=0;
    reg pending=0;reg [1:0] pending_slot;reg [31:0] pending_token;
    integer switches=0,done_count=0,checks=0,visible=0,frame_index=0;
    integer raw_fd=0,meta_fd=0;
    string raw_path,meta_path;
    reg [23:0] expected_rgb=0;
    reg [34:0] expected_meta=0;
    reg expected_new=0;
    function [23:0] source_rgb(input integer x,input integer y,input integer slot);
        integer r,g,b;
        begin
            if(slot==0) begin
                r=64+(x*191)/(WIDTH-1);g=32+(y*160)/(HEIGHT-1);b=40+(((x/12)^(y/12))&1)*100;
            end else begin
                r=20+(((x/10+y/10)&1)*150);g=100+(x*155)/(WIDTH-1);b=80+(y*175)/(HEIGHT-1);
            end
            source_rgb={r[7:0],g[7:0],b[7:0]};
        end
    endfunction
    function [23:0] scaled(input [23:0] rgb,input integer amount,input bit de);
        integer r,g,b;
        begin
            r=(rgb[23:16]*amount+128)/256;g=(rgb[15:8]*amount+128)/256;b=(rgb[7:0]*amount+128)/256;
            scaled=de ? {r[7:0],g[7:0],b[7:0]} : 24'd0;
        end
    endfunction
    // Model commit delay + old-FIFO drain. Raw request acceptance is NOT reply.
    always @(posedge clk) begin
        reply_valid<=0;
        if(!rst_n) begin pending<=0;display_slot<=0;switches<=0;end
        else begin
            if(switch_valid && switch_ready) begin
                if(pending || gain!=0) $fatal(1,"unsafe backend request");
                pending<=1;pending_frames<=2;pending_slot<=switch_slot;pending_token<=switch_token;
                switches<=switches+1;
            end
            if(frame_tick && pending) begin
                if(pending_frames!=0) pending_frames<=pending_frames-1;
                else begin
                    display_slot<=pending_slot;pending<=0;
                    reply_valid<=1;reply_token<=pending_token;reply_slot<=pending_slot;
                end
            end
            if(switch_cancel) pending<=0;
        end
    end
    always @(posedge clk) begin : scoreboard
        reg [23:0] next_rgb;reg [34:0] next_meta;reg next_new;
        next_rgb=scaled(in_rgb,gain,in_de);next_meta={in_hs,in_vs,in_de,in_x,in_y};
        next_new=(display_slot==1);
        #1;
        if(!rst_n) begin expected_rgb=0;expected_meta=0;expected_new=0;end
        else begin
            if(out_rgb!==expected_rgb || {out_hs,out_vs,out_de,out_x,out_y}!==expected_meta)
                $fatal(1,"integrated pixel/sync mismatch frame=%0d x=%0d y=%0d",frame_index,out_x,out_y);
            expected_rgb=next_rgb;expected_meta=next_meta;expected_new=next_new;checks=checks+1;
            if(out_de) begin
                visible=visible+1;
                if(CAPTURE) $fwrite(raw_fd,"%c%c%c",out_rgb[23:16],out_rgb[15:8],out_rgb[7:0]);
                if(out_x==0 && out_y==0 && CAPTURE) $fwrite(meta_fd,"%0d %0d %0d %0d\n",frame_index,gain,phase,display_slot);
            end
            if(done) done_count=done_count+1;
            if(fault || failed) $fatal(1,"unexpected integrated failure %0d",error_code);
        end
    end
    initial begin
        if(CAPTURE) begin
            if(!$value$plusargs("RAW=%s",raw_path) || !$value$plusargs("META=%s",meta_path)) $fatal(1,"capture paths missing");
            raw_fd=$fopen(raw_path,"wb");meta_fd=$fopen(meta_path,"w");
            if(!raw_fd || !meta_fd) $fatal(1,"capture open failed");
        end
        repeat(4) @(negedge clk);rst_n=1;
        for(frame_index=0;frame_index<FRAMES;frame_index=frame_index+1) begin
            for(integer y=0;y<VTOTAL;y=y+1) begin
                for(integer x=0;x<HTOTAL;x=x+1) begin
                    @(negedge clk);
                    frame_tick=(x==0 && y==0);
                    request_valid=(frame_index==2 && x==0 && y==0);
                    in_hs=(x>=2);in_vs=(y>=1);
                    in_de=(x>=XSTART && x<XSTART+WIDTH && y>=YSTART && y<YSTART+HEIGHT);
                    in_x=in_de ? x-XSTART : 0;in_y=in_de ? y-YSTART : 0;
                    in_rgb=in_de ? source_rgb(in_x,in_y,display_slot) : 24'd0;
                end
            end
        end
        @(negedge clk);in_de=0;frame_tick=0;request_valid=0;
        repeat(4) @(negedge clk);
        if(visible!=WIDTH*HEIGHT*FRAMES || done_count!=1 || switches!=1 || busy || gain!=256 || display_slot!=1)
            $fatal(1,"integrated completion visible=%0d expected=%0d done=%0d",visible,WIDTH*HEIGHT*FRAMES,done_count);
        if(CAPTURE) begin $fclose(raw_fd);$fclose(meta_fd);end
        $display("TEST_PASS integrated width=%0d height=%0d frames=%0d visible_pixels=%0d checks=%0d",WIDTH,HEIGHT,FRAMES,visible,checks);
        $finish;
    end
    initial begin #2000000000;$fatal(1,"integrated watchdog");end
endmodule
