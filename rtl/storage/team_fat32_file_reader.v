// Streams precisely file_size bytes along a FAT32 cluster chain. Remaining
// bytes of the current sector are drained before completion/early close.
module team_fat32_file_reader #(
    parameter integer WAIT_LIMIT=1000000
)(
    input wire clk, rst_n, start, close_file,
    input wire [31:0] fat_lba, data_lba, cluster_count,
    input wire [7:0] sectors_per_cluster,
    input wire [27:0] first_cluster,
    input wire [31:0] file_size,
    output reg busy, done, error,
    output reg [3:0] error_code,
    output reg [31:0] file_position,
    output wire file_valid,
    input wire file_ready,
    output wire [7:0] file_byte,
    output wire file_last,
    output wire rd_req_valid,
    output wire rd_cancel,
    input wire rd_req_ready,
    output wire [31:0] rd_req_lba,
    input wire rd_valid,
    output wire rd_ready,
    input wire [7:0] rd_data,
    input wire rd_last, rd_error
);
    localparam IDLE=0, ISSUE_DATA=1, READ_DATA=2, AFTER_DATA=3,
               ISSUE_FAT=4, READ_FAT=5, CHECK_FAT=6;
    reg [2:0] state;
    reg sector_start, closing;
    reg [31:0] sector_lba, remaining;
    wire sector_idle, sector_done, sector_error, byte_valid, byte_last;
    wire [3:0] sector_code;
    wire [7:0] byte_data;
    wire [8:0] byte_index;
    wire byte_ready=(state==READ_FAT) || ((state==READ_DATA) &&
                    (closing || close_file || remaining==0 || file_ready));
    assign file_valid=(state==READ_DATA) && byte_valid && remaining!=0 && !closing && !close_file;
    assign file_byte=byte_data;
    assign file_last=(remaining==1);
    team_sector_guard #(.WAIT_LIMIT(WAIT_LIMIT)) guard(
        .clk(clk),.rst_n(rst_n),.start(sector_start),.lba(sector_lba),
        .idle(sector_idle),.done(sector_done),.error(sector_error),.error_code(sector_code),
        .out_valid(byte_valid),.out_ready(byte_ready),.out_data(byte_data),
        .out_index(byte_index),.out_last(byte_last),
        .rd_req_valid(rd_req_valid),.rd_cancel(rd_cancel),.rd_req_ready(rd_req_ready),.rd_req_lba(rd_req_lba),
        .rd_valid(rd_valid),.rd_ready(rd_ready),.rd_data(rd_data),.rd_last(rd_last),.rd_error(rd_error));
    reg [27:0] current_cluster, anchor;
    reg [31:0] chain_power, chain_length, hops, fat_value;
    reg [7:0] sector_in_cluster;
    reg [8:0] fat_offset;
    wire [27:0] next_cluster=fat_value[27:0];
    function [2:0] log_spc;
        input [7:0] value;
        begin case(value)
            1:log_spc=0;2:log_spc=1;4:log_spc=2;8:log_spc=3;
            16:log_spc=4;32:log_spc=5;64:log_spc=6;default:log_spc=7;
        endcase end
    endfunction
    function [31:0] cluster_sector;
        input [27:0] c;
        begin cluster_sector=data_lba+(({4'd0,c}-2)<<log_spc(sectors_per_cluster));end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;busy<=0;done<=0;error<=0;error_code<=0;file_position<=0;
            sector_start<=0;sector_lba<=0;remaining<=0;closing<=0;
            current_cluster<=0;anchor<=0;chain_power<=0;chain_length<=0;hops<=0;
            fat_value<=0;sector_in_cluster<=0;fat_offset<=0;
        end else begin
            done<=0;error<=0;sector_start<=0;
            if(close_file && busy) closing<=1;
            if(busy && sector_error) begin
                busy<=0;error<=1;error_code<=sector_code;state<=IDLE;
            end else case(state)
                IDLE: if(start) begin
                    file_position<=0;remaining<=file_size;closing<=0;error_code<=0;
                    current_cluster<=first_cluster;anchor<=first_cluster;
                    chain_power<=1;chain_length<=0;hops<=1;sector_in_cluster<=0;
                    if(file_size==0) done<=1;
                    else if(first_cluster<2 || first_cluster>cluster_count+1 || sectors_per_cluster==0) begin
                        error<=1;error_code<=6;
                    end else begin busy<=1;sector_lba<=cluster_sector(first_cluster);state<=ISSUE_DATA;end
                end
                ISSUE_DATA: if(closing || close_file) begin busy<=0;done<=1;state<=IDLE;end
                else if(sector_idle) begin sector_start<=1;state<=READ_DATA;end
                READ_DATA: if(byte_valid && byte_ready) begin
                    if(file_valid && file_ready) begin
                        remaining<=remaining-1'b1;file_position<=file_position+1'b1;
                    end
                    if(byte_last) state<=AFTER_DATA;
                end
                AFTER_DATA: if(remaining==0 || closing || close_file) begin
                    busy<=0;done<=1;state<=IDLE;
                end else if(sector_in_cluster+1<sectors_per_cluster) begin
                    sector_in_cluster<=sector_in_cluster+1'b1;sector_lba<=sector_lba+1'b1;state<=ISSUE_DATA;
                end else begin
                    fat_value<=0;fat_offset<={current_cluster[6:0],2'b00};
                    sector_lba<=fat_lba+(current_cluster>>7);state<=ISSUE_FAT;
                end
                ISSUE_FAT: if(closing || close_file) begin busy<=0;done<=1;state<=IDLE;end
                else if(sector_idle) begin sector_start<=1;state<=READ_FAT;end
                READ_FAT: if(byte_valid) begin
                    if(byte_index==fat_offset) fat_value[7:0]<=byte_data;
                    if(byte_index==fat_offset+1) fat_value[15:8]<=byte_data;
                    if(byte_index==fat_offset+2) fat_value[23:16]<=byte_data;
                    if(byte_index==fat_offset+3) fat_value[31:24]<=byte_data;
                    if(byte_last) state<=CHECK_FAT;
                end
                CHECK_FAT: if(closing || close_file) begin busy<=0;done<=1;state<=IDLE;end
                else if(next_cluster>=28'hffffff8) begin
                    busy<=0;error<=1;error_code<=7;state<=IDLE;
                end else if(next_cluster<2 || next_cluster>=28'hffffff0 || next_cluster>cluster_count+1) begin
                    busy<=0;error<=1;error_code<=7;state<=IDLE;
                end else if(next_cluster==anchor) begin
                    busy<=0;error<=1;error_code<=8;state<=IDLE;
                end else if(hops>=cluster_count) begin
                    busy<=0;error<=1;error_code<=9;state<=IDLE;
                end else begin
                    if(chain_length+1==chain_power) begin
                        anchor<=next_cluster;chain_power<=chain_power<<1;chain_length<=0;
                    end else chain_length<=chain_length+1'b1;
                    current_cluster<=next_cluster;hops<=hops+1'b1;sector_in_cluster<=0;
                    sector_lba<=cluster_sector(next_cluster);state<=ISSUE_DATA;
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
