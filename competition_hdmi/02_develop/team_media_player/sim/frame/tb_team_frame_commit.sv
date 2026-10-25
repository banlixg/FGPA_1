`timescale 1ns/1ps
module tb_team_frame_commit;
    parameter SRC_HALF=3, VIDEO_HALF=7;
    reg src_clk=0, video_clk=0;
    always #(SRC_HALF) src_clk=~src_clk;
    always #(VIDEO_HALF) video_clk=~video_clk;
    reg src_rst_n=0,video_rst_n=0;
    reg select_valid=0;reg [1:0] select_slot=0;
    wire select_ready,select_done;
    reg frame_boundary=0,frames=0;
    wire active_valid,commit_pulse; wire [1:0] active_slot;
    integer tick=0,commits=0,acks=0,checks=0;
    reg previous_valid=0; reg [1:0] previous_slot=0;
    team_frame_commit_bridge dut(.*);
    always @(negedge video_clk) begin
        if(!video_rst_n) begin tick=0;frame_boundary=0;end
        else begin tick=tick+1;frame_boundary=frames && (tick%17==0);end
    end
    always @(posedge video_clk) begin
        #1;
        if(!video_rst_n) begin previous_valid=0;previous_slot=0;commits=0;end
        else begin
            if((active_slot!=previous_slot || active_valid!=previous_valid) && !commit_pulse)
                $fatal(1,"active frame changed outside commit");
            if(commit_pulse) begin
                if(!frame_boundary) $fatal(1,"commit outside frame boundary");
                commits=commits+1;
            end
            previous_slot=active_slot;previous_valid=active_valid;
        end
    end
    always @(posedge src_clk) begin
        #1;if(!src_rst_n) acks=0;else if(select_done) acks=acks+1;
    end
    task reset_both;
        begin
            @(negedge src_clk);src_rst_n=0;video_rst_n=0;select_valid=0;frames=0;
            repeat(5) @(negedge video_clk);
            @(negedge src_clk);src_rst_n=1;
            @(negedge video_clk);video_rst_n=1;
            repeat(3) @(negedge src_clk);
        end
    endtask
    task offer(input [1:0] slot);
        begin
            @(negedge src_clk);while(!select_ready) @(negedge src_clk);
            select_slot=slot;select_valid=1;
            @(negedge src_clk);select_valid=0;
            if(select_ready) $fatal(1,"request did not occupy mailbox");
        end
    endtask
    task await_ack(input integer number,input [1:0] slot);
        begin
            while(acks<number) @(negedge src_clk);
            if(!active_valid || active_slot!==slot || commits!=number)
                $fatal(1,"commit/ack mismatch commits=%0d acks=%0d slot=%0d",commits,acks,active_slot);
            checks=checks+1;
        end
    endtask
    initial begin
        reset_both();offer(2);
        // Payload input changes cannot overwrite an in-flight selection.
        select_slot=0;
        repeat(50) begin
            @(negedge video_clk);
            if(active_valid || select_ready || commits!=0 || acks!=0)
                $fatal(1,"selection applied or ACKed without boundary");
        end
        checks=checks+1;frames=1;await_ack(1,2);
        // Exercise many transfers across non-harmonic clock ratios.
        for(integer n=2;n<=130;n=n+1) begin
            offer((n*3+1)%4);await_ack(n,(n*3+1)%4);
        end
        frames=0;repeat(3) @(negedge video_clk);
        offer(1);repeat(8) @(negedge video_clk);
        reset_both();
        repeat(40) @(negedge video_clk);
        if(active_valid || commits!=0 || acks!=0 || !select_ready) $fatal(1,"phantom request after reset");
        frames=1;offer(3);await_ack(1,3);
        $display("TEST_PASS bridge src_half=%0d video_half=%0d checks=%0d",SRC_HALF,VIDEO_HALF,checks);
        $finish;
    end
    initial begin #2000000;$fatal(1,"bridge watchdog");end
endmodule
