`timescale 1ns/1ps
module tb_wav;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,start=0,abort_file=0;wire idle,busy,done,error;wire [3:0] code;
    reg valid=0;wire ready;reg [7:0] byte_data;reg last=0;
    wire sv;reg sr=0;wire [31:0] sample;
    parameter SIZE=1000,SAMPLES=100,ERROR=0;
    reg [7:0] file_bytes[0:SIZE-1];reg [31:0] expected[0:SAMPLES-1];
    integer pos=0,count=0;string base;reg [31:0] rng=32'h918af4c1;
    reg was_taken=0,finish_seen=0;
    team_wav_parser dut(.clk(clk),.rst_n(rst_n),.start(start),.abort_file(abort_file),.file_size(SIZE),
        .idle(idle),.busy(busy),.done(done),.error(error),.error_code(code),
        .file_valid(valid),.file_ready(ready),.file_byte(byte_data),.file_last(last),
        .sample_valid(sv),.sample_ready(sr),.sample_data(sample));
    always @(posedge clk)if(rst_n)begin
        was_taken=valid&&ready;
        if(was_taken)pos=pos+1;
        if(sv&&sr)begin if(count>=SAMPLES||sample!==expected[count])$fatal(1,"WAV sample %0d got %h",count,sample);count=count+1;end
        if(done||error)begin
            if(ERROR==0&&(!done||count!=SAMPLES))$fatal(1,"valid WAV rejected %0d samples=%0d",code,count);
            if(ERROR!=0&&(!error||code!=ERROR))$fatal(1,"bad WAV accepted/code=%0d",code);
            finish_seen=1;
        end
    end
    always @(negedge clk)begin
        rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};sr=(rng[2:0]==0);
        if(!rst_n)valid=0;
        else if(!valid||was_taken)begin valid=(pos<SIZE&&rng[3]);byte_data=file_bytes[pos];last=(pos==SIZE-1);end
    end
    initial begin
        if(!$value$plusargs("BASE=%s",base))$fatal(1,"BASE");
        $readmemh({base,"/wav.hex"},file_bytes);$readmemh({base,"/samples.hex"},expected);
        repeat(4)@(negedge clk);rst_n=1;start=1;@(negedge clk);start=0;
        wait(finish_seen);$display("TEST_PASS WAV bytes=%0d samples=%0d expected_error=%0d",pos,count,ERROR);$finish;
    end
    initial begin #20000000;$fatal(1,"WAV watchdog state=%0d pos=%0d",dut.state,pos);end
endmodule
