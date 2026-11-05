// RIFF/WAVE chunk walker, PCM format 1, 48 kHz, signed 16-bit mono/stereo.
// Unknown chunks and odd padding are skipped; no fixed 44-byte-header assumption.
module team_wav_parser(
    input wire clk,rst_n,start,abort_file,input wire [31:0] file_size,
    output wire idle,output reg busy,done,error,output reg [3:0] error_code,
    input wire file_valid,output wire file_ready,input wire [7:0] file_byte,input wire file_last,
    output reg sample_valid,input wire sample_ready,output reg [31:0] sample_data
);
    localparam IDLE=0,RIFF=1,CHUNK=2,CHECK=3,FMT=4,SKIP=5,DATA=6,PAD=7,FINISH=8;
    reg [3:0] state;reg [31:0] pos,size,limit,chunk_id,chunk_size,remaining,index;
    reg [31:0] riff_id,wave_id,riff_size,sample_rate,byte_rate;
    reg [15:0] format,channels,alignment,bits;
    reg format_ok,odd_pad;reg [1:0] part;reg [15:0] left;
    reg [7:0] low;
    assign idle=(state==IDLE);
    assign file_ready=(state==RIFF||state==CHUNK||state==FMT||state==SKIP||state==PAD)||
                      (state==DATA&&(!sample_valid||sample_ready));
    wire take=file_valid&&file_ready;
    wire final_byte=(state==DATA&&remaining==1);
    task fail;
        input [3:0] code;
        begin state<=IDLE;busy<=0;sample_valid<=0;error<=1;error_code<=code;end
    endtask
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;busy<=0;done<=0;error<=0;error_code<=0;sample_valid<=0;sample_data<=0;
            pos<=0;size<=0;limit<=0;chunk_id<=0;chunk_size<=0;remaining<=0;index<=0;
            riff_id<=0;wave_id<=0;riff_size<=0;sample_rate<=0;byte_rate<=0;
            format<=0;channels<=0;alignment<=0;bits<=0;format_ok<=0;odd_pad<=0;part<=0;left<=0;low<=0;
        end else begin
            done<=0;error<=0;
            if(sample_valid&&sample_ready)sample_valid<=0;
            if(take)pos<=pos+1'b1;
            if(abort_file&&busy)fail(1);
            else if(take&&file_last&&!final_byte)fail(2);
            else case(state)
                IDLE:if(start)begin
                    pos<=0;size<=file_size;limit<=file_size;index<=0;riff_id<=0;wave_id<=0;riff_size<=0;
                    format_ok<=0;sample_valid<=0;error_code<=0;
                    if(file_size<44)fail(2);else begin busy<=1;state<=RIFF;end
                end
                RIFF:if(take)begin
                    if(pos<4)riff_id<={riff_id[23:0],file_byte};
                    else if(pos<8)riff_size<=riff_size|({24'd0,file_byte}<<((pos-4)*8));
                    else wave_id<={wave_id[23:0],file_byte};
                    if(pos==11)begin state<=CHECK;index<=0;end
                end
                CHECK:if(index==0)begin
                    if(riff_id!="RIFF"||wave_id!="WAVE")fail(3);
                    else if({1'b0,riff_size}+33'd8>{1'b0,size}||riff_size<36)fail(4);
                    else begin limit<=riff_size+8;state<=CHUNK;index<=0;chunk_id<=0;chunk_size<=0;end
                end else begin
                    if({1'b0,pos}+{1'b0,chunk_size}+chunk_size[0]>{1'b0,limit})fail(4);
                    else if(chunk_id=="fmt ")begin
                        if(chunk_size<16||format_ok)fail(5);
                        else begin state<=FMT;remaining<=chunk_size;index<=0;format<=0;channels<=0;sample_rate<=0;byte_rate<=0;alignment<=0;bits<=0;odd_pad<=chunk_size[0];end
                    end else if(chunk_id=="data")begin
                        if(!format_ok||chunk_size==0||(channels==1?chunk_size[0]!=0:chunk_size[1:0]!=0))fail(6);
                        else begin state<=DATA;remaining<=chunk_size;part<=0;end
                    end else begin
                        if(chunk_size==0)begin state<=CHUNK;index<=0;chunk_id<=0;chunk_size<=0;end
                        else begin state<=SKIP;remaining<=chunk_size;odd_pad<=chunk_size[0];end
                    end
                end
                CHUNK:if(pos+8>limit&&index==0)fail(4);
                      else if(take)begin
                    if(index<4)chunk_id<={chunk_id[23:0],file_byte};
                    else chunk_size<=chunk_size|({24'd0,file_byte}<<((index-4)*8));
                    if(index==7)begin state<=CHECK;index<=1;end else index<=index+1'b1;
                end
                FMT:if(take)begin
                    case(index)
                        0:format[7:0]<=file_byte;1:format[15:8]<=file_byte;
                        2:channels[7:0]<=file_byte;3:channels[15:8]<=file_byte;
                        4:sample_rate[7:0]<=file_byte;5:sample_rate[15:8]<=file_byte;6:sample_rate[23:16]<=file_byte;7:sample_rate[31:24]<=file_byte;
                        8:byte_rate[7:0]<=file_byte;9:byte_rate[15:8]<=file_byte;10:byte_rate[23:16]<=file_byte;11:byte_rate[31:24]<=file_byte;
                        12:alignment[7:0]<=file_byte;13:alignment[15:8]<=file_byte;14:bits[7:0]<=file_byte;15:bits[15:8]<=file_byte;
                    endcase
                    index<=index+1'b1;remaining<=remaining-1'b1;
                    if(remaining==1)begin
                        if(format!=1||(channels!=1&&channels!=2)||sample_rate!=48000||alignment!=channels*2||
                           byte_rate!=channels*96000||{(index==15?file_byte:bits[15:8]),bits[7:0]}!=16)fail(5);
                        else begin format_ok<=1;state<=odd_pad?PAD:CHUNK;index<=0;chunk_id<=0;chunk_size<=0;end
                    end
                end
                SKIP:if(take)begin
                    remaining<=remaining-1'b1;
                    if(remaining==1)begin state<=odd_pad?PAD:CHUNK;index<=0;chunk_id<=0;chunk_size<=0;end
                end
                PAD:if(take)begin state<=CHUNK;index<=0;chunk_id<=0;chunk_size<=0;end
                DATA:if(take)begin
                    remaining<=remaining-1'b1;part<=part+1'b1;
                    case(part)
                        0:low<=file_byte;
                        1:begin
                            left<={file_byte,low};
                            if(channels==1)begin sample_data<={file_byte,low,file_byte,low};sample_valid<=1;part<=0;end
                        end
                        2:low<=file_byte;
                        3:begin sample_data<={left,file_byte,low};sample_valid<=1;part<=0;end
                    endcase
                    if(remaining==1)state<=FINISH;
                end
                FINISH:if(!sample_valid||sample_ready)begin done<=1;busy<=0;state<=IDLE;end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
