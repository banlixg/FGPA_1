`timescale 1ns/1ps
module tb_team_image_loader;
    parameter WIDTH=31,HEIGHT=17,MAX_LBA=3500;
    localparam N=WIDTH*HEIGHT;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,load_valid=0;reg [1:0] load_slot=0;
    reg [27:0] first_cluster=0;reg [31:0] file_size=0;
    reg [31:0] fat_lba,data_lba,cluster_count;
    reg [7:0] spc;
    wire load_ready,busy,load_done,load_failed;
    wire [3:0] slot_valid,error_code;wire [1:0] result_slot;
    wire req_valid,cancel,rd_ready;wire [31:0] req_lba;
    reg bus_active=0,bus_valid=0,bus_last=0,bus_error=0;
    reg [7:0] bus_data=0;
    integer bus_lba=0,bus_index=0,requests=0;
    reg byte_taken=0;
    reg [31:0] random_state=32'h9185ac31;
    wire req_ready=!bus_active && random_state[4];
    wire wr_valid;reg wr_ready=0;wire [20:0] wr_addr;wire [31:0] wr_data;
    reg rsp_valid=0,rsp_error=0;
    team_image_loader #(.IMAGE_WIDTH(WIDTH),.IMAGE_HEIGHT(HEIGHT),.WAIT_LIMIT(64)) dut(
        .clk(clk),.rst_n(rst_n),.load_valid(load_valid),.load_ready(load_ready),
        .load_slot(load_slot),.first_cluster(first_cluster),.file_size(file_size),
        .fat_lba(fat_lba),.data_lba(data_lba),.cluster_count(cluster_count),.sectors_per_cluster(spc),
        .busy(busy),.slot_valid(slot_valid),.load_done(load_done),.load_failed(load_failed),
        .result_slot(result_slot),.error_code(error_code),
        .rd_req_valid(req_valid),.rd_cancel(cancel),.rd_req_ready(req_ready),.rd_req_lba(req_lba),
        .rd_valid(bus_valid),.rd_ready(rd_ready),.rd_data(bus_data),.rd_last(bus_last),.rd_error(bus_error),
        .wr_valid(wr_valid),.wr_ready(wr_ready),.wr_addr(wr_addr),.wr_data(wr_data),
        .wr_rsp_valid(rsp_valid),.wr_rsp_error(rsp_error));
    reg [7:0] card[0:(MAX_LBA+1)*512-1];
    reg present[0:MAX_LBA];
    reg [147:0] entries[0:3];
    reg [55:0] pixels[0:4*N-1];
    reg [31:0] memory[0:4*N-1];
    reg [55:0] expected_pixel;
    string base,mode;
    integer dummy,file_index=0,writes=0,acks=0,valid_frames=0,total_writes=0;
    integer expected_addr,checks=0;
    reg mem_pending=0,mem_fail=0;
    reg [20:0] mem_addr;reg [31:0] mem_data;
    integer mem_delay=0;
    reg done_seen=0,failed_seen=0,injected=0;
    always @(posedge clk) begin
        if(rst_n) begin
            byte_taken=bus_valid && rd_ready;
            if(cancel) begin bus_active<=0;byte_taken=0;end
            else if(bus_active && byte_taken) begin
                if(bus_last) bus_active<=0;else bus_index=bus_index+1;
            end else if(!bus_active && req_valid && req_ready) begin
                bus_lba=req_lba;bus_index=0;bus_active<=1;requests=requests+1;
                if(bus_lba>MAX_LBA || present[bus_lba]!==1'b1) $fatal(1,"unexpected LBA %0d",bus_lba);
            end
            if(wr_valid && wr_ready) begin
                if(mem_pending || writes>=N || slot_valid[load_slot]) $fatal(1,"invalid memory request");
                expected_pixel=pixels[file_index*N+writes];
                expected_addr=load_slot*N+expected_pixel[39:24]*WIDTH+expected_pixel[55:40];
                if(wr_addr!==expected_addr || wr_data!=={expected_pixel[23:0],8'd0})
                    $fatal(1,"FAT/BMP/frame address or RGB mismatch file=%0d pixel=%0d address=%0d expected=%0d",file_index,writes,wr_addr,expected_addr);
                writes=writes+1;total_writes=total_writes+1;
                mem_pending=1;mem_addr=wr_addr;mem_data=wr_data;mem_delay=random_state[2:1];
                mem_fail=(mode=="loader_memory_error_retry" && file_index==0 && writes==3);
            end
            if(rsp_valid) begin
                if(!mem_pending) $fatal(1,"bad memory model response");
                if(!rsp_error) memory[mem_addr]=mem_data;
                mem_pending=0;acks=acks+1;
            end
            if(load_done) done_seen=1;
            if(load_failed) failed_seen=1;
        end
    end
    always @(negedge clk) begin
        random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
        wr_ready=rst_n && !mem_pending && (random_state[5:3]!=0);
        rsp_valid=0;rsp_error=0;
        if(mem_pending) begin
            if(mem_delay>0) mem_delay=mem_delay-1;
            else begin rsp_valid=1;rsp_error=mem_fail;end
        end
        if(!rst_n || !bus_active) begin bus_valid=0;bus_error=0;bus_last=0;end
        else if(mode=="loader_drain_error_retry" && file_index==0 && !injected && dut.writer.image_ok) begin
            bus_valid=0;bus_error=1;injected=1;
        end else if(bus_error) begin bus_valid=0;end
        else if(bus_valid && !byte_taken) begin end
        else begin
            bus_valid=(random_state[2:0]!=0);bus_error=0;
            bus_data=card[bus_lba*512+bus_index];bus_last=(bus_index==511);
        end
    end
    initial begin
        if(!$value$plusargs("BASE=%s",base)) $fatal(1,"BASE missing");
        if(!$value$plusargs("MODE=%s",mode)) $fatal(1,"MODE missing");
        dummy=$value$plusargs("FAT=%d",fat_lba);dummy=$value$plusargs("DATA=%d",data_lba);
        dummy=$value$plusargs("CLUSTERS=%d",cluster_count);dummy=$value$plusargs("SPC=%d",spc);
        $readmemh({base,"/card.hex"},card);$readmemh({base,"/present.hex"},present);
        $readmemh({base,"/entries.hex"},entries);$readmemh({base,"/pixels.hex"},pixels);
        for(integer a=0;a<4*N;a=a+1) memory[a]=32'hdeadbeef;
        if(mode=="loader_bad_bmp_retry")
            card[(data_lba+(entries[0][59:32]-2)*spc)*512+28]=32;
        repeat(4) @(negedge clk);rst_n=1;
        for(file_index=0;file_index<4;file_index=file_index+1) begin
            @(negedge clk);load_slot=valid_frames;
            first_cluster=entries[file_index][59:32];file_size=entries[file_index][31:0];
            writes=0;acks=0;done_seen=0;failed_seen=0;
            #1;if(!load_ready) $fatal(1,"loader did not become ready after previous file");
            load_valid=1;@(negedge clk);load_valid=0;
            while(!done_seen && !failed_seen) @(negedge clk);
            if(busy || bus_active || mem_pending) $fatal(1,"job returned before all transactions drained");
            if(file_index==0 && (mode=="loader_bad_bmp_retry" || mode=="loader_drain_error_retry" || mode=="loader_memory_error_retry")) begin
                if(!failed_seen || slot_valid!=0) $fatal(1,"bad file became a valid frame");
                if(mode=="loader_bad_bmp_retry" && error_code!=1) $fatal(1,"wrong BMP error");
                if(mode=="loader_drain_error_retry" && (error_code!=2 || writes!=N || !injected)) $fatal(1,"drain error not propagated");
                if(mode=="loader_memory_error_retry" && error_code!=5) $fatal(1,"memory error not propagated");
            end else begin
                if(!done_seen || writes!=N || acks!=N || error_code!=0 || result_slot!=valid_frames)
                    $fatal(1,"complete file failed to commit");
                for(integer a=0;a<N;a=a+1) begin
                    expected_pixel=pixels[file_index*N+a];
                    expected_addr=valid_frames*N+expected_pixel[39:24]*WIDTH+expected_pixel[55:40];
                    if(memory[expected_addr]!=={expected_pixel[23:0],8'd0}) $fatal(1,"resident frame comparison failed");
                end
                valid_frames=valid_frames+1;
                if(slot_valid!=((1<<valid_frames)-1)) $fatal(1,"wrong residency mask");
            end
            checks=checks+1;
            repeat(3) @(negedge clk);
        end
        $display("TEST_PASS mode=%s files=%0d resident=%0d checks=%0d writes=%0d sector_requests=%0d",mode,file_index,valid_frames,checks,total_writes,requests);
        $finish;
    end
    initial begin #2000000000;$fatal(1,"loader watchdog");end
endmodule
