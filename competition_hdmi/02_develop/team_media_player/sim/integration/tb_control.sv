`timescale 1ns/1ps
module tb_control;
    reg clk=0;always #5 clk=~clk;reg rst_n=0,nk=1,ak=1,pk=1,ready=1;
    reg [1:0] slot=0;wire rv,auto_play;wire [1:0] target,period;wire [9:0] pf;
    integer cycles=0,requests=0;wire ft=(cycles%5==0);
    team_player_control #(.DEBOUNCE_CYCLES(3)) dut(
        .clk(clk),.rst_n(rst_n),.frame_tick(ft),.next_key_n(nk),.auto_key_n(ak),.period_key_n(pk),
        .active_valid(1'b1),.active_slot(slot),.resident_mask(4'b1011),.request_ready(ready),
        .request_valid(rv),.request_slot(target),.auto_play(auto_play),.period_setting(period),.period_frames(pf));
    always @(posedge clk)if(rst_n)begin
        cycles<=cycles+1;
        if(rv&&ready)begin if(target==2||target==slot)$fatal(1,"invalid frame chosen");slot<=target;requests=requests+1;end
    end
    task next_press;begin nk=0;repeat(9)@(negedge clk);nk=1;repeat(9)@(negedge clk);end endtask
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        repeat(5)begin nk=0;@(negedge clk);nk=1;@(negedge clk);end
        repeat(10)@(negedge clk);if(requests)$fatal(1,"bounce accepted");
        nk=0;repeat(100)@(negedge clk);nk=1;repeat(10)@(negedge clk);
        if(requests!=1||slot!=1)$fatal(1,"long hold repeated");
        ready=0;next_press();next_press();if(requests!=1)$fatal(1,"busy request escaped");
        ready=1;repeat(10)@(negedge clk);if(requests!=2||slot!=3)$fatal(1,"coalesced request");
        for(integer i=0;i<2;i++)begin pk=0;repeat(9)@(negedge clk);pk=1;repeat(9)@(negedge clk);end
        if(pf!=120||period!=0)$fatal(1,"period configuration");
        ak=0;repeat(100)@(negedge clk);ak=1;repeat(10)@(negedge clk);if(!auto_play)$fatal(1,"auto long press toggled twice");
        wait(requests==3);@(negedge clk);ak=0;repeat(9)@(negedge clk);ak=1;repeat(9)@(negedge clk);
        if(auto_play)$fatal(1,"auto stop");repeat(1300)@(negedge clk);if(requests!=3)$fatal(1,"auto did not stop");
        $display("TEST_PASS controls bounce long_hold coalesce sparse_slots period auto_start_stop requests=%0d",requests);$finish;
    end
    initial begin #200000;$fatal(1,"control watchdog");end
endmodule
