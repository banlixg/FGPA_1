// KEY2 next, KEY4 auto on/off, KEY3 cycles 2/5/10 seconds (frame periods).
// One coalesced manual request while busy; long holds produce one event only.
module team_key_event #(parameter STABLE_CYCLES=250000)(
    input wire clk,rst_n,key_n,output reg pressed
);
    reg meta,sync,stable;reg [31:0] ticks;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin meta<=1;sync<=1;stable<=1;ticks<=0;pressed<=0;end
        else begin
            meta<=key_n;sync<=meta;pressed<=0;
            if(sync==stable)ticks<=0;
            else if(ticks+1>=STABLE_CYCLES)begin stable<=sync;ticks<=0;pressed<=!sync;end
            else ticks<=ticks+1'b1;
        end
    end
endmodule

module team_player_control #(parameter DEBOUNCE_CYCLES=250000)(
    input wire clk,rst_n,frame_tick,next_key_n,auto_key_n,period_key_n,
    input wire active_valid,input wire [1:0] active_slot,input wire [3:0] resident_mask,
    input wire request_ready,output wire request_valid,output reg [1:0] request_slot,
    output reg auto_play,output reg [1:0] period_setting,
    output wire [9:0] period_frames
);
    wire next_event,auto_event,period_event;reg pending;reg [9:0] elapsed;
    reg found;integer i;reg [1:0] candidate;
    team_key_event #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) kn(clk,rst_n,next_key_n,next_event);
    team_key_event #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) ka(clk,rst_n,auto_key_n,auto_event);
    team_key_event #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) kp(clk,rst_n,period_key_n,period_event);
    assign period_frames=(period_setting==0)?10'd120:(period_setting==1)?10'd300:10'd600;
    assign request_valid=pending&&active_valid&&found;
    always @*begin
        request_slot=active_slot;found=0;candidate=0;
        for(i=1;i<=3;i=i+1)begin
            candidate=active_slot+i;
            if(!found&&resident_mask[candidate])begin request_slot=candidate;found=1;end
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin auto_play<=0;period_setting<=1;pending<=0;elapsed<=0;end
        else begin
            if(request_valid&&request_ready)begin pending<=0;elapsed<=0;end
            if(next_event&&active_valid)pending<=1;
            if(auto_event)begin auto_play<=!auto_play;elapsed<=0;end
            if(period_event)begin period_setting<=(period_setting==2)?0:period_setting+1'b1;elapsed<=0;end
            if(frame_tick&&active_valid&&auto_play&&!auto_event&&!period_event)begin
                if(elapsed+1>=period_frames)begin elapsed<=0;pending<=1;end
                else elapsed<=elapsed+1'b1;
            end
        end
    end
endmodule
