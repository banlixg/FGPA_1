`timescale 1ns/1ps
module tb_team_fade_ctrl;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,frame_tick=0,request_valid=0;
    reg [1:0] request_slot=1;
    reg request_slot_valid=1,effect_enable=1;
    reg [8:0] request_step=8;
    reg abort_transition=0;
    wire request_ready,switch_valid;
    reg switch_ready=0;
    wire [1:0] switch_slot;wire [31:0] switch_token;wire switch_cancel;
    reg reply_valid=0;reg [31:0] reply_token=0;reg [1:0] reply_slot=0;reg reply_error=0;
    reg recover_valid=0;wire recover_ready;reg [1:0] recover_slot=0;
    wire [8:0] gain;wire busy,fault,blackout,done,failed;
    wire [1:0] result_slot;wire [3:0] error_code;wire [2:0] phase;
    team_fade_ctrl #(.WATCHDOG_CYCLES(400)) dut(.*);
    reg frames_on=1;
    integer cycle=0,tick_cycle=0,zero_at=-1000,accepted=0,done_count=0,failed_count=0;
    integer checks=0,out_steps=0,in_steps=0,expected_step=8,expected_gain;
    reg enabled_job=1,held=0;reg [1:0] held_slot;reg [31:0] held_token;
    reg [8:0] previous_gain=256;
    reg [2:0] previous_phase=0;
    string mode;integer chosen_step;
    always @(negedge clk) begin
        tick_cycle=tick_cycle+1;
        frame_tick=rst_n && frames_on && (tick_cycle%11==0);
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            accepted=0;held=0;enabled_job=1;cycle=0;expected_step=8;
        end else begin
            cycle=cycle+1;
            if(request_valid && request_ready) begin
                enabled_job=effect_enable;
                expected_step=(request_step==0)?8:((request_step>256)?256:request_step);
            end
            if(held && !switch_cancel &&
               (!switch_valid || switch_slot!==held_slot || switch_token!==held_token))
                $fatal(1,"switch command changed while backpressured");
            held=switch_valid && !switch_ready;
            if(held) begin held_slot=switch_slot;held_token=switch_token;end
            if(switch_valid && switch_ready) begin
                accepted=accepted+1;
                if(enabled_job && (gain!=0 || cycle-zero_at<11))
                    $fatal(1,"switch before a complete black frame");
            end
        end
        #1;
        if(!rst_n) begin
            done_count=0;failed_count=0;previous_gain=256;previous_phase=0;
            out_steps=0;in_steps=0;
        end else begin
            if(gain!=previous_gain && !frame_tick && !fault) $fatal(1,"gain changed inside a frame");
            if(gain>256) $fatal(1,"gain overflow");
            if(!fault && frame_tick && previous_phase==1) begin
                expected_gain=(previous_gain>expected_step)?previous_gain-expected_step:0;
                if(gain!=expected_gain) $fatal(1,"incorrect fade-out step");
            end
            if(!fault && frame_tick && previous_phase==5) begin
                expected_gain=(previous_gain+expected_step>256)?256:previous_gain+expected_step;
                if(gain!=expected_gain) $fatal(1,"incorrect fade-in step");
            end
            if(gain==0 && previous_gain!=0) zero_at=cycle;
            if(gain<previous_gain && !fault) out_steps=out_steps+1;
            if(gain>previous_gain && !fault) in_steps=in_steps+1;
            if(request_ready && busy) $fatal(1,"ready while busy");
            if(fault && (gain!=0 || request_ready)) $fatal(1,"unsafe fault state");
            if(done) done_count=done_count+1;
            if(failed) failed_count=failed_count+1;
            previous_gain=gain;previous_phase=phase;checks=checks+1;
        end
    end
    task reset_all;
        begin
            @(negedge clk);rst_n=0;request_valid=0;reply_valid=0;switch_ready=0;
            abort_transition=0;recover_valid=0;frames_on=1;
            repeat(4) @(negedge clk);rst_n=1;
        end
    endtask
    task offer(input [1:0] slot,input bit valid_slot,input bit enable,input integer amount);
        begin
            @(negedge clk);while(!request_ready) @(negedge clk);
            request_slot=slot;request_slot_valid=valid_slot;effect_enable=enable;request_step=amount;
            request_valid=1;@(negedge clk);request_valid=0;
        end
    endtask
    task accept_switch(input bit immediate_reply);
        begin
            while(!switch_valid) @(negedge clk);
            repeat(17) @(negedge clk);
            switch_ready=1;
            if(immediate_reply) begin
                reply_valid=1;reply_token=switch_token;reply_slot=switch_slot;reply_error=0;
            end
            @(negedge clk);switch_ready=0;reply_valid=0;
        end
    endtask
    task send_reply(input [31:0] token,input [1:0] slot,input bit bad);
        begin
            @(negedge clk);reply_valid=1;reply_token=token;reply_slot=slot;reply_error=bad;
            @(negedge clk);reply_valid=0;
        end
    endtask
    task finish_ok(input integer number,input [1:0] slot);
        begin
            while(busy) @(negedge clk);
            repeat(2) @(negedge clk);
            if(gain!=256 || done_count!=number || failed_count!=0 || error_code!=0 || result_slot!=slot)
                $fatal(1,"normal completion mismatch done=%0d failed=%0d code=%0d",done_count,failed_count,error_code);
        end
    endtask
    task expect_fault(input integer code);
        begin
            while(!fault) @(negedge clk);
            if(error_code!=code || failed_count!=1 || done_count!=0) $fatal(1,"wrong fault %0d expected=%0d",error_code,code);
            repeat(18) begin
                @(negedge clk);if(!busy || request_ready || gain!=0) $fatal(1,"fault silently released");
            end
        end
    endtask
    initial begin
        if(!$value$plusargs("MODE=%s",mode)) mode="normal_step8";
        reset_all();chosen_step=8;
        if(mode=="normal_step7") chosen_step=7;
        if(mode=="normal_step1") chosen_step=1;
        if(mode=="normal_step0") chosen_step=0;
        if(mode=="normal_step256") chosen_step=256;
        if(mode=="normal_step511") chosen_step=511;
        if(mode=="invalid_target") begin
            offer(3,0,1,8);repeat(3) @(negedge clk);
            if(busy || gain!=256 || accepted!=0 || error_code!=1 || done_count!=1 || failed_count!=1)
                $fatal(1,"invalid slot was not rejected safely");
        end else if(mode=="request_timeout") begin
            offer(1,1,1,8);expect_fault(3);
        end else if(mode=="missing_frame_tick") begin
            frames_on=0;offer(1,1,1,8);expect_fault(2);
        end else if(mode=="reply_timeout" || mode=="fault_recovery") begin
            offer(1,1,1,8);accept_switch(0);expect_fault(3);
            if(mode=="fault_recovery") begin
                send_reply(switch_token,1,0); // Late success cannot clear FAULT.
                if(!fault) $fatal(1,"late reply cleared fault");
                @(negedge clk);recover_slot=2;recover_valid=1;
                @(negedge clk);recover_valid=0;
                while(busy) @(negedge clk);
                if(gain!=256 || result_slot!=2 || error_code!=3 || done_count!=1 || failed_count!=1)
                    $fatal(1,"recovery erased error or restored wrong frame");
            end
        end else if(mode=="reply_error" || mode=="wrong_slot") begin
            offer(1,1,1,8);accept_switch(0);
            send_reply(switch_token,(mode=="wrong_slot")?2:1,mode=="reply_error");
            expect_fault((mode=="wrong_slot")?4:5);
        end else if(mode=="missing_frame_after_reply") begin
            offer(1,1,1,8);accept_switch(0);frames_on=0;
            send_reply(switch_token,1,0);expect_fault(2);
        end else if(mode=="abort_out" || mode=="abort_issue" || mode=="abort_wait" || mode=="abort_in") begin
            offer(1,1,1,8);
            if(mode=="abort_out") begin while(gain==256) @(negedge clk);end
            else if(mode=="abort_issue") begin while(!switch_valid) @(negedge clk);end
            else begin
                accept_switch(0);
                if(mode=="abort_in") begin
                    send_reply(switch_token,1,0);
                    while(phase!=5) @(negedge clk);
                end
            end
            @(negedge clk);abort_transition=1;@(negedge clk);abort_transition=0;expect_fault(6);
        end else if(mode=="reset_out" || mode=="reset_wait") begin
            offer(1,1,1,8);
            if(mode=="reset_wait") accept_switch(0);
            else while(gain==256) @(negedge clk);
            reset_all();
            if(busy || gain!=256 || switch_valid || error_code!=0) $fatal(1,"reset state");
            offer(2,1,1,16);accept_switch(0);send_reply(switch_token,2,0);finish_ok(1,2);
        end else begin
            offer(1,1,mode!="disabled",chosen_step);
            if(mode=="latched_config") begin
                // Changing future config/target during a transition has no effect.
                request_step=256;effect_enable=0;request_slot=3;request_slot_valid=0;
            end
            accept_switch(mode=="immediate_reply");
            if(mode=="stale_reply_then_correct") begin
                send_reply(switch_token-1,1,0);
                repeat(37) begin @(negedge clk);if(gain!=0 || !busy) $fatal(1,"stale reply accepted");end
            end
            if(mode=="delayed_reply") begin
                repeat(80) begin @(negedge clk);if(gain!=0 || !busy) $fatal(1,"faded in before confirmation");end
            end
            if(mode!="immediate_reply") send_reply(switch_token,1,0);
            if(mode=="queued_request") begin
                reg [31:0] old_token;
                old_token=switch_token;
                @(negedge clk);request_valid=1;request_slot=3;request_slot_valid=1;
                effect_enable=1;request_step=16;
                // Sender holds the next command while ready is low. It must be
                // accepted once, only after the first transition finishes.
                while(switch_token==old_token) @(negedge clk);
                request_valid=0;
                if(done_count!=1) $fatal(1,"new job accepted before old completion");
                accept_switch(0);send_reply(switch_token,3,0);finish_ok(2,3);
                if(accepted!=2) $fatal(1,"queued command accepted more than once");
            end else finish_ok(1,1);
            if(mode=="latched_config" && (out_steps!=32 || in_steps!=32)) $fatal(1,"config not latched");
            if(mode=="repeat_two") begin
                reg [31:0] old_token;
                old_token=switch_token;
                offer(3,1,1,7);accept_switch(0);
                if(switch_token==old_token) $fatal(1,"token did not advance");
                send_reply(old_token,1,0);repeat(25) @(negedge clk);
                if(gain!=0) $fatal(1,"previous reply released next transition");
                send_reply(switch_token,3,0);finish_ok(2,3);
            end
        end
        $display("TEST_PASS ctrl mode=%s checks=%0d accepted=%0d fade_out_steps=%0d fade_in_steps=%0d",mode,checks,accepted,out_steps,in_steps);
        $finish;
    end
    initial begin #3000000;$fatal(1,"control watchdog mode=%s",mode);end
endmodule
