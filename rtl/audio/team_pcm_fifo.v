// Gray-pointer asynchronous FIFO; common asynchronous assertion of both resets.
// Only Gray pointers cross clocks; storage has one synchronous read port.
module team_pcm_fifo #(parameter ADDRESS_BITS=11)(
    input wire wr_clk,wr_rst_n,wr_valid,output wire wr_ready,input wire [31:0] wr_data,
    input wire rd_clk,rd_rst_n,rd_enable,output reg [31:0] rd_data,
    output wire empty,output wire [ADDRESS_BITS:0] rd_level
);
    localparam DEPTH=1<<ADDRESS_BITS;
    reg [31:0] ram[0:DEPTH-1];
    reg [ADDRESS_BITS:0] wp,wg,rp,rg,rgs1,rgs2,wgs1,wgs2;
    wire [ADDRESS_BITS:0] wnext=wp+1'b1;
    wire [ADDRESS_BITS:0] wg_next=(wnext>>1)^wnext;
    wire full=(wg=={~rgs2[ADDRESS_BITS:ADDRESS_BITS-1],rgs2[ADDRESS_BITS-2:0]});
    assign wr_ready=!full;assign empty=(rg==wgs2);
    function [ADDRESS_BITS:0] ungray;
        input [ADDRESS_BITS:0] value;integer k;
        begin ungray[ADDRESS_BITS]=value[ADDRESS_BITS];
            for(k=ADDRESS_BITS-1;k>=0;k=k-1)ungray[k]=ungray[k+1]^value[k];end
    endfunction
    assign rd_level=ungray(wgs2)-rp;
    always @(posedge wr_clk or negedge wr_rst_n)begin
        if(!wr_rst_n)begin wp<=0;wg<=0;rgs1<=0;rgs2<=0;end
        else begin
            rgs1<=rg;rgs2<=rgs1;
            if(wr_valid&&wr_ready)begin ram[wp[ADDRESS_BITS-1:0]]<=wr_data;wp<=wnext;wg<=wg_next;end
        end
    end
    always @(posedge rd_clk or negedge rd_rst_n)begin
        if(!rd_rst_n)begin rp<=0;rg<=0;wgs1<=0;wgs2<=0;rd_data<=0;end
        else begin
            wgs1<=wg;wgs2<=wgs1;
            if(rd_enable&&!empty)begin rd_data<=ram[rp[ADDRESS_BITS-1:0]];rp<=rp+1'b1;rg<=((rp+1'b1)>>1)^(rp+1'b1);end
        end
    end
endmodule
