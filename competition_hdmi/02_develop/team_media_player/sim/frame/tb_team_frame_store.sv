`timescale 1ns/1ps
module tb_team_frame_store;
    parameter WIDTH=31, HEIGHT=17, BYTE_COUNT=6744;
    localparam N=WIDTH*HEIGHT;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0;
    reg load_start=0; reg [1:0] load_slot=0;
    wire load_ready,busy; wire [3:0] slot_valid;
    reg direct_mode=0;
    reg [23:0] direct_rgb=24'h123456;
    reg [15:0] direct_x=0,direct_y=0;
    reg direct_valid=0, direct_done=0, direct_error=0;
    reg file_done=0,file_error=0;
    wire pixel_ready,wr_valid; reg wr_ready=0;
    wire [20:0] wr_addr; wire [31:0] wr_data;
    wire rsp_valid,rsp_error;
    wire load_done,load_failed,abort_load;
    wire [1:0] result_slot; wire [3:0] error_code;
    reg parser_start=0; reg [31:0] file_size=0;
    reg [7:0] file_byte=0; reg file_valid=0,file_last=0;
    wire file_ready,parser_ready,parser_busy;
    wire [23:0] rgb; wire [15:0] px,py;
    wire pvalid,pdone,perror; wire [3:0] pcode;
    team_bmp_parser #(.IMAGE_WIDTH(WIDTH),.IMAGE_HEIGHT(HEIGHT)) parser(
        .clk(clk),.rst_n(rst_n),.start(parser_start),.file_size(file_size),
        .abort_file(abort_load),.start_ready(parser_ready),.busy(parser_busy),
        .file_byte(file_byte),.file_valid(file_valid),.file_ready(file_ready),
        .file_last(file_last),.pixel_rgb(rgb),.pixel_x(px),.pixel_y(py),
        .pixel_valid(pvalid),.pixel_ready(pixel_ready && !direct_mode),
        .image_done(pdone),.image_error(perror),.error_code(pcode));
    team_frame_store_writer #(.IMAGE_WIDTH(WIDTH),.IMAGE_HEIGHT(HEIGHT)) dut(
        .clk(clk),.rst_n(rst_n),.load_start(load_start),.load_slot(load_slot),
        .load_ready(load_ready),.busy(busy),.slot_valid(slot_valid),
        .pixel_rgb(direct_mode?direct_rgb:rgb),.pixel_x(direct_mode?direct_x:px),
        .pixel_y(direct_mode?direct_y:py),.pixel_valid(direct_mode?direct_valid:pvalid),
        .pixel_ready(pixel_ready),.image_done(direct_mode?direct_done:pdone),
        .image_error(direct_mode?direct_error:perror),.file_done(file_done),
        .file_error(file_error),.wr_valid(wr_valid),.wr_ready(wr_ready),
        .wr_addr(wr_addr),.wr_data(wr_data),.wr_rsp_valid(rsp_valid),
        .wr_rsp_error(rsp_error),.load_done(load_done),.load_failed(load_failed),
        .abort_load(abort_load),.result_slot(result_slot),.error_code(error_code));

    reg [7:0] bytes[0:BYTE_COUNT-1];
    reg [31:0] sizes[0:3];
    reg [23:0] expected[0:4*N-1];
    reg [31:0] memory[0:4*N-1];
    reg visited[0:4*N-1];
    string base,mode;
    integer seed=32'h1d872b45;
    integer i,j,k,case_checks=0,total_writes=0;
    integer accepted=0,completed=0,done_count=0,fail_count=0,parser_count=0;
    reg model_pending=0,model_rsp=0,model_fail=0;
    reg [20:0] model_addr=0; reg [31:0] model_data=0;
    integer response_delay=0,queued_number=0;
    integer fail_number=0;
    reg hold_request=0,hold_response=0,hold_last=0;
    reg zero_latency=0,unsolicited=0,compare_pixels=0;
    reg held=0; reg [20:0] held_addr; reg [31:0] held_data;
    assign rsp_valid = unsolicited || (zero_latency ? (wr_valid && wr_ready) : model_rsp);
    assign rsp_error = zero_latency ? ((accepted+1)==fail_number && fail_number!=0) : model_fail;

    // Source and response delays are independent. No simulation SDRAM model is
    // being represented as a real SDRAM controller: this is the write-port contract.
    always @(negedge clk) begin
        if (!rst_n) begin wr_ready=0; model_rsp=0; end
        else begin
            wr_ready = !model_pending && !hold_request && (($random(seed)&3)!=0);
            model_rsp=0;
            if (model_pending) begin
                if (response_delay>0) response_delay=response_delay-1;
                else if (!hold_response && !(hold_last && queued_number==N)) model_rsp=1;
            end
        end
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            model_pending=0; accepted=0; completed=0;
            done_count=0; fail_count=0; parser_count=0; held=0;
        end else begin
            if (held && (!wr_valid || wr_addr!==held_addr || wr_data!==held_data))
                $fatal(1,"offered memory write changed before acceptance");
            held=wr_valid && !wr_ready;
            if (held) begin held_addr=wr_addr; held_data=wr_data; end
            if (wr_valid && wr_ready) begin
                if (model_pending) $fatal(1,"more than one outstanding write");
                if (wr_addr>=4*N) $fatal(1,"write address exceeds four frames: %0d",wr_addr);
                if (wr_addr/N != load_slot) $fatal(1,"wrong slot address");
                if (slot_valid[wr_addr/N]) $fatal(1,"write into published slot");
                if (compare_pixels) begin
                    if (visited[wr_addr]) $fatal(1,"duplicate pixel write %0d",wr_addr);
                    if (wr_data!=={expected[wr_addr],8'd0})
                        $fatal(1,"pixel mismatch address=%0d got=%h expected=%h",wr_addr,wr_data,expected[wr_addr]);
                    visited[wr_addr]=1;
                end
                accepted=accepted+1; total_writes=total_writes+1;
                if (zero_latency) begin
                    if (!(fail_number!=0 && accepted==fail_number)) memory[wr_addr]=wr_data;
                    completed=completed+1;
                end else begin
                    model_pending=1; model_addr=wr_addr; model_data=wr_data;
                    queued_number=accepted;
                    model_fail=(fail_number!=0 && accepted==fail_number);
                    response_delay=($random(seed)&3);
                end
            end
            if (model_rsp && !zero_latency) begin
                if (!model_pending) $fatal(1,"model response with no request");
                if (!model_fail) memory[model_addr]=model_data;
                model_pending=0; completed=completed+1;
            end
            if (load_done) done_count=done_count+1;
            if (load_failed) fail_count=fail_count+1;
            if (pdone) parser_count=parser_count+1;
            if (perror && !direct_mode) $fatal(1,"unexpected BMP error %0d",pcode);
        end
    end

    task reset_all;
        begin
            @(negedge clk);rst_n=0;load_start=0;parser_start=0;file_valid=0;
            direct_valid=0;direct_done=0;direct_error=0;file_done=0;file_error=0;
            hold_request=0;hold_response=0;hold_last=0;unsolicited=0;fail_number=0;
            repeat(4) @(negedge clk);
            rst_n=1;
            for(integer a=0;a<4*N;a=a+1) begin memory[a]=32'hdeadbeef;visited[a]=0;end
        end
    endtask
    task start_direct(input [1:0] slot);
        begin
            direct_mode=1;compare_pixels=0;
            @(negedge clk);load_slot=slot;
            #1;if(!load_ready) $fatal(1,"new invalid slot not available");
            accepted=0;completed=0;
            load_start=1;
            @(negedge clk);load_start=0;
        end
    endtask
    task pixel(input integer x,input integer y);
        begin
            @(negedge clk);
            while(!pixel_ready) @(negedge clk);
            direct_x=x;direct_y=y;direct_valid=1;
            @(posedge clk);
            if(!pixel_ready) $fatal(1,"driver lost pixel readiness");
            @(negedge clk);direct_valid=0;
        end
    endtask
    task all_direct_pixels;
        begin
            for(integer y=0;y<HEIGHT;y=y+1)
                for(integer x=0;x<WIDTH;x=x+1) pixel(x,y);
        end
    endtask
    task signal_image_done;
        begin @(negedge clk);direct_done=1;@(negedge clk);direct_done=0;end
    endtask
    task signal_file_done;
        begin @(negedge clk);file_done=1;@(negedge clk);file_done=0;end
    endtask
    task wait_failure(input integer code);
        begin
            while(busy) @(negedge clk);
            if(error_code!==code || slot_valid[load_slot] || model_pending)
                $fatal(1,"wrong failure code=%0d expected=%0d valid=%h",error_code,code,slot_valid);
            repeat(3) @(negedge clk);
            if(fail_count!=1 || done_count!=0) $fatal(1,"failure result count");
            case_checks=case_checks+1;
        end
    endtask
    task run_image(input integer number,input [1:0] slot);
        integer offset,position,before_parser,before_done;
        begin
            direct_mode=0;compare_pixels=1;
            @(negedge clk);load_slot=slot;file_size=sizes[number];
            #1;if(!load_ready || !parser_ready) $fatal(1,"pipeline not ready");
            accepted=0;completed=0;before_parser=parser_count;before_done=done_count;
            load_start=1;parser_start=1;
            @(negedge clk);load_start=0;parser_start=0;
            offset=0;for(integer z=0;z<number;z=z+1) offset=offset+sizes[z];
            position=0;
            while(position<sizes[number]) begin
                @(negedge clk);
                // Only replace a held byte after it has been accepted.
                file_valid=(($random(seed)&3)!=0);
                file_byte=bytes[offset+position];file_last=(position==sizes[number]-1);
                if(file_valid) begin
                    @(posedge clk);
                    while(!file_ready) @(posedge clk);
                    position=position+1;
                end
            end
            @(negedge clk);file_valid=0;file_last=0;
            if(mode=="late_file_done") begin
                while(parser_count==before_parser || completed!=N) @(negedge clk);
                repeat(12) begin
                    @(negedge clk);if(slot_valid[slot] || !busy) $fatal(1,"published before clean file end");
                end
            end
            signal_file_done();
            if(hold_last) begin
                while(parser_count==before_parser || !model_pending || queued_number!=N) @(negedge clk);
                repeat(12) begin
                    @(negedge clk);if(slot_valid[slot] || !busy) $fatal(1,"published before last memory ACK");
                end
                hold_last=0;
            end
            while(busy) @(negedge clk);
            repeat(3) @(negedge clk);
            if(!slot_valid[slot] || done_count!=before_done+1 || fail_count!=0 || error_code!=0)
                $fatal(1,"image did not commit cleanly slot=%0d",slot);
            if(accepted!=N || completed!=N) $fatal(1,"wrong pixel count");
            for(integer a=slot*N;a<(slot+1)*N;a=a+1)
                if(!visited[a] || memory[a]!=={expected[a],8'd0}) $fatal(1,"final RAM comparison %0d",a);
            case_checks=case_checks+1;
        end
    endtask

    initial begin
        if(!$value$plusargs("BASE=%s",base)) $fatal(1,"BASE missing");
        if(!$value$plusargs("MODE=%s",mode)) mode="four_images";
        $readmemh({base,"/bytes.hex"},bytes);
        $readmemh({base,"/sizes.hex"},sizes);
        $readmemh({base,"/expected.hex"},expected);
        reset_all();
        if(mode=="four_images" || mode=="full_resolution" || mode=="late_write_ack" ||
           mode=="late_file_done" || mode=="zero_latency") begin
            zero_latency=(mode=="zero_latency");
            hold_last=(mode=="late_write_ack");
            run_image(0,2);run_image(1,0);run_image(2,3);run_image(3,1);
            if(slot_valid!==4'b1111) $fatal(1,"four slots not resident");
            @(negedge clk);load_slot=0;load_start=1;
            repeat(12) begin @(negedge clk);if(load_ready || busy || wr_valid) $fatal(1,"published slot overwritten");end
            load_start=0;case_checks=case_checks+1;
        end else if(mode=="bad_first_coordinate") begin
            start_direct(0);pixel(1,0);wait_failure(3);
        end else if(mode=="duplicate_coordinate") begin
            start_direct(0);pixel(0,0);pixel(0,0);wait_failure(3);
        end else if(mode=="out_of_range") begin
            start_direct(0);pixel(0,HEIGHT);wait_failure(3);
        end else if(mode=="early_image_done") begin
            start_direct(0);pixel(0,0);signal_image_done();wait_failure(4);
        end else if(mode=="abort_held_request") begin
            start_direct(0);hold_request=1;pixel(0,0);
            @(negedge clk);direct_error=1;
            @(negedge clk);direct_error=0;
            repeat(12) begin @(negedge clk);if(!busy || !wr_valid || slot_valid!=0) $fatal(1,"lost offered write on abort");end
            hold_request=0;wait_failure(1);
        end else if(mode=="abort_outstanding_response") begin
            start_direct(0);hold_response=1;pixel(0,0);
            while(!model_pending) @(negedge clk);
            file_error=1;@(negedge clk);file_error=0;
            repeat(12) begin @(negedge clk);if(!busy || slot_valid!=0) $fatal(1,"released slot before drain");end
            hold_response=0;wait_failure(2);
        end else if(mode=="write_error") begin
            start_direct(0);fail_number=2;pixel(0,0);pixel(1,0);wait_failure(5);
        end else if(mode=="unsolicited_response") begin
            start_direct(0);@(negedge clk);unsolicited=1;
            @(negedge clk);unsolicited=0;wait_failure(6);
        end else if(mode=="late_write_error") begin
            start_direct(0);hold_last=1;fail_number=N;all_direct_pixels();
            signal_image_done();signal_file_done();
            repeat(12) begin @(negedge clk);if(slot_valid!=0 || !busy) $fatal(1,"early commit");end
            hold_last=0;wait_failure(5);
        end else if(mode=="late_file_error") begin
            start_direct(0);all_direct_pixels();signal_image_done();
            while(completed!=N) @(negedge clk);
            repeat(12) begin @(negedge clk);if(slot_valid!=0 || !busy) $fatal(1,"file end was not required");end
            file_error=1;@(negedge clk);file_error=0;wait_failure(2);
        end else if(mode=="retry_failed_slot") begin
            start_direct(2);pixel(1,0);wait_failure(3);
            // Same invalid slot is usable again without global reset.
            fail_count=0;run_image(0,2);
        end else if(mode=="reset_pending") begin
            start_direct(0);hold_request=1;pixel(0,0);
            repeat(3) @(negedge clk);reset_all();
            if(busy || wr_valid || slot_valid!=0) $fatal(1,"reset did not cancel metadata");
            run_image(0,2);
        end else $fatal(1,"unknown mode %s",mode);
        $display("TEST_PASS mode=%s checks=%0d writes=%0d slots=%h",mode,case_checks,total_writes,slot_valid);
        $finish;
    end
    initial begin #2000000000; $fatal(1,"watchdog: frame store did not terminate");end
endmodule
