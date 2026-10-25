`timescale 1ns/1ps
module tb_team_fat32;
    parameter integer WIDTH=3, HEIGHT=2, MAX_LBA=4096, EXPECTED_BYTES=1024, FILES=4;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, mount_start=0, scan_start=0, reader_start=0, parser_start=0;
    integer phase=0, file_index=0;
    wire mount_busy,mounted,mount_done,mount_error,scan_busy,scan_done,scan_error,limited;
    wire reader_busy,reader_done,reader_error;
    wire [3:0] mount_code,scan_code,reader_code;
    wire [31:0] volume_lba,fat_lba,data_lba,sectors_per_fat,cluster_count;
    wire [7:0] spc;
    wire [27:0] root_cluster;
    wire [15:0] candidate_count;
    wire candidate_valid;
    reg candidate_ready=0;
    wire [87:0] candidate_name;
    wire [27:0] candidate_cluster;
    wire [31:0] candidate_size;
    reg [27:0] first_cluster=0;
    reg [31:0] opened_size=0;
    wire [31:0] file_position;
    wire file_valid,file_ready,file_last;
    wire [7:0] file_byte;
    wire [2:0] req_valid,cancel,req_ready,byte_ready;
    wire [31:0] req_lba[0:2];
    reg bus_active=0, bus_valid=0, bus_last=0, bus_error=0;
    reg [7:0] bus_data=0;
    integer bus_index=0,bus_lba=0;
    reg byte_taken=0;
    reg [31:0] random_state=32'h7693ac51;
    wire request_ready=!bus_active && random_state[4];
    assign req_ready[0]=(phase==0) && request_ready;
    assign req_ready[1]=(phase==1) && request_ready;
    assign req_ready[2]=(phase==2) && request_ready;

    team_fat32_mount #(.WAIT_LIMIT(64)) mount(
        .clk(clk),.rst_n(rst_n),.start(mount_start),.busy(mount_busy),.mounted(mounted),
        .done(mount_done),.error(mount_error),.error_code(mount_code),
        .volume_lba(volume_lba),.fat_lba(fat_lba),.data_lba(data_lba),
        .sectors_per_fat(sectors_per_fat),.cluster_count(cluster_count),
        .sectors_per_cluster(spc),.root_cluster(root_cluster),
        .rd_req_valid(req_valid[0]),.rd_cancel(cancel[0]),.rd_req_ready(req_ready[0]),.rd_req_lba(req_lba[0]),
        .rd_valid(bus_valid && phase==0),.rd_ready(byte_ready[0]),.rd_data(bus_data),
        .rd_last(bus_last),.rd_error(bus_error && phase==0));
    team_fat32_catalog #(.WAIT_LIMIT(64),.MAX_CANDIDATES(32),.MAX_DIR_CLUSTERS(16)) catalog(
        .clk(clk),.rst_n(rst_n),.start(scan_start),.fat_lba(fat_lba),.data_lba(data_lba),
        .cluster_count(cluster_count),.sectors_per_cluster(spc),.root_cluster(root_cluster),
        .busy(scan_busy),.done(scan_done),.error(scan_error),.limited(limited),.error_code(scan_code),
        .candidate_count(candidate_count),.candidate_valid(candidate_valid),.candidate_ready(candidate_ready),
        .candidate_name(candidate_name),.candidate_cluster(candidate_cluster),.candidate_size(candidate_size),
        .rd_req_valid(req_valid[1]),.rd_cancel(cancel[1]),.rd_req_ready(req_ready[1]),.rd_req_lba(req_lba[1]),
        .rd_valid(bus_valid && phase==1),.rd_ready(byte_ready[1]),.rd_data(bus_data),
        .rd_last(bus_last),.rd_error(bus_error && phase==1));

    integer close_after=-1, image_mode=0;
    integer bytes_received=0, pixels_received=0;
    wire image_done,image_error,pixel_valid,parser_ready,parser_busy,parser_start_ready;
    wire [3:0] image_code;
    wire [23:0] pixel_rgb;
    wire [15:0] pixel_x,pixel_y;
    reg pixel_ready=0;
    wire close_file=(close_after>=0 && bytes_received>=close_after) ||
                    (image_mode!=0 && (image_done || image_error));
    assign file_ready=(image_mode!=0) ? parser_ready : random_state[7];
    team_fat32_file_reader #(.WAIT_LIMIT(64)) reader(
        .clk(clk),.rst_n(rst_n),.start(reader_start),.close_file(close_file),
        .fat_lba(fat_lba),.data_lba(data_lba),.cluster_count(cluster_count),
        .sectors_per_cluster(spc),.first_cluster(first_cluster),.file_size(opened_size),
        .busy(reader_busy),.done(reader_done),.error(reader_error),.error_code(reader_code),
        .file_position(file_position),.file_valid(file_valid),.file_ready(file_ready),
        .file_byte(file_byte),.file_last(file_last),
        .rd_req_valid(req_valid[2]),.rd_cancel(cancel[2]),.rd_req_ready(req_ready[2]),.rd_req_lba(req_lba[2]),
        .rd_valid(bus_valid && phase==2),.rd_ready(byte_ready[2]),.rd_data(bus_data),
        .rd_last(bus_last),.rd_error(bus_error && phase==2));
    team_bmp_parser #(.IMAGE_WIDTH(WIDTH),.IMAGE_HEIGHT(HEIGHT)) bmp(
        .clk(clk),.rst_n(rst_n),.start(parser_start),.file_size(opened_size),.abort_file(reader_error),
        .start_ready(parser_start_ready),.busy(parser_busy),.file_byte(file_byte),
        .file_valid(file_valid && image_mode!=0),.file_ready(parser_ready),.file_last(file_last),
        .pixel_rgb(pixel_rgb),.pixel_x(pixel_x),.pixel_y(pixel_y),.pixel_valid(pixel_valid),
        .pixel_ready(pixel_ready),.image_done(image_done),.image_error(image_error),.error_code(image_code));

    reg [7:0] card[0:(MAX_LBA+1)*512-1];
    reg present[0:MAX_LBA];
    reg [147:0] expected_entries[0:31];
    reg [147:0] captured_entries[0:31];
    reg [7:0] expected_bytes[0:EXPECTED_BYTES-1];
    reg [55:0] expected_pixels[0:((WIDTH*HEIGHT*FILES)>0 ? WIDTH*HEIGHT*FILES : 1)-1];
    reg [2047:0] image_path,present_path,entries_path,bytes_path,pixels_path;
    integer dummy,expected_mount,expected_scan,expected_file,inject,num_files;
    integer expected_volume,expected_fat,expected_data,expected_spc,expected_clusters;
    integer entries_received=0,byte_base=0,total_pixels=0,cycles=0,requests=0;
    reg reader_done_seen=0,reader_error_seen=0,image_done_seen=0,image_error_seen=0;
    reg held_candidate=0;
    reg [147:0] held_entry;

    task pass;
        input [63:0] location;
        begin
            $display("TEST_PASS stage=%s files=%0d pixels=%0d sector_requests=%0d",
                     location,entries_received,total_pixels,requests);
            $finish;
        end
    endtask
    initial begin
        dummy=$value$plusargs("IMAGE=%s",image_path);
        dummy=$value$plusargs("PRESENT=%s",present_path);
        dummy=$value$plusargs("ENTRIES=%s",entries_path);
        dummy=$value$plusargs("BYTES=%s",bytes_path);
        dummy=$value$plusargs("PIXELS=%s",pixels_path);
        dummy=$value$plusargs("MOUNT_ERROR=%d",expected_mount);
        dummy=$value$plusargs("SCAN_ERROR=%d",expected_scan);
        dummy=$value$plusargs("FILE_ERROR=%d",expected_file);
        dummy=$value$plusargs("INJECT=%d",inject);
        dummy=$value$plusargs("NUM_FILES=%d",num_files);
        dummy=$value$plusargs("IMAGE_MODE=%d",image_mode);
        dummy=$value$plusargs("CLOSE_AFTER=%d",close_after);
        dummy=$value$plusargs("VOLUME=%d",expected_volume);
        dummy=$value$plusargs("FAT=%d",expected_fat);
        dummy=$value$plusargs("DATA=%d",expected_data);
        dummy=$value$plusargs("SPC=%d",expected_spc);
        dummy=$value$plusargs("CLUSTERS=%d",expected_clusters);
        $readmemh(image_path,card);
        $readmemh(present_path,present);
        if(num_files>0) begin
            $readmemh(entries_path,expected_entries,0,num_files-1);
            $readmemh(bytes_path,expected_bytes,0,EXPECTED_BYTES-1);
            if(image_mode!=0)
                $readmemh(pixels_path,expected_pixels,0,WIDTH*HEIGHT*num_files-1);
        end
        repeat(4) @(negedge clk);rst_n=1;
        @(negedge clk);mount_start=1;
        @(negedge clk);mount_start=0;
        wait(mount_done || mount_error);
        if(expected_mount!=0) begin
            if(!mount_error || mount_code!=expected_mount) $fatal(1,"Wrong mount error %0d",mount_code);
            pass("mount");
        end
        if(mount_error || !mounted) $fatal(1,"Unexpected mount error %0d",mount_code);
        if(volume_lba!=expected_volume || fat_lba!=expected_fat || data_lba!=expected_data ||
           spc!=expected_spc || cluster_count!=expected_clusters || root_cluster!=5)
            $fatal(1,"Geometry mismatch vol=%0d fat=%0d data=%0d spc=%0d count=%0d root=%0d",
                   volume_lba,fat_lba,data_lba,spc,cluster_count,root_cluster);
        @(negedge clk);phase=1;scan_start=1;
        @(negedge clk);scan_start=0;
        wait(scan_done || scan_error);
        if(expected_scan!=0) begin
            if(!scan_error || scan_code!=expected_scan) $fatal(1,"Wrong catalog error %0d",scan_code);
            pass("catalog");
        end
        if(scan_error || limited || entries_received!=num_files || candidate_count!=num_files)
            $fatal(1,"Catalog mismatch error=%0d count=%0d/%0d limited=%0d",scan_code,entries_received,num_files,limited);
        for(file_index=0;file_index<num_files;file_index=file_index+1) begin
            @(negedge clk);
            phase=2;first_cluster=captured_entries[file_index][59:32];
            opened_size=captured_entries[file_index][31:0];
            reader_start=1;parser_start=(image_mode!=0);
            @(negedge clk);reader_start=0;parser_start=0;
            wait(reader_done_seen || reader_error_seen);
            if(expected_file!=0) begin
                if(!reader_error_seen || reader_code!=expected_file) $fatal(1,"Wrong file error %0d",reader_code);
                pass("file_err");
            end
            if(reader_error_seen) $fatal(1,"Unexpected file error %0d",reader_code);
            if(close_after>=0) begin
                if(bytes_received!=close_after) $fatal(1,"Early close count %0d",bytes_received);
            end else if(bytes_received!=opened_size) $fatal(1,"File size mismatch %0d/%0d",bytes_received,opened_size);
            if(image_mode!=0) begin
                wait(image_done_seen || image_error_seen);
                if(image_error_seen || pixels_received!=WIDTH*HEIGHT)
                    $fatal(1,"Image decode failed code=%0d pixels=%0d",image_code,pixels_received);
            end
            byte_base=byte_base+opened_size;
            repeat(3) @(negedge clk);
        end
        pass("complete");
    end

    // A strict sector model: only sectors explicitly present in the fixture may
    // be requested. Random source gaps and sink stalls stress ready/valid.
    always @(posedge clk) begin
        if(rst_n) begin
            cycles=cycles+1;
            if(cycles>100000000) $fatal(1,"Watchdog phase=%0d",phase);
            byte_taken=bus_valid && byte_ready[phase];
            if(cancel[phase]) begin bus_active<=0;byte_taken=0;end
            else if(bus_active && byte_taken) begin
                if(bus_last) bus_active<=0;
                else bus_index=bus_index+1;
            end else if(!bus_active && req_valid[phase] && request_ready) begin
                bus_lba=req_lba[phase];bus_index=0;bus_active<=1;requests=requests+1;
                if(bus_lba>MAX_LBA || present[bus_lba]!==1'b1)
                    $fatal(1,"Unexpected sector request LBA=%0d phase=%0d",bus_lba,phase);
            end
        end
    end
    always @(negedge clk) begin
        random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
        candidate_ready=(random_state[5:2]>5);
        pixel_ready=(random_state[9:6]>5);
        if(!rst_n || !bus_active) begin bus_valid=0;bus_error=0;bus_last=0;end
        else if(inject==1 && phase==0 && bus_index==10) begin bus_valid=0;bus_error=1;end
        else if(inject==3 && phase==0) begin bus_valid=0;bus_error=0;end
        else if(bus_valid && !byte_taken) begin end
        else begin
            bus_error=0;bus_valid=(random_state[2:0]!=0);
            bus_data=card[bus_lba*512+bus_index];
            bus_last=(bus_index==511) || (inject==2 && phase==0 && bus_index==7);
        end
    end
    always @(posedge clk) begin
        if(rst_n) begin
            if(held_candidate && {candidate_name,candidate_cluster,candidate_size}!==held_entry)
                $fatal(1,"Candidate changed during backpressure");
            held_candidate=candidate_valid && !candidate_ready;
            held_entry={candidate_name,candidate_cluster,candidate_size};
            if(candidate_valid && candidate_ready) begin
                if(entries_received>=num_files || held_entry!==expected_entries[entries_received])
                    $fatal(1,"Wrong directory candidate %0d got=%037h expected=%037h",entries_received,held_entry,expected_entries[entries_received]);
                captured_entries[entries_received]=held_entry;entries_received=entries_received+1;
            end
            if(reader_start) begin
                bytes_received<=0;pixels_received<=0;
                reader_done_seen=0;reader_error_seen=0;image_done_seen=0;image_error_seen=0;
            end else if(phase==2) begin
                if(file_valid && file_ready) begin
                    if(bytes_received>=opened_size || file_byte!==expected_bytes[byte_base+bytes_received] ||
                       file_position!=bytes_received || file_last!=(bytes_received==opened_size-1))
                        $fatal(1,"File byte mismatch file=%0d offset=%0d data=%02h expected=%02h pos=%0d",
                               file_index,bytes_received,file_byte,expected_bytes[byte_base+bytes_received],file_position);
                    bytes_received<=bytes_received+1;
                end
                if(pixel_valid && pixel_ready) begin
                    if(pixels_received>=WIDTH*HEIGHT || {pixel_x,pixel_y,pixel_rgb}!==expected_pixels[file_index*WIDTH*HEIGHT+pixels_received])
                        $fatal(1,"Decoded image pixel mismatch file=%0d pixel=%0d",file_index,pixels_received);
                    pixels_received<=pixels_received+1;total_pixels=total_pixels+1;
                end
                if(reader_done) reader_done_seen=1;
                if(reader_error) reader_error_seen=1;
                if(image_done) image_done_seen=1;
                if(image_error) image_error_seen=1;
            end
        end
    end
endmodule
