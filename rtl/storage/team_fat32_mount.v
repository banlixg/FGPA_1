// Read-only FAT32 geometry discovery. Supports a primary MBR FAT32 partition or
// a VBR at LBA 0 (superfloppy), 512-byte sectors, FAT32 version zero, 1/2 FATs.
module team_fat32_mount #(
    parameter integer WAIT_LIMIT=1000000
)(
    input wire clk, rst_n, start,
    output reg busy, mounted, done, error,
    output reg [3:0] error_code,
    output reg [31:0] volume_lba, fat_lba, data_lba,
    output reg [31:0] sectors_per_fat, cluster_count,
    output reg [7:0] sectors_per_cluster,
    output reg [27:0] root_cluster,
    output wire rd_req_valid,
    output wire rd_cancel,
    input wire rd_req_ready,
    output wire [31:0] rd_req_lba,
    input wire rd_valid,
    output wire rd_ready,
    input wire [7:0] rd_data,
    input wire rd_last, rd_error
);
    localparam IDLE=0, ISSUE=1, READ_BOOT=2, CLASSIFY=3, CALCULATE=4, VALIDATE=5;
    reg [2:0] state;
    reg sector_start;
    reg [31:0] sector_lba;
    wire sector_idle, sector_done, sector_error, byte_valid, byte_last;
    wire [3:0] sector_code;
    wire [7:0] byte_data;
    wire [8:0] byte_index;
    team_sector_guard #(.WAIT_LIMIT(WAIT_LIMIT)) guard(
        .clk(clk),.rst_n(rst_n),.start(sector_start),.lba(sector_lba),
        .idle(sector_idle),.done(sector_done),.error(sector_error),.error_code(sector_code),
        .out_valid(byte_valid),.out_ready(state==READ_BOOT),.out_data(byte_data),
        .out_index(byte_index),.out_last(byte_last),
        .rd_req_valid(rd_req_valid),.rd_cancel(rd_cancel),.rd_req_ready(rd_req_ready),.rd_req_lba(rd_req_lba),
        .rd_valid(rd_valid),.rd_ready(rd_ready),.rd_data(rd_data),.rd_last(rd_last),.rd_error(rd_error));

    reg second_boot;
    reg [15:0] signature, bps, reserved, roots16, total16, fat16, extflags, version;
    reg [7:0] spc, fats;
    reg [31:0] total32, fat32, root32;
    reg [7:0] partition_type[0:3];
    reg [31:0] partition_start[0:3], partition_size[0:3];
    reg [31:0] partition_limit;
    reg [63:0] overhead, data_sectors, count_wide, fat_base, data_base;
    reg [63:0] active_base, volume_end, fat_capacity;
    reg [3:0] active_fat;
    integer i;
    reg found;
    wire looks_like_vbr=(roots16==0 && fat16==0 && fat32!=0 && total32!=0 && root32>=2);
    wire spc_ok=(spc!=0 && spc<=128 && (spc & (spc-1'b1))==0);
    function [2:0] log_spc;
        input [7:0] value;
        begin case(value)
            1:log_spc=0;2:log_spc=1;4:log_spc=2;8:log_spc=3;
            16:log_spc=4;32:log_spc=5;64:log_spc=6;default:log_spc=7;
        endcase end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; busy<=0; mounted<=0; done<=0; error<=0; error_code<=0;
            sector_start<=0; sector_lba<=0; second_boot<=0; partition_limit<=0;
            volume_lba<=0;fat_lba<=0;data_lba<=0;sectors_per_fat<=0;
            cluster_count<=0;sectors_per_cluster<=0;root_cluster<=0;
            signature<=0;bps<=0;reserved<=0;roots16<=0;total16<=0;fat16<=0;
            extflags<=0;version<=0;spc<=0;fats<=0;total32<=0;fat32<=0;root32<=0;
            overhead<=0;data_sectors<=0;count_wide<=0;fat_base<=0;data_base<=0;
            active_base<=0;volume_end<=0;fat_capacity<=0;active_fat<=0;
            for(i=0;i<4;i=i+1) begin partition_type[i]<=0;partition_start[i]<=0;partition_size[i]<=0;end
        end else begin
            done<=0;error<=0;sector_start<=0;
            if(busy && sector_error) begin
                state<=IDLE;busy<=0;error<=1;error_code<=sector_code;
            end else case(state)
                IDLE: if(start) begin
                    busy<=1;mounted<=0;error_code<=0;second_boot<=0;
                    volume_lba<=0;sector_lba<=0;partition_limit<=0;state<=ISSUE;
                end
                ISSUE: if(sector_idle) begin
                    signature<=0;bps<=0;reserved<=0;roots16<=0;total16<=0;fat16<=0;
                    extflags<=0;version<=0;spc<=0;fats<=0;total32<=0;fat32<=0;root32<=0;
                    for(i=0;i<4;i=i+1) begin partition_type[i]<=0;partition_start[i]<=0;partition_size[i]<=0;end
                    sector_start<=1;state<=READ_BOOT;
                end
                READ_BOOT: if(byte_valid) begin
                    case(byte_index)
                        11:bps[7:0]<=byte_data;12:bps[15:8]<=byte_data;
                        13:spc<=byte_data;
                        14:reserved[7:0]<=byte_data;15:reserved[15:8]<=byte_data;
                        16:fats<=byte_data;
                        17:roots16[7:0]<=byte_data;18:roots16[15:8]<=byte_data;
                        19:total16[7:0]<=byte_data;20:total16[15:8]<=byte_data;
                        22:fat16[7:0]<=byte_data;23:fat16[15:8]<=byte_data;
                        32:total32[7:0]<=byte_data;33:total32[15:8]<=byte_data;
                        34:total32[23:16]<=byte_data;35:total32[31:24]<=byte_data;
                        36:fat32[7:0]<=byte_data;37:fat32[15:8]<=byte_data;
                        38:fat32[23:16]<=byte_data;39:fat32[31:24]<=byte_data;
                        40:extflags[7:0]<=byte_data;41:extflags[15:8]<=byte_data;
                        42:version[7:0]<=byte_data;43:version[15:8]<=byte_data;
                        44:root32[7:0]<=byte_data;45:root32[15:8]<=byte_data;
                        46:root32[23:16]<=byte_data;47:root32[31:24]<=byte_data;
                        510:signature[7:0]<=byte_data;511:signature[15:8]<=byte_data;
                        default: begin end
                    endcase
                    for(i=0;i<4;i=i+1) begin
                        if(byte_index==450+i*16) partition_type[i]<=byte_data;
                        if(byte_index==454+i*16) partition_start[i][7:0]<=byte_data;
                        if(byte_index==455+i*16) partition_start[i][15:8]<=byte_data;
                        if(byte_index==456+i*16) partition_start[i][23:16]<=byte_data;
                        if(byte_index==457+i*16) partition_start[i][31:24]<=byte_data;
                        if(byte_index==458+i*16) partition_size[i][7:0]<=byte_data;
                        if(byte_index==459+i*16) partition_size[i][15:8]<=byte_data;
                        if(byte_index==460+i*16) partition_size[i][23:16]<=byte_data;
                        if(byte_index==461+i*16) partition_size[i][31:24]<=byte_data;
                    end
                    if(byte_last) state<=CLASSIFY;
                end
                CLASSIFY: if(signature!=16'haa55) begin
                    state<=IDLE;busy<=0;error<=1;error_code<=4;
                end else if(second_boot || looks_like_vbr) state<=CALCULATE;
                else begin
                    found=0;
                    for(i=0;i<4;i=i+1) begin
                        if(!found && (partition_type[i]==8'h0b || partition_type[i]==8'h0c) &&
                           partition_start[i]!=0 && partition_size[i]!=0) begin
                            volume_lba<=partition_start[i];sector_lba<=partition_start[i];
                            partition_limit<=partition_size[i];second_boot<=1;state<=ISSUE;found=1;
                        end
                    end
                    if(!found) begin state<=IDLE;busy<=0;error<=1;error_code<=5;end
                end
                CALCULATE: begin
                    // Only 1/2 FAT copies are accepted; use additions rather
                    // than inferring a wide multiplier from untrusted fields.
                    overhead=reserved+{32'd0,fat32}+((fats==2) ? {32'd0,fat32} : 64'd0);
                    data_sectors={32'd0,total32}-overhead;
                    count_wide=data_sectors >> log_spc(spc);
                    fat_base={32'd0,volume_lba}+reserved;
                    data_base={32'd0,volume_lba}+overhead;
                    active_fat=extflags[7] ? extflags[3:0] : 0;
                    active_base=fat_base+((active_fat==1) ? {32'd0,fat32} : 64'd0);
                    volume_end={32'd0,volume_lba}+{32'd0,total32};
                    fat_capacity={32'd0,fat32}<<7;
                    state<=VALIDATE;
                end
                VALIDATE: begin
                    if(bps!=512 || !spc_ok || reserved==0 || (fats!=1 && fats!=2) ||
                       roots16!=0 || fat16!=0 || total16!=0 || fat32==0 || version!=0 ||
                       overhead>=total32 || count_wide<65525 || count_wide>64'h0fffffee ||
                       fat_capacity<count_wide+2 || root32<2 || root32>count_wide+1 ||
                       active_fat>=fats || data_base>64'hffffffff ||
                       volume_end>64'h100000000 ||
                       (second_boot && total32>partition_limit)) begin
                        state<=IDLE;busy<=0;error<=1;error_code<=6;
                    end else begin
                        fat_lba<=active_base[31:0];data_lba<=data_base[31:0];
                        sectors_per_fat<=fat32;cluster_count<=count_wide[31:0];
                        sectors_per_cluster<=spc;root_cluster<=root32[27:0];
                        mounted<=1;done<=1;busy<=0;state<=IDLE;
                    end
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
