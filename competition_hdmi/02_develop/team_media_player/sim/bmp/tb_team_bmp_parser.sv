`timescale 1ns/1ps
module tb_team_bmp_parser;
    parameter integer WIDTH=640, HEIGHT=480, INPUT_CAP=1048576;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, start=0, abort_file=0;
    reg [31:0] file_size=0;
    reg [7:0] file_byte=0;
    reg file_valid=0, file_last=0, pixel_ready=0;
    wire start_ready, busy, file_ready, pixel_valid, image_done, image_error;
    wire [23:0] pixel_rgb;
    wire [15:0] pixel_x, pixel_y;
    wire [3:0] error_code;
    team_bmp_parser #(.IMAGE_WIDTH(WIDTH),.IMAGE_HEIGHT(HEIGHT)) dut(.*);

    reg [7:0] input_mem[0:INPUT_CAP-1];
    reg [55:0] expected_mem[0:WIDTH*HEIGHT-1];
    reg [2047:0] input_path, expected_path;
    integer byte_count, expected_count, expected_error, source_size;
    integer abort_after, repeats, repeat_index;
    integer input_index=0, received=0, cycles=0;
    integer stall_cycles=0, input_stalls=0;
    reg input_taken=0, finished=0;
    reg held_pixel=0;
    reg [55:0] held_value;
    reg [31:0] random_state=32'h1a2b3c4d;
    integer dummy;

    initial begin
        dummy=$value$plusargs("INPUT=%s",input_path);
        dummy=$value$plusargs("EXPECTED=%s",expected_path);
        dummy=$value$plusargs("BYTES=%d",byte_count);
        dummy=$value$plusargs("PIXELS=%d",expected_count);
        dummy=$value$plusargs("ERROR=%d",expected_error);
        dummy=$value$plusargs("SOURCE_SIZE=%d",source_size);
        abort_after=-1;
        dummy=$value$plusargs("ABORT_AFTER=%d",abort_after);
        repeats=1;
        dummy=$value$plusargs("REPEATS=%d",repeats);
        if (byte_count<1 || byte_count>INPUT_CAP || expected_count>WIDTH*HEIGHT)
            $fatal(1,"Bad fixture limits");
        $readmemh(input_path,input_mem,0,byte_count-1);
        if(expected_count>0)
            $readmemh(expected_path,expected_mem,0,expected_count-1);
        file_size=source_size;
        repeat(4) @(negedge clk);
        rst_n=1;
        for(repeat_index=0;repeat_index<repeats;repeat_index=repeat_index+1) begin
            @(negedge clk);
            if(!start_ready) $fatal(1,"Start not accepted after prior image");
            start=1;
            @(negedge clk);
            start=0;
            wait(finished);
            repeat(3) @(negedge clk);
            if(busy || pixel_valid || !start_ready)
                $fatal(1,"Terminal state did not release parser");
        end
        $display("TEST_PASS pixels=%0d received=%0d error=%0d repeats=%0d output_stalls=%0d input_stalls=%0d",
                 expected_count,received,expected_error,repeats,stall_cycles,input_stalls);
        $finish;
    end

    // The driver changes data only after a measured input handshake. It injects
    // independent source gaps and sink stalls, and holds every byte until taken.
    always @(negedge clk) begin
        if(!rst_n || !busy || finished) begin
            file_valid=0;
            file_last=0;
            abort_file=0;
            pixel_ready=0;
        end else begin
            random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            pixel_ready=(random_state[3:0]>=6);
            if(file_valid && !input_taken) begin end
            else if(input_index<byte_count) begin
                file_valid=(random_state[7:4]>=3);
                file_byte=input_mem[input_index];
                file_last=(input_index==byte_count-1);
            end else begin
                file_valid=0;
                file_last=0;
            end
            abort_file=(abort_after>=0 && input_index>=abort_after);
        end
    end

    always @(posedge clk) begin
        if(!rst_n || start) begin
            input_index=0;
            received=0;
            cycles=0;
            stall_cycles=0;
            input_stalls=0;
            input_taken=0;
            held_pixel=0;
            finished=0;
        end else if(!finished) begin
            cycles=cycles+1;
            input_taken=file_valid && file_ready;
            if(input_taken) input_index=input_index+1;
            if(file_valid && !file_ready) input_stalls=input_stalls+1;
            if(held_pixel && !abort_file && !image_error) begin
                if(!pixel_valid || {pixel_x,pixel_y,pixel_rgb} !== held_value)
                    $fatal(1,"Output changed while backpressured");
            end
            held_pixel=pixel_valid && !pixel_ready && !abort_file;
            held_value={pixel_x,pixel_y,pixel_rgb};
            if(pixel_valid && !pixel_ready) stall_cycles=stall_cycles+1;
            if(pixel_valid && pixel_ready) begin
                if(received>=expected_count)
                    $fatal(1,"Unexpected extra pixel %0d",received);
                if({pixel_x,pixel_y,pixel_rgb} !== expected_mem[received])
                    $fatal(1,"Pixel mismatch at %0d got=%014h expected=%014h",received,
                           {pixel_x,pixel_y,pixel_rgb},expected_mem[received]);
                received=received+1;
            end
            if(image_done && image_error) $fatal(1,"Both terminal signals asserted");
            if(image_done) begin
                if(expected_error!=0 || received!=expected_count)
                    $fatal(1,"Unexpected success/count error=%0d pixels=%0d/%0d",expected_error,received,expected_count);
                if(busy || pixel_valid) $fatal(1,"Success preceded final pixel acceptance");
                finished=1;
            end
            if(image_error) begin
                if(expected_error==0 || error_code!=expected_error)
                    $fatal(1,"Wrong error: got %0d expected %0d",error_code,expected_error);
                finished=1;
            end
            if(cycles>16000000) $fatal(1,"Simulation watchdog expired");
        end else if(image_done || image_error) begin
            $fatal(1,"Terminal signal persisted for multiple cycles");
        end
    end
endmodule
