// Mode 0, MSB first; HALF_DIV reference cycles per half SPI period.
module team_spi_byte(
    input wire clk,rst_n,start,
    input wire [15:0] half_div,
    input wire [7:0] tx,
    output reg busy,done,
    output reg [7:0] rx,
    output reg sclk,mosi,
    input wire miso
);
    reg [15:0] ticks;reg [3:0] edge_count;reg [7:0] shift;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin busy<=0;done<=0;rx<=0;sclk<=0;mosi<=1;ticks<=0;edge_count<=0;shift<=0;end
        else begin
            done<=0;
            if(!busy) begin
                sclk<=0;
                if(start) begin busy<=1;shift<=tx;mosi<=tx[7];ticks<=0;edge_count<=0;end
            end else if(ticks+1>=half_div) begin
                ticks<=0;edge_count<=edge_count+1'b1;sclk<=!sclk;
                if(!sclk) rx<={rx[6:0],miso};
                else begin
                    shift<={shift[6:0],1'b1};mosi<=shift[6];
                    if(edge_count==15) begin busy<=0;done<=1;mosi<=1;end
                end
            end else ticks<=ticks+1'b1;
        end
    end
endmodule
