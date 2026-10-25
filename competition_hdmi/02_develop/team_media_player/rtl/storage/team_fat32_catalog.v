// Root-directory BMP candidate enumeration. LFN auxiliary/deleted/directory/
// volume-label entries are skipped; short aliases are sufficient for file I/O.
module team_fat32_catalog #(
    parameter integer WAIT_LIMIT=1000000,
    parameter integer MAX_CANDIDATES=32,
    parameter integer MAX_DIR_CLUSTERS=1024
)(
    input wire clk, rst_n, start,
    input wire [31:0] fat_lba, data_lba, cluster_count,
    input wire [7:0] sectors_per_cluster,
    input wire [27:0] root_cluster,
    output reg busy, done, error, limited,
    output reg [3:0] error_code,
    output reg [15:0] candidate_count,
    output reg candidate_valid,
    input wire candidate_ready,
    output reg [87:0] candidate_name,
    output reg [27:0] candidate_cluster,
    output reg [31:0] candidate_size,
    output wire rd_req_valid,
    output wire rd_cancel,
    input wire rd_req_ready,
    output wire [31:0] rd_req_lba,
    input wire rd_valid,
    output wire rd_ready,
    input wire [7:0] rd_data,
    input wire rd_last, rd_error
);
    localparam IDLE=0, ISSUE_DIR=1, READ_DIR=2, AFTER_DIR=3,
               ISSUE_FAT=4, READ_FAT=5, CHECK_FAT=6;
    reg [2:0] state;
    reg sector_start;
    reg [31:0] sector_lba;
    wire sector_idle, sector_done, sector_error, byte_valid, byte_last;
    wire [3:0] sector_code;
    wire [7:0] byte_data;
    wire [8:0] byte_index;
    wire byte_ready=(state==READ_FAT) || ((state==READ_DIR) && !candidate_valid);
    team_sector_guard #(.WAIT_LIMIT(WAIT_LIMIT)) guard(
        .clk(clk),.rst_n(rst_n),.start(sector_start),.lba(sector_lba),
        .idle(sector_idle),.done(sector_done),.error(sector_error),.error_code(sector_code),
        .out_valid(byte_valid),.out_ready(byte_ready),.out_data(byte_data),
        .out_index(byte_index),.out_last(byte_last),
        .rd_req_valid(rd_req_valid),.rd_cancel(rd_cancel),.rd_req_ready(rd_req_ready),.rd_req_lba(rd_req_lba),
        .rd_valid(rd_valid),.rd_ready(rd_ready),.rd_data(rd_data),.rd_last(rd_last),.rd_error(rd_error));
    reg [27:0] current_cluster, anchor;
    reg [31:0] chain_power, chain_length, hops;
    reg [7:0] sector_in_cluster;
    reg [31:0] fat_value;
    reg [8:0] fat_offset;
    reg end_seen;
    reg [7:0] entry_first, entry_attr;
    reg [87:0] entry_name;
    reg [31:0] entry_cluster, entry_size;
    wire [27:0] next_cluster=fat_value[27:0];
    wire bmp_extension=((entry_name[23:16]=="B") || (entry_name[23:16]=="b")) &&
                       ((entry_name[15:8]=="M") || (entry_name[15:8]=="m")) &&
                       ((entry_name[7:0]=="P") || (entry_name[7:0]=="p"));
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
            state<=IDLE;busy<=0;done<=0;error<=0;limited<=0;error_code<=0;
            candidate_count<=0;candidate_valid<=0;candidate_name<=0;
            candidate_cluster<=0;candidate_size<=0;sector_start<=0;sector_lba<=0;
            current_cluster<=0;anchor<=0;chain_power<=0;chain_length<=0;hops<=0;
            sector_in_cluster<=0;fat_value<=0;fat_offset<=0;end_seen<=0;
            entry_first<=0;entry_attr<=0;entry_name<=0;entry_cluster<=0;entry_size<=0;
        end else begin
            done<=0;error<=0;sector_start<=0;
            if(candidate_valid && candidate_ready) begin
                candidate_valid<=0;candidate_count<=candidate_count+1'b1;
                if(candidate_count+1>=MAX_CANDIDATES) begin end_seen<=1;limited<=1;end
            end
            if(busy && sector_error) begin
                state<=IDLE;busy<=0;candidate_valid<=0;error<=1;error_code<=sector_code;
            end else case(state)
                IDLE: if(start) begin
                    candidate_count<=0;candidate_valid<=0;limited<=0;end_seen<=0;error_code<=0;
                    current_cluster<=root_cluster;anchor<=root_cluster;
                    chain_power<=1;chain_length<=0;hops<=1;sector_in_cluster<=0;
                    if(root_cluster<2 || root_cluster>cluster_count+1 || sectors_per_cluster==0) begin
                        error<=1;error_code<=6;
                    end else begin busy<=1;sector_lba<=cluster_sector(root_cluster);state<=ISSUE_DIR;end
                end
                ISSUE_DIR: if(sector_idle) begin sector_start<=1;state<=READ_DIR;end
                READ_DIR: if(byte_valid && byte_ready) begin
                    if(!end_seen) begin
                        if(byte_index[4:0]==0) begin
                            entry_first<=byte_data;entry_name<={80'd0,byte_data};
                            entry_attr<=0;entry_cluster<=0;entry_size<=0;
                            if(byte_data==0) end_seen<=1;
                        end else if(byte_index[4:0]<=10)
                            entry_name<={entry_name[79:0],byte_data};
                        case(byte_index[4:0])
                            11:entry_attr<=byte_data;
                            20:entry_cluster[23:16]<=byte_data;
                            21:entry_cluster[31:24]<=byte_data;
                            26:entry_cluster[7:0]<=byte_data;
                            27:entry_cluster[15:8]<=byte_data;
                            28:entry_size[7:0]<=byte_data;
                            29:entry_size[15:8]<=byte_data;
                            30:entry_size[23:16]<=byte_data;
                            31:begin
                                if(entry_first!=0 && entry_first!=8'he5 &&
                                   entry_attr!=8'h0f && (entry_attr & 8'h18)==0 &&
                                   bmp_extension && entry_cluster[27:0]>=2 &&
                                   entry_cluster[27:0]<=cluster_count+1 &&
                                   {byte_data,entry_size[23:0]}>=54) begin
                                    candidate_name<=entry_name;
                                    candidate_cluster<=entry_cluster[27:0];
                                    candidate_size<={byte_data,entry_size[23:0]};
                                    candidate_valid<=1;
                                end
                            end
                            default:begin end
                        endcase
                    end
                    if(byte_last) state<=AFTER_DIR;
                end
                AFTER_DIR: if(!candidate_valid) begin
                    if(end_seen) begin busy<=0;done<=1;state<=IDLE;end
                    else if(sector_in_cluster+1<sectors_per_cluster) begin
                        sector_in_cluster<=sector_in_cluster+1'b1;
                        sector_lba<=sector_lba+1'b1;state<=ISSUE_DIR;
                    end else begin
                        sector_lba<=fat_lba+(current_cluster>>7);
                        fat_offset<={current_cluster[6:0],2'b00};fat_value<=0;
                        state<=ISSUE_FAT;
                    end
                end
                ISSUE_FAT: if(sector_idle) begin sector_start<=1;state<=READ_FAT;end
                READ_FAT: if(byte_valid) begin
                    if(byte_index==fat_offset) fat_value[7:0]<=byte_data;
                    if(byte_index==fat_offset+1) fat_value[15:8]<=byte_data;
                    if(byte_index==fat_offset+2) fat_value[23:16]<=byte_data;
                    if(byte_index==fat_offset+3) fat_value[31:24]<=byte_data;
                    if(byte_last) state<=CHECK_FAT;
                end
                CHECK_FAT: begin
                    if(next_cluster>=28'hffffff8) begin busy<=0;done<=1;state<=IDLE;end
                    else if(next_cluster<2 || next_cluster>=28'hffffff0 || next_cluster>cluster_count+1) begin
                        busy<=0;error<=1;error_code<=7;state<=IDLE;
                    end else if(next_cluster==anchor) begin
                        busy<=0;error<=1;error_code<=8;state<=IDLE;
                    end else if(hops>=MAX_DIR_CLUSTERS || hops>=cluster_count) begin
                        busy<=0;error<=1;error_code<=9;state<=IDLE;
                    end else begin
                        if(chain_length+1==chain_power) begin
                            anchor<=next_cluster;chain_power<=chain_power<<1;chain_length<=0;
                        end else chain_length<=chain_length+1'b1;
                        hops<=hops+1'b1;current_cluster<=next_cluster;sector_in_cluster<=0;
                        sector_lba<=cluster_sector(next_cluster);state<=ISSUE_DIR;
                    end
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
