// Own startup supervisor. Enumerate first, then own the sector bus while loading.
// Published slots are immutable. Invalid files consume candidates, never slots.
module team_boot_loader #(
    parameter IMAGE_WIDTH=640, IMAGE_HEIGHT=480, ADDR_BITS=21,
    parameter WAIT_LIMIT=25000000, MAX_CANDIDATES=32
)(
    input wire clk,rst_n,start,
    output wire [3:0] slot_valid,
    output reg [2:0] image_count,
    output reg finished,failed,
    output reg [3:0] stage,error_code,
    output reg [15:0] rejected_count,
    output wire [31:0] fat_lba,data_lba,cluster_count,
    output wire [7:0] spc,
    output reg audio_found,output reg [27:0] audio_cluster,output reg [31:0] audio_size,
    output wire rd_req_valid,rd_cancel,
    input wire rd_req_ready,
    output wire [31:0] rd_req_lba,
    input wire rd_valid,
    output wire rd_ready,
    input wire [7:0] rd_data,
    input wire rd_last,rd_error,
    output wire wr_valid,
    input wire wr_ready,
    output wire [ADDR_BITS-1:0] wr_addr,
    output wire [31:0] wr_data,
    input wire wr_rsp_valid,wr_rsp_error
);
    localparam IDLE=0,MOUNT=1,CATALOG=2,ISSUE=3,LOAD=4,COMPLETE=5,FAIL=6;
    reg mount_start,cat_start;
    wire mounted,mdone,merror,cdone,cerror,limited,cvalid,lready,ldone,lfailed;
    wire [3:0] mcode,ccode,lcode;
    wire [31:0] volume_lba,sectors_per_fat;
    wire [27:0] root_cluster,ccluster;
    wire [31:0] csize;wire [87:0] cname;
    wire [15:0] candidate_count;
    reg [27:0] clusters[0:MAX_CANDIDATES-1];
    reg [31:0] sizes[0:MAX_CANDIDATES-1];
    reg [15:0] stored,index;
    wire [2:0] req,cancel,ready;
    wire [31:0] lba0,lba1,lba2;
    wire own0=(stage==MOUNT),own1=(stage==CATALOG),own2=(stage==ISSUE || stage==LOAD);
    assign rd_req_valid=(own0&&req[0])||(own1&&req[1])||(own2&&req[2]);
    assign rd_req_lba=own0?lba0:own1?lba1:lba2;
    assign rd_ready=(own0&&ready[0])||(own1&&ready[1])||(own2&&ready[2]);
    assign rd_cancel=(own0&&cancel[0])||(own1&&cancel[1])||(own2&&cancel[2]);
    team_fat32_mount #(.WAIT_LIMIT(WAIT_LIMIT)) mount(
        .clk(clk),.rst_n(rst_n),.start(mount_start),.busy(),.mounted(mounted),
        .done(mdone),.error(merror),.error_code(mcode),.volume_lba(volume_lba),
        .fat_lba(fat_lba),.data_lba(data_lba),.sectors_per_fat(sectors_per_fat),
        .cluster_count(cluster_count),.sectors_per_cluster(spc),.root_cluster(root_cluster),
        .rd_req_valid(req[0]),.rd_cancel(cancel[0]),.rd_req_ready(rd_req_ready&&own0),
        .rd_req_lba(lba0),.rd_valid(rd_valid&&own0),.rd_ready(ready[0]),.rd_data(rd_data),
        .rd_last(rd_last),.rd_error(rd_error&&own0));
    team_fat32_catalog #(.WAIT_LIMIT(WAIT_LIMIT),.MAX_CANDIDATES(MAX_CANDIDATES),.MIN_FILE_SIZE(44),.INCLUDE_WAV(1)) catalog(
        .clk(clk),.rst_n(rst_n),.start(cat_start),.fat_lba(fat_lba),.data_lba(data_lba),
        .cluster_count(cluster_count),.sectors_per_cluster(spc),.root_cluster(root_cluster),
        .busy(),.done(cdone),.error(cerror),.limited(limited),.error_code(ccode),
        .candidate_count(candidate_count),.candidate_valid(cvalid),
        .candidate_ready(stored<MAX_CANDIDATES),.candidate_name(cname),
        .candidate_cluster(ccluster),.candidate_size(csize),.rd_req_valid(req[1]),
        .rd_cancel(cancel[1]),.rd_req_ready(rd_req_ready&&own1),.rd_req_lba(lba1),
        .rd_valid(rd_valid&&own1),.rd_ready(ready[1]),.rd_data(rd_data),
        .rd_last(rd_last),.rd_error(rd_error&&own1));
    team_image_loader #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),
        .ADDR_BITS(ADDR_BITS),.WAIT_LIMIT(WAIT_LIMIT)) loader(
        .clk(clk),.rst_n(rst_n),.load_valid(stage==ISSUE && index<stored && image_count<4),
        .load_ready(lready),.load_slot(image_count[1:0]),.first_cluster(clusters[index]),
        .file_size(sizes[index]),.fat_lba(fat_lba),.data_lba(data_lba),.cluster_count(cluster_count),
        .sectors_per_cluster(spc),.busy(),.slot_valid(slot_valid),.load_done(ldone),
        .load_failed(lfailed),.result_slot(),.error_code(lcode),.rd_req_valid(req[2]),
        .rd_cancel(cancel[2]),.rd_req_ready(rd_req_ready&&own2),.rd_req_lba(lba2),
        .rd_valid(rd_valid&&own2),.rd_ready(ready[2]),.rd_data(rd_data),.rd_last(rd_last),
        .rd_error(rd_error&&own2),.wr_valid(wr_valid),.wr_ready(wr_ready),.wr_addr(wr_addr),
        .wr_data(wr_data),.wr_rsp_valid(wr_rsp_valid),.wr_rsp_error(wr_rsp_error));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            stage<=IDLE;error_code<=0;finished<=0;failed<=0;image_count<=0;
            stored<=0;index<=0;rejected_count<=0;mount_start<=0;cat_start<=0;
            audio_found<=0;audio_cluster<=0;audio_size<=0;
        end else begin
            mount_start<=0;cat_start<=0;
            if(stage==CATALOG && cvalid && stored<MAX_CANDIDATES) begin
                if((cname[23:16]=="W"||cname[23:16]=="w")&&
                   (cname[15:8]=="A"||cname[15:8]=="a")&&
                   (cname[7:0]=="V"||cname[7:0]=="v"))begin
                    if(!audio_found || cname=="AUDIO   WAV")begin
                        audio_found<=1;audio_cluster<=ccluster;audio_size<=csize;
                    end
                end else begin clusters[stored]<=ccluster;sizes[stored]<=csize;stored<=stored+1'b1;end
            end
            case(stage)
                IDLE:if(start) begin mount_start<=1;stage<=MOUNT;end
                MOUNT:if(merror) begin error_code<=mcode;failed<=1;stage<=FAIL;end
                      else if(mdone && mounted) begin cat_start<=1;stage<=CATALOG;end
                CATALOG:if(cerror) begin error_code<=ccode;failed<=1;stage<=FAIL;end
                        else if(cdone) stage<=ISSUE;
                ISSUE:if(image_count==4 || index>=stored) begin
                    finished<=1;failed<=(image_count<4);error_code<=(image_count<4)?4'hf:0;
                    stage<=COMPLETE;
                end else if(lready) stage<=LOAD;
                LOAD:if(ldone || lfailed) begin
                    if(ldone) image_count<=image_count+1'b1;
                    else rejected_count<=rejected_count+1'b1;
                    index<=index+1'b1;stage<=ISSUE;
                end
                default:begin end
            endcase
        end
    end
endmodule
