`timescale 1ns/1ps
module tb_memory_port;
    reg clk=0;always #5 clk=~clk;reg rst_n=0,wv=0,lv=0;
    wire wr,rsp,rerr,lr,pv,ld,le,aw,ar;wire [9:0] pi;wire [23:0] pd;wire [20:0] wa,ra;wire [31:0] wd;
    reg [31:0] memory[0:31];reg [31:0] ticks=0;reg [4:0] pipe=0;reg [31:0] pipe_data[0:4];
    string mode;integer writes=0;reg suppress_response=0,corrupt_readback=0;
    team_sdram_port #(.LINE_WIDTH(8),.SETTLE_CYCLES(32),.TIMEOUT_CYCLES(64)) dut(
        .clk(clk),.rst_n(rst_n),.mem_initialized(1'b1),.mem_busy(1'b0),.mem_refresh(1'b0),
        .wr_valid(wv),.wr_ready(wr),.wr_addr(21'd7),.wr_data(32'h12345678),.wr_rsp_valid(rsp),.wr_rsp_error(rerr),
        .line_valid(lv),.line_ready(lr),.line_addr(21'd0),.line_pixel_valid(pv),.line_pixel_index(pi),.line_pixel_data(pd),.line_done(ld),.line_error(le),
        .app_wr_en(aw),.app_wr_addr(wa),.app_wr_data(wd),.app_rd_en(ar),.app_rd_addr(ra),
        .mem_rd_valid(pipe[4]&&!suppress_response),.mem_rd_data(pipe_data[4]));
    always @(posedge clk)if(rst_n)begin
        ticks<=ticks+1;pipe<={pipe[3:0],ar};pipe_data[0]<=memory[ra]^(corrupt_readback?1:0);
        for(integer i=1;i<5;i++)pipe_data[i]<=pipe_data[i-1];
        if(aw)begin memory[wa]<=wd;writes=writes+1;end
    end
    initial begin
        if(!$value$plusargs("MODE=%s",mode))mode="memory_ok";
        suppress_response=(mode=="memory_timeout"||mode=="line_timeout");corrupt_readback=(mode=="memory_bad_readback");
        for(integer i=0;i<32;i++)memory[i]=i;
        repeat(4)@(negedge clk);rst_n=1;
        if(mode=="line_timeout")begin
            lv=1;@(negedge clk);lv=0;wait(ld);if(!le)$fatal(1,"line timeout not reported");
        end else begin
            wv=1;@(negedge clk);wv=0;wait(rsp);
            if(writes!=1||ticks<35||rerr!=(mode!="memory_ok"))$fatal(1,"write acknowledgment before verification/incorrect error");
        end
        if(mode=="memory_timeout"||mode=="line_timeout")begin repeat(10)@(negedge clk);if(wr||lr)$fatal(1,"late responses can contaminate later job");end
        $display("TEST_PASS mode=%s writes=%0d verified_response_or_fault=1",mode,writes);$finish;
    end
    initial begin #20000;$fatal(1,"memory port watchdog");end
endmodule
