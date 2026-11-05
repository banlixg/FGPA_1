// Adapter around the board's vendor SDRAM controller, not its image/FIFO logic.
// Writes are acknowledged ONLY after an independent readback matches all 32 bits.
// Display uses sequential line requests; boot writes and display are serialized.
//
// 2026-11-04 板测修复记录（本板 HX4S20C / EG4S20B256 SIP SDRAM）：
//   1) 原实现把 Sdr_busy / Sdr_init_ref_vld 当命令门控 -> 命令在刷新切换窗口被静默丢弃。
//      基线(SD/frame_fifo_read/write)从不做该门控，控制器内部自行仲裁。
//      改为 wire available = mem_initialized;
//   2) 独立自检实测：**单拍**写/读在本 SIP 上不可靠（读有回应但数据为 FFFF），
//      而**连发多拍**写/读稳定正确（自检 v3：连发 4 写 0xA5A50000..3 后连发 4 读，
//      第 4 个回应数据 = 0x0003，4 个回应全部收到）。
//      因此写/读都改为 **4 拍突发**：写同一地址同一数据 4 拍，读同一地址 4 拍，
//      在收到第 4 个读回应时比对（同地址读，理论 4 个回应数据相同）。
//      LINE 路径原本就是整行连发，不受影响。
module team_sdram_port #(
    parameter ADDR_BITS=21, SETTLE_CYCLES=64, TIMEOUT_CYCLES=10000,
    parameter VERIFY_ENABLE=1,      // 1: 写后读回校验（正式）；0: 仅功能验证
    parameter BURST_BEATS=4,        // 写/读突发拍数（实测 4 拍可靠，单拍不可靠）
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
    localparam IDLE=0,PREP=1,WRITE=2,SETTLE=3,VERIFY=4,WAIT_VERIFY=5,LINE=6,FAULT=7;
    localparam [3:0] BEATS_LAST = BURST_BEATS - 1;

    reg [2:0]  state;
    reg [ADDR_BITS-1:0] address;
    reg [31:0] value;
    reg [31:0] ticks;
    reg [10:0] issued,returned;
    reg [3:0]  wr_beats, rd_beats, resp_cnt;
    reg [31:0] last_rd;

    // 收发命令只看初始化完成，不看 busy/refresh（与基线一致；控制器内部仲裁）
    wire available = mem_initialized;

    assign wr_ready   = (state==IDLE) && available;
    assign line_ready = (state==IDLE) && available && !wr_valid;

    assign app_wr_en   = (state==WRITE) && available;
    assign app_wr_addr = address;
    assign app_wr_data = value;

    assign app_rd_en   = available && ((state==VERIFY) || (state==LINE && issued<LINE_WIDTH));
    assign app_rd_addr = address + ((state==LINE) ? issued : 0);

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            state<=IDLE;address<=0;value<=0;ticks<=0;issued<=0;returned<=0;
            wr_beats<=0;rd_beats<=0;resp_cnt<=0;last_rd<=0;
            wr_rsp_valid<=0;wr_rsp_error<=0;line_pixel_valid<=0;
            line_pixel_index<=0;line_pixel_data<=0;line_done<=0;line_error<=0;
        end else begin
            wr_rsp_valid<=0;line_pixel_valid<=0;line_done<=0;line_error<=0;
            case(state)
                IDLE:begin
                    ticks<=0;
                    if(wr_valid&&wr_ready)begin
                        address<=wr_addr;value<=wr_data;wr_beats<=0;state<=PREP;
                    end else if(line_valid&&line_ready)begin
                        address<=line_addr;issued<=0;returned<=0;state<=LINE;
                    end
                end
                // 地址/数据稳定一拍后再发写突发
                PREP:begin rd_beats<=0;resp_cnt<=0;state<=WRITE;wr_beats<=0;end
                // 写同一地址同一数据连续 BURST_BEATS 拍
                WRITE:begin
                    if(wr_beats==BEATS_LAST)begin state<=SETTLE;ticks<=0;end
                    else wr_beats<=wr_beats+4'd1;
                end
                SETTLE:begin
                    if(ticks+1>=SETTLE_CYCLES)begin
                        ticks<=0;
                        if(VERIFY_ENABLE)begin rd_beats<=0;resp_cnt<=0;state<=VERIFY;end
                        else begin wr_rsp_valid<=1;wr_rsp_error<=1'b0;state<=IDLE;end
                    end else ticks<=ticks+1'b1;
                end
                // 读同一地址连续 BURST_BEATS 拍
                VERIFY:begin
                    if(rd_beats==BEATS_LAST)begin state<=WAIT_VERIFY;ticks<=0;end
                    else rd_beats<=rd_beats+4'd1;
                end
                // 收集突发回应，收到第 BURST_BEATS 个时比对
                WAIT_VERIFY:begin
                    if(mem_rd_valid)begin
                        last_rd<=mem_rd_data;
                        ticks<=0;
                        if(resp_cnt==BEATS_LAST)begin
                            wr_rsp_valid<=1;
                            wr_rsp_error<=(mem_rd_data!=value);
                            state<=IDLE;
                        end else resp_cnt<=resp_cnt+4'd1;
                    end else if(ticks+1>=TIMEOUT_CYCLES)begin
                        wr_rsp_valid<=1;wr_rsp_error<=1;state<=FAULT;
                    end else ticks<=ticks+1'b1;
                end
                LINE:begin
                    if(app_rd_en)issued<=issued+1'b1;
                    if(mem_rd_valid)begin
                        line_pixel_valid<=1;
                        line_pixel_index<=returned[9:0];
                        line_pixel_data<=mem_rd_data[31:8];
                        returned<=returned+1'b1;ticks<=0;
                        if(returned+1==LINE_WIDTH)begin line_done<=1;state<=IDLE;end
                    end else if(ticks+1>=TIMEOUT_CYCLES)begin
                        line_done<=1;line_error<=1;state<=FAULT;
                    end else ticks<=ticks+1'b1;
                end
                // Late responses after timeout cannot be attributed safely. Reset required.
                default:begin end
            endcase
        end
    end
endmodule
