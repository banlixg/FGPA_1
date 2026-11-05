`timescale 1ns/1ps
module tb_pcm;
    reg wc=0,rc=0;always #4 wc=~wc;always #20 rc=~rc;
    reg rst_n=0;integer written=0,read=0,ticks=0,last_tick=0,acrs=0;
    wire ready,empty,pop,av,acr;wire [31:0] data;wire [11:0] level;wire [23:0] left,right;wire [19:0] n,cts;wire [31:0] underruns;
    function [31:0] value(input integer i);value={16'(i*101+16'h8000),16'(i*317+16'hf000)};endfunction
    team_pcm_fifo fifo(.wr_clk(wc),.wr_rst_n(rst_n),.wr_valid(written<6000),.wr_ready(ready),.wr_data(value(written)),
        .rd_clk(rc),.rd_rst_n(rst_n),.rd_enable(pop),.rd_data(data),.empty(empty),.rd_level(level));
    team_pcm_hdmi dut(.clk(rc),.rst_n(rst_n),.fifo_data(data),.fifo_empty(empty),.fifo_level(level),.fifo_read(pop),
        .audio_valid(av),.audio_left(left),.audio_right(right),.acr_valid(acr),.acr_n(n),.acr_cts(cts),.underruns(underruns));
    always @(posedge wc)if(rst_n&&written<6000&&ready)written<=written+1;
    always @(negedge rc)if(rst_n)begin
        ticks=ticks+1;
        if(av)begin
            if({left[23:8],right[23:8]}!==value(read)||left[7:0]||right[7:0])$fatal(1,"PCM order %0d got=%h %h",read,left,right);
            if(read>0&&(ticks-last_tick!=520&&ticks-last_tick!=521))$fatal(1,"sample interval %0d",ticks-last_tick);
            last_tick=ticks;read=read+1;
        end
        if(acr)begin acrs=acrs+1;if(!av||read%48!=0||n!=6144||cts!=25000)$fatal(1,"ACR contract");end
        if(read==5000)begin
            if(underruns||acrs!=5000/48)$fatal(1,"PCM underflow/ACR count");
            $display("TEST_PASS PCM samples=%0d ACR=%0d underruns=0",read,acrs);$finish;
        end
    end
    initial begin repeat(4)@(negedge rc);rst_n=1;end
    initial begin #200000000;$fatal(1,"PCM watchdog");end
endmodule
