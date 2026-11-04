// Takes SD ownership after all images have been loaded. Reuses generic FAT I/O,
// independently parses WAV chunks and loops the descriptor found by boot enumeration.
module team_audio_file #(parameter WAIT_LIMIT=25000000)(
    input wire clk,rst_n,enable,found,
    input wire [31:0] fat,data,clusters,file_size,
    input wire [7:0] spc,input wire [27:0] first_cluster,
    output reg [3:0] state,error_code,
    output wire sample_valid,input wire sample_ready,output wire [31:0] sample_data,
    output wire rd_req_valid,rd_cancel,input wire rd_req_ready,
    output wire [31:0] rd_req_lba,input wire rd_valid,output wire rd_ready,
    input wire [7:0] rd_data,input wire rd_last,rd_error
);
    reg fstart;
    wire [3:0] fc,pc;
    wire [7:0] fbyte;wire fv,fr,fl,fd,fe,fb,pd,pe,pbusy,pidle;
    reg ending,bad_file;
    team_fat32_file_reader #(.WAIT_LIMIT(WAIT_LIMIT)) file_reader(
        .clk(clk),.rst_n(rst_n),.start(fstart),.close_file(pd||pe),
        .fat_lba(fat),.data_lba(data),.cluster_count(clusters),.sectors_per_cluster(spc),
        .first_cluster(first_cluster),.file_size(file_size),.busy(fb),.done(fd),.error(fe),
        .error_code(fc),.file_position(),.file_valid(fv),.file_ready(fr),.file_byte(fbyte),.file_last(fl),
        .rd_req_valid(rd_req_valid),.rd_cancel(rd_cancel),.rd_req_ready(rd_req_ready),
        .rd_req_lba(rd_req_lba),.rd_valid(rd_valid),.rd_ready(rd_ready),.rd_data(rd_data),
        .rd_last(rd_last),.rd_error(rd_error));
    team_wav_parser parser(
        .clk(clk),.rst_n(rst_n),.start(fstart),.abort_file(fe),.file_size(file_size),
        .idle(pidle),.busy(pbusy),.done(pd),.error(pe),.error_code(pc),
        .file_valid(fv),.file_ready(fr),.file_byte(fbyte),.file_last(fl),
        .sample_valid(sample_valid),.sample_ready(sample_ready),.sample_data(sample_data));
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin state<=0;error_code<=0;fstart<=0;ending<=0;bad_file<=0;end
        else begin
            fstart<=0;
            case(state)
                0:if(enable)begin
                    if(found)state<=3;else begin state<=7;error_code<=4'hf;end
                end
                3:if(!fb&&pidle)begin fstart<=1;ending<=0;bad_file<=0;state<=4;end
                4:begin
                    if(pe||fe)begin ending<=1;bad_file<=1;error_code<=pe?pc:fc;state<=5;end
                    else if(pd)begin ending<=1;state<=5;end
                end
                5:if(ending&&!fb&&pidle)state<=bad_file?7:3;
                default:begin end
            endcase
        end
    end
endmodule

module team_pcm_hdmi #(parameter PIXEL_HZ=25000000,START_LEVEL=256)(
    input wire clk,rst_n,input wire [31:0] fifo_data,input wire fifo_empty,
    input wire [11:0] fifo_level,output wire fifo_read,
    output reg audio_valid,output reg [23:0] audio_left,audio_right,
    output reg acr_valid,output wire [19:0] acr_n,acr_cts,
    output reg [31:0] underruns
);
    reg started,pending,missing;reg [31:0] phase;reg [5:0] samples;
    wire tick=started&&(phase+48000>=PIXEL_HZ);
    assign fifo_read=tick&&!fifo_empty;
    assign acr_n=20'd6144;
    // f_TMDS = 128*f_s*CTS/N; N=6144, f_s=48000 => CTS=f_pixel/1000.
    assign acr_cts=PIXEL_HZ/1000;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            started<=0;pending<=0;missing<=0;phase<=0;samples<=0;
            audio_valid<=0;audio_left<=0;audio_right<=0;acr_valid<=0;underruns<=0;
        end else begin
            audio_valid<=pending;acr_valid<=0;pending<=tick;missing<=fifo_empty;
            if(!started)begin phase<=0;if(fifo_level>=START_LEVEL)started<=1;end
            else if(tick)phase<=phase+48000-PIXEL_HZ;else phase<=phase+48000;
            if(tick&&fifo_empty)underruns<=underruns+1'b1;
            if(pending)begin
                audio_left<=missing?24'd0:{fifo_data[31:16],8'd0};
                audio_right<=missing?24'd0:{fifo_data[15:0],8'd0};
                if(samples==47)begin samples<=0;acr_valid<=1;end else samples<=samples+1'b1;
            end
        end
    end
endmodule
