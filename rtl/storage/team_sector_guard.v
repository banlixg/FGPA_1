// One 512-byte read transaction. The lower adapter MUST honour byte backpressure.
// A future non-stallable SPI engine must be connected through a sector buffer.
module team_sector_guard #(
    parameter integer WAIT_LIMIT=1000000
)(
    input wire clk, rst_n, start,
    input wire [31:0] lba,
    output wire idle,
    output reg done, error,
    output reg [3:0] error_code,
    output wire out_valid,
    input wire out_ready,
    output wire [7:0] out_data,
    output wire [8:0] out_index,
    output wire out_last,
    output wire rd_req_valid,
    output wire rd_cancel,
    input wire rd_req_ready,
    output reg [31:0] rd_req_lba,
    input wire rd_valid,
    output wire rd_ready,
    input wire [7:0] rd_data,
    input wire rd_last, rd_error
);
    localparam IDLE=0, REQUEST=1, STREAM=2;
    reg [1:0] state;
    reg [8:0] index;
    reg [31:0] waited;
    assign idle=(state==IDLE);
    assign rd_req_valid=(state==REQUEST);
    assign rd_cancel=error;
    assign rd_ready=(state==STREAM) && out_ready;
    assign out_valid=(state==STREAM) && rd_valid && !rd_error;
    assign out_data=rd_data;
    assign out_index=index;
    assign out_last=(index==511);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; index<=0; waited<=0; rd_req_lba<=0;
            done<=0; error<=0; error_code<=0;
        end else begin
            done<=0; error<=0;
            if(state!=IDLE && rd_error) begin
                state<=IDLE; error<=1; error_code<=1; waited<=0;
            end else case(state)
                IDLE: if(start) begin
                    rd_req_lba<=lba; index<=0; waited<=0;
                    error_code<=0; state<=REQUEST;
                end
                REQUEST: if(rd_req_ready) begin
                    state<=STREAM; waited<=0;
                end else if(waited>=WAIT_LIMIT-1) begin
                    state<=IDLE; error<=1; error_code<=3;
                end else waited<=waited+1'b1;
                STREAM: if(out_ready && rd_valid) begin
                    waited<=0;
                    if(rd_last != (index==511)) begin
                        state<=IDLE; error<=1; error_code<=2;
                    end else if(index==511) begin
                        state<=IDLE; done<=1;
                    end else index<=index+1'b1;
                end else if(!out_ready) waited<=0;
                else if(waited>=WAIT_LIMIT-1) begin
                    state<=IDLE; error<=1; error_code<=3;
                end else waited<=waited+1'b1;
                default: state<=IDLE;
            endcase
        end
    end
endmodule
