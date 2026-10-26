// Adapter around the board's vendor SDRAM controller, not its image/FIFO logic.
// Writes are acknowledged ONLY after an independent readback matches all 32 bits.
// Display uses sequential line requests; boot writes and display are serialized.
module team_sdram_port #(
    parameter ADDR_BITS=21, SETTLE_CYCLES=64, TIMEOUT_CYCLES=10000,
    parameter LINE_WIDTH=640
)(
    input wire clk,rst_n,mem_initialized,mem_busy,mem_refresh,
    input wire wr_valid,output wire wr_ready,
    input wire [ADDR_BITS-1:0] wr_addr,input wire [31:0] wr_data,
    output reg wr_rsp_valid,wr_rsp_error,
    input wire line_valid,output wire line_ready,input wire [ADDR_BITS-1:0] line_addr,
    output reg line_pixel_valid,output reg [9:0] line_pixel_index,
    output reg [23:0] line_pixel_data,output reg line_done,line_error,
    output wire app_wr_en,output wire [ADDR_BITS-1:0] app_wr_addr,
    output wire [31:0] app_wr_data,
    output wire app_rd_en,output wire [ADDR_BITS-1:0] app_rd_addr,
    input wire mem_rd_valid,input wire [31:0] mem_rd_data
);
    localparam IDLE=0,WRITE=1,SETTLE=2,VERIFY=3,WAIT_VERIFY=4,LINE=5,FAULT=6;
    reg [2:0] state;reg [ADDR_BITS-1:0] address;reg [31:0] value;
    reg [31:0] ticks;reg [10:0] issued,returned;
    wire available=mem_initialized&&!mem_busy&&!mem_refresh;
    assign wr_ready=(state==IDLE)&&available;
    assign line_ready=(state==IDLE)&&available&&!wr_valid;
    assign app_wr_en=(state==WRITE)&&available;
    assign app_wr_addr=address;assign app_wr_data=value;
    assign app_rd_en=available&&((state==VERIFY)||(state==LINE&&issued<LINE_WIDTH));
    assign app_rd_addr=address+((state==LINE)?issued:0);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            state<=IDLE;address<=0;value<=0;ticks<=0;issued<=0;returned<=0;
            wr_rsp_valid<=0;wr_rsp_error<=0;line_pixel_valid<=0;
            line_pixel_index<=0;line_pixel_data<=0;line_done<=0;line_error<=0;
        end else begin
            wr_rsp_valid<=0;line_pixel_valid<=0;line_done<=0;line_error<=0;
            case(state)
                IDLE:begin
                    ticks<=0;
                    if(wr_valid&&wr_ready)begin address<=wr_addr;value<=wr_data;state<=WRITE;end
                    else if(line_valid&&line_ready)begin address<=line_addr;issued<=0;returned<=0;state<=LINE;end
                end
                WRITE:if(app_wr_en)begin state<=SETTLE;ticks<=0;end
                      else if(ticks+1>=TIMEOUT_CYCLES)begin wr_rsp_valid<=1;wr_rsp_error<=1;state<=FAULT;end
                      else ticks<=ticks+1'b1;
                SETTLE:if(ticks+1>=SETTLE_CYCLES)begin state<=VERIFY;ticks<=0;end
                       else ticks<=ticks+1'b1;
                VERIFY:if(app_rd_en)begin state<=WAIT_VERIFY;ticks<=0;end
                       else if(ticks+1>=TIMEOUT_CYCLES)begin wr_rsp_valid<=1;wr_rsp_error<=1;state<=FAULT;end
                       else ticks<=ticks+1'b1;
                WAIT_VERIFY:if(mem_rd_valid)begin
                    wr_rsp_valid<=1;wr_rsp_error<=(mem_rd_data!=value);state<=IDLE;
                end else if(ticks+1>=TIMEOUT_CYCLES)begin
                    wr_rsp_valid<=1;wr_rsp_error<=1;state<=FAULT;
                end else ticks<=ticks+1'b1;
                LINE:begin
                    if(app_rd_en)issued<=issued+1'b1;
                    if(mem_rd_valid)begin
                        line_pixel_valid<=1;line_pixel_index<=returned[9:0];line_pixel_data<=mem_rd_data[31:8];
                        returned<=returned+1'b1;ticks<=0;
                        if(returned+1==LINE_WIDTH)begin line_done<=1;state<=IDLE;end
                    end else if(ticks+1>=TIMEOUT_CYCLES)begin line_done<=1;line_error<=1;state<=FAULT;end
                    else ticks<=ticks+1'b1;
                end
                // Late responses after timeout cannot be attributed safely. Reset required.
                default:begin end
            endcase
        end
    end
endmodule
