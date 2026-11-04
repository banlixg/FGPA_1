// Independent, read-only SD v2 SPI host. CMD58 decides block/byte addressing.
// Whole-sector buffering decouples non-pausable card traffic from file backpressure.
// Cancel drains an in-flight physical transaction before exposing request_ready.
module team_sd_spi_reader #(
    parameter POWER_CYCLES=1000000, SLOW_DIV=125, FAST_DIV=2,
    parameter INIT_TRIES=1000, RESPONSE_BYTES=16, TOKEN_BYTES=262143
)(
    input wire clk,rst_n,
    output reg initialized,init_failed,
    output reg [3:0] error_code,
    output reg high_capacity,
    input wire rd_req_valid,
    output wire rd_req_ready,
    input wire [31:0] rd_req_lba,
    input wire rd_cancel,
    output wire rd_valid,
    input wire rd_ready,
    output wire [7:0] rd_data,
    output wire rd_last,
    output reg rd_error,
    output reg sd_ncs,
    output wire sd_dclk,sd_mosi,
    input wire sd_miso
);
    localparam POWER=0,CLOCKS=1,LAUNCH=2,SEND=3,R1=4,EXTRA=5,CHECK=6,
        IDLE=7,TOKEN=8,DATA=9,CRC_HI=10,CRC_LO=11,RELEASE=12,STREAM=13,DEAD=14;
    reg [3:0] state;
    reg byte_start;reg [7:0] byte_tx;wire byte_busy,byte_done;wire [7:0] byte_rx;
    wire [15:0] divider=initialized?FAST_DIV:SLOW_DIV;
    team_spi_byte spi(.clk(clk),.rst_n(rst_n),.start(byte_start),.half_div(divider),
        .tx(byte_tx),.busy(byte_busy),.done(byte_done),.rx(byte_rx),
        .sclk(sd_dclk),.mosi(sd_mosi),.miso(sd_miso));
    reg [31:0] power_count,arg,extra_value;
    reg [5:0] command;reg [7:0] command_crc,r1;
    reg [2:0] command_index,extra_index;
    reg [18:0] polls;reg [15:0] tries;
    reg [8:0] data_index,stream_index;
    reg [15:0] crc,received_crc;
    reg [7:0] sector[0:511];
    reg dropped,transaction_error,read_job;
    reg [3:0] after_release;
    assign rd_req_ready=(state==IDLE)&&initialized&&!byte_busy;
    assign rd_valid=(state==STREAM)&&!dropped&&!rd_cancel;
    assign rd_data=sector[stream_index];
    assign rd_last=(stream_index==511);
    function [15:0] crc16;
        input [15:0] old_crc;input [7:0] value;
        reg [15:0] c;integer k;
        begin c=old_crc^{value,8'd0};for(k=0;k<8;k=k+1)c=c[15]?((c<<1)^16'h1021):(c<<1);crc16=c;end
    endfunction
    task issue;
        input [5:0] cmd;input [31:0] argument;input [7:0] check;
        begin command<=cmd;arg<=argument;command_crc<=check;state<=LAUNCH;end
    endtask
    task fail;
        input [3:0] code;
        begin
            error_code<=code;transaction_error<=1;sd_ncs<=1;state<=RELEASE;
            after_release<=initialized?IDLE:DEAD;
            if(!initialized)init_failed<=1;
        end
    endtask
    task transfer;
        input [7:0] value;
        begin byte_tx<=value;byte_start<=1;end
    endtask
    // launch only when neither the byte engine nor its queued start is active
    wire can_send=!byte_busy&&!byte_start&&!byte_done;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=POWER;initialized<=0;init_failed<=0;high_capacity<=0;error_code<=0;
            rd_error<=0;sd_ncs<=1;byte_start<=0;byte_tx<=8'hff;power_count<=0;
            command<=0;arg<=0;command_crc<=0;command_index<=0;extra_index<=0;
            r1<=0;extra_value<=0;polls<=0;tries<=0;data_index<=0;stream_index<=0;
            crc<=0;received_crc<=0;dropped<=0;transaction_error<=0;read_job<=0;after_release<=IDLE;
        end else begin
            byte_start<=0;rd_error<=0;
            if(rd_cancel && read_job) dropped<=1;
            case(state)
                POWER:if(power_count+1>=POWER_CYCLES) begin polls<=0;state<=CLOCKS;end
                      else power_count<=power_count+1'b1;
                CLOCKS:begin
                    if(can_send) transfer(8'hff);
                    if(byte_done) begin
                        if(polls==9) begin polls<=0;issue(0,0,8'h95);end
                        else polls<=polls+1'b1;
                    end
                end
                LAUNCH:begin sd_ncs<=0;command_index<=0;polls<=0;state<=SEND;end
                SEND:begin
                    if(can_send) case(command_index)
                        0:transfer({2'b01,command});1:transfer(arg[31:24]);2:transfer(arg[23:16]);
                        3:transfer(arg[15:8]);4:transfer(arg[7:0]);5:transfer(command_crc);
                    endcase
                    if(byte_done) begin
                        if(command_index==5) state<=R1;
                        else command_index<=command_index+1'b1;
                    end
                end
                R1:begin
                    if(can_send) transfer(8'hff);
                    if(byte_done) begin
                        if(!byte_rx[7]) begin
                            r1<=byte_rx;extra_index<=0;extra_value<=0;
                            if(command==8 || command==58) state<=EXTRA;else state<=CHECK;
                        end else if(polls+1>=RESPONSE_BYTES) fail(1);
                        else polls<=polls+1'b1;
                    end
                end
                EXTRA:begin
                    if(can_send) transfer(8'hff);
                    if(byte_done) begin
                        extra_value<={extra_value[23:0],byte_rx};
                        if(extra_index==3) state<=CHECK;else extra_index<=extra_index+1'b1;
                    end
                end
                CHECK:case(command)
                    0:if(r1!=1) fail(2);else begin sd_ncs<=1;after_release<=LAUNCH;issue(8,32'h1aa,8'h87);state<=RELEASE;end
                    8:if(r1!=1 || extra_value[11:0]!=12'h1aa) fail(3);
                      else begin sd_ncs<=1;after_release<=LAUNCH;issue(55,0,8'h01);state<=RELEASE;end
                    55:if(r1!=1 && r1!=0) fail(4);
                       else begin sd_ncs<=1;after_release<=LAUNCH;issue(41,32'h40000000,8'h01);state<=RELEASE;end
                    41:if(r1==0) begin sd_ncs<=1;after_release<=LAUNCH;issue(58,0,8'h01);state<=RELEASE;end
                       else if(r1==1 && tries+1<INIT_TRIES) begin
                           tries<=tries+1'b1;sd_ncs<=1;after_release<=LAUNCH;issue(55,0,8'h01);state<=RELEASE;
                       end else fail(4);
                    58:if(r1!=0 || !extra_value[31] || !(|extra_value[23:15])) fail(5);
                       else begin
                           high_capacity<=extra_value[30];sd_ncs<=1;
                           if(extra_value[30]) begin initialized<=1;after_release<=IDLE;state<=RELEASE;end
                           else begin after_release<=LAUNCH;issue(16,512,8'h01);state<=RELEASE;end
                       end
                    16:if(r1!=0) fail(5);else begin initialized<=1;sd_ncs<=1;after_release<=IDLE;state<=RELEASE;end
                    17:if(r1!=0) fail(6);else begin polls<=0;state<=TOKEN;end
                    default:fail(2);
                endcase
                IDLE:if(rd_req_valid && rd_req_ready) begin
                    dropped<=rd_cancel;transaction_error<=0;read_job<=1;error_code<=0;
                    if(!high_capacity && |rd_req_lba[31:23]) fail(9);
                    else issue(17,high_capacity?rd_req_lba:(rd_req_lba<<9),8'h01);
                end
                TOKEN:begin
                    if(can_send) transfer(8'hff);
                    if(byte_done) begin
                        if(byte_rx==8'hfe) begin data_index<=0;crc<=0;state<=DATA;end
                        else if(byte_rx!=8'hff) fail(7);
                        else if(polls+1>=TOKEN_BYTES) fail(8);
                        else polls<=polls+1'b1;
                    end
                end
                DATA:begin
                    if(can_send) transfer(8'hff);
                    if(byte_done) begin
                        sector[data_index]<=byte_rx;crc<=crc16(crc,byte_rx);
                        if(data_index==511) state<=CRC_HI;else data_index<=data_index+1'b1;
                    end
                end
                CRC_HI:begin
                    if(can_send) transfer(8'hff);
                    if(byte_done) begin received_crc[15:8]<=byte_rx;state<=CRC_LO;end
                end
                CRC_LO:begin
                    if(can_send) transfer(8'hff);
                    if(byte_done) begin
                        if({received_crc[15:8],byte_rx}!=crc) fail(10);
                        else begin sd_ncs<=1;after_release<=STREAM;state<=RELEASE;end
                    end
                end
                RELEASE:begin
                    if(can_send) transfer(8'hff);
                    if(byte_done) begin
                        if(transaction_error && read_job && !dropped && !rd_cancel) rd_error<=1;
                        if(after_release==STREAM) begin
                            stream_index<=0;
                            if(dropped || rd_cancel) begin state<=IDLE;read_job<=0;end
                            else state<=STREAM;
                        end else begin state<=after_release;if(after_release==IDLE) read_job<=0;end
                    end
                end
                STREAM:if(dropped || rd_cancel || (rd_valid&&rd_ready&&rd_last)) begin state<=IDLE;read_job<=0;end
                       else if(rd_valid&&rd_ready) stream_index<=stream_index+1'b1;
                default:begin end
            endcase
        end
    end
endmodule
