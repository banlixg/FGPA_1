`timescale 1ns/1ps
module tb_team_fade_rgb;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0;
    reg [8:0] gain=256;
    reg [23:0] in_rgb=0;
    reg in_hs=0,in_vs=0,in_de=0;
    reg [15:0] in_x=0,in_y=0;
    wire [23:0] out_rgb;wire out_hs,out_vs,out_de;wire [15:0] out_x,out_y;
    team_fade_rgb dut(.*);
    reg [23:0] expected_rgb=0;
    reg [34:0] expected_meta=0;
    integer checks=0,seed=32'h532879a1,g,c;
    function [23:0] reference_rgb(input [23:0] rgb,input integer level,input bit de);
        integer r,gg,b,limited;
        begin
            limited=(level>256)?256:level;
            r=(rgb[23:16]*limited+128)/256;
            gg=(rgb[15:8]*limited+128)/256;
            b=(rgb[7:0]*limited+128)/256;
            reference_rgb=de ? {r[7:0],gg[7:0],b[7:0]} : 24'd0;
        end
    endfunction
    always @(posedge clk) begin : scoreboard
        reg [23:0] next_rgb;
        reg [34:0] next_meta;
        next_rgb=reference_rgb(in_rgb,gain,in_de);
        next_meta={in_hs,in_vs,in_de,in_x,in_y};
        #1;
        if(!rst_n) begin
            if(out_rgb!==0 || {out_hs,out_vs,out_de,out_x,out_y}!==0) $fatal(1,"reset output");
            expected_rgb=0;expected_meta=0;
        end else begin
            if(out_rgb!==expected_rgb || {out_hs,out_vs,out_de,out_x,out_y}!==expected_meta)
                $fatal(1,"two-register RGB/metadata mismatch got=%h expected=%h",out_rgb,expected_rgb);
            expected_rgb=next_rgb;expected_meta=next_meta;checks=checks+1;
        end
    end
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        for(g=0;g<512;g=g+1) begin
            for(c=0;c<256;c=c+1) begin
                @(negedge clk);gain=g;in_rgb={8'(c),8'(255-c),8'((c*73+g)&255)};
                in_de=1;in_hs=c[0];in_vs=g[0];in_x=c;in_y=g;
            end
        end
        for(c=0;c<4096;c=c+1) begin
            @(negedge clk);in_rgb=$random(seed);gain=$random(seed);
            {in_hs,in_vs,in_de}=$random(seed);in_x=$random(seed);in_y=$random(seed);
        end
        // Flush mid-stream. No pre-reset colour/sync may leak into the new run.
        @(negedge clk);rst_n=0;
        repeat(3) @(negedge clk);rst_n=1;
        repeat(12) @(negedge clk);
        $display("TEST_PASS rgb exhaustive_gains=512 channel_values=256 checks=%0d",checks);
        $finish;
    end
endmodule
