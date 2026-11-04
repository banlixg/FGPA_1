// Own two-line display architecture: bundled-data mailbox + dual-clock line RAM.
// No asynchronous FIFO flush, no double-buffer image load/display ownership.
module team_line_scanout #(
    parameter WIDTH=640,HEIGHT=480,HTOTAL=800,VTOTAL=525,
    parameter HFP=16,HSA=96,VFP=10,VSA=2,ADDR_BITS=21
)(
    input wire video_clk,video_rst_n,mem_clk,mem_rst_n,
    input wire boot_finished,input wire [3:0] resident_mask,
    input wire switch_valid,output wire switch_ready,
    input wire [1:0] switch_slot,input wire [31:0] switch_token,
    input wire switch_cancel,
    output reg reply_valid,output reg [1:0] reply_slot,
    output reg [31:0] reply_token,output reg reply_error,
    output reg [1:0] active_slot,output reg active_valid,
    output wire frame_tick,
    output wire [23:0] rgb,output reg hs,vs,de,
    output reg [15:0] x,y,
    output reg [31:0] underruns,
    output wire line_valid,input wire line_ready,
    output wire [ADDR_BITS-1:0] line_addr,
    input wire line_pixel_valid,input wire [9:0] line_pixel_index,
    input wire [23:0] line_pixel_data,input wire line_done,line_error
);
    reg [11:0] hc,vc;
    assign frame_tick=(hc==0 && vc==HEIGHT);
    reg boot1,boot2;reg [3:0] mask1,mask2;
    reg req_toggle;reg [8:0] req_row;reg [1:0] req_slot;reg req_bank;
    reg ack1,ack2,ack_seen;reg ack_toggle,ack_error;
    reg req1,req2,req_seen,mem_active,mem_bank;
    reg [ADDR_BITS-1:0] mem_address;
    reg [23:0] lines[0:2047];
    reg [23:0] line_read;
    reg pixel_good;
    // The RAM read register has no reset. Reset/gating happens outside the RAM,
    // so TD can infer a true dual-clock block RAM rather than thousands of LUTs.
    always @(posedge video_clk)line_read<=lines[{vc[0],hc[9:0]}];
    assign rgb=pixel_good?line_read:24'd0;
    reg [1:0] bank_valid;reg [8:0] bank_row0,bank_row1;
    reg [1:0] bank_slot0,bank_slot1;
    reg line_good;
    reg pending,waiting_prefill;reg [1:0] target;reg [31:0] token;
    wire mailbox_ready=(req_toggle==ack2);
    assign switch_ready=boot2&&!pending&&!waiting_prefill;
    assign line_valid=mem_active;
    assign line_addr=mem_address;
    wire good=(vc<HEIGHT)&&bank_valid[vc[0]]&&
        (vc[0]?(bank_row1==vc && bank_slot1==active_slot):(bank_row0==vc && bank_slot0==active_slot));
    always @(posedge mem_clk or negedge mem_rst_n)begin
        if(!mem_rst_n)begin
            req1<=0;req2<=0;req_seen<=0;mem_active<=0;mem_bank<=0;mem_address<=0;
            ack_toggle<=0;ack_error<=0;
        end else begin
            req1<=req_toggle;req2<=req1;
            if(req2!=req_seen&&!mem_active)begin
                req_seen<=req2;mem_bank<=req_bank;
                mem_address<=req_slot*(WIDTH*HEIGHT)+req_row*WIDTH;mem_active<=1;
            end
            if(line_valid&&line_ready)mem_active<=0;
            if(line_pixel_valid)lines[{mem_bank,line_pixel_index}]<=line_pixel_data;
            if(line_done)begin ack_toggle<=req_seen;ack_error<=line_error;end
        end
    end
    task fetch;
        input [8:0] row;input [1:0] slot;
        begin req_row<=row;req_slot<=slot;req_bank<=row[0];req_toggle<=!req_toggle;bank_valid[row[0]]<=0;end
    endtask
    always @(posedge video_clk or negedge video_rst_n)begin
        if(!video_rst_n)begin
            hc<=0;vc<=0;boot1<=0;boot2<=0;mask1<=0;mask2<=0;
            req_toggle<=0;req_row<=0;req_slot<=0;req_bank<=0;
            ack1<=0;ack2<=0;ack_seen<=0;bank_valid<=0;bank_row0<=0;bank_row1<=0;
            bank_slot0<=0;bank_slot1<=0;line_good<=0;
            pending<=0;waiting_prefill<=0;target<=0;token<=0;
            reply_valid<=0;reply_slot<=0;reply_token<=0;reply_error<=0;
            active_slot<=0;active_valid<=0;underruns<=0;pixel_good<=0;hs<=1;vs<=1;de<=0;x<=0;y<=0;
        end else begin
            boot1<=boot_finished;boot2<=boot1;mask1<=resident_mask;mask2<=mask1;
            ack1<=ack_toggle;ack2<=ack1;reply_valid<=0;
            if(hc==HTOTAL-1)begin hc<=0;if(vc==VTOTAL-1)vc<=0;else vc<=vc+1'b1;end
            else hc<=hc+1'b1;
            hs<=!(hc>=WIDTH+HFP&&hc<WIDTH+HFP+HSA);
            vs<=!(vc>=HEIGHT+VFP&&vc<HEIGHT+VFP+VSA);
            de<=(hc<WIDTH&&vc<HEIGHT);x<=hc;y<=vc;
            pixel_good<=hc<WIDTH&&vc<HEIGHT&&active_valid&&((hc==0)?good:line_good);
            if(hc==0&&vc<HEIGHT)begin
                line_good<=good;
                if(active_valid&&!good)underruns<=underruns+1'b1;
                if(active_valid&&vc+1<HEIGHT&&mailbox_ready)fetch(vc+1'b1,active_slot);
            end
            if(switch_valid&&switch_ready)begin pending<=1;target<=switch_slot;token<=switch_token;end
            if(switch_cancel)begin pending<=0;waiting_prefill<=0;end
            if(frame_tick&&boot2&&mailbox_ready)begin
                if(pending&&!switch_cancel)begin
                    pending<=0;reply_slot<=target;reply_token<=token;
                    if(mask2[target])begin
                        active_slot<=target;active_valid<=1;waiting_prefill<=1;fetch(0,target);
                    end else begin reply_valid<=1;reply_error<=1;end
                end else if(active_valid)fetch(0,active_slot);
                else if(mask2[0])begin active_slot<=0;active_valid<=1;fetch(0,0);end
            end
            if(ack2!=ack_seen)begin
                ack_seen<=ack2;
                if(req_bank)begin bank_row1<=req_row;bank_slot1<=req_slot;end
                else begin bank_row0<=req_row;bank_slot0<=req_slot;end
                bank_valid[req_bank]<=!ack_error;
                // The acknowledgement is after all new row pixels are in RAM.
                if(waiting_prefill&&req_row==0&&req_slot==active_slot&&!switch_cancel)begin
                    waiting_prefill<=0;reply_valid<=1;reply_error<=ack_error;
                end
            end
        end
    end
endmodule
