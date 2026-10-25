// Production single-clock image-load pipeline, from FAT32 descriptor to frame.
// Mount/catalog scheduling and real SD/SDRAM adapters live outside this module.
module team_image_loader #(
    parameter integer IMAGE_WIDTH=640,
    parameter integer IMAGE_HEIGHT=480,
    parameter integer ADDR_BITS=21,
    parameter integer WAIT_LIMIT=1000000
)(
    input wire clk, rst_n,
    input wire load_valid,
    output wire load_ready,
    input wire [1:0] load_slot,
    input wire [27:0] first_cluster,
    input wire [31:0] file_size,
    input wire [31:0] fat_lba, data_lba, cluster_count,
    input wire [7:0] sectors_per_cluster,
    output wire busy,
    output wire [3:0] slot_valid,
    output reg load_done, load_failed,
    output reg [1:0] result_slot,
    output reg [3:0] error_code,
    output wire rd_req_valid, rd_cancel,
    input wire rd_req_ready,
    output wire [31:0] rd_req_lba,
    input wire rd_valid,
    output wire rd_ready,
    input wire [7:0] rd_data,
    input wire rd_last, rd_error,
    output wire wr_valid,
    input wire wr_ready,
    output wire [ADDR_BITS-1:0] wr_addr,
    output wire [31:0] wr_data,
    input wire wr_rsp_valid, wr_rsp_error
);
    reg job_active, result_pending, result_success;
    wire reader_busy, reader_done, reader_error;
    wire parser_busy, parser_start_ready, image_done, image_error;
    wire writer_busy, writer_ready, writer_done, writer_failed, writer_abort;
    wire [1:0] writer_slot;
    wire [3:0] writer_code, reader_code, image_code;
    wire [31:0] file_position;
    wire [7:0] file_byte;
    wire file_valid, file_ready, file_last;
    wire [23:0] pixel_rgb;
    wire [15:0] pixel_x, pixel_y;
    wire pixel_valid, pixel_ready;
    wire start_job = load_valid && load_ready;
    assign load_ready = !job_active && writer_ready && parser_start_ready && !reader_busy;
    assign busy = job_active;
    team_fat32_file_reader #(.WAIT_LIMIT(WAIT_LIMIT)) reader(
        .clk(clk),.rst_n(rst_n),.start(start_job),
        .close_file(image_done || image_error || writer_abort),
        .fat_lba(fat_lba),.data_lba(data_lba),.cluster_count(cluster_count),
        .sectors_per_cluster(sectors_per_cluster),.first_cluster(first_cluster),.file_size(file_size),
        .busy(reader_busy),.done(reader_done),.error(reader_error),.error_code(reader_code),
        .file_position(file_position),.file_valid(file_valid),.file_ready(file_ready),
        .file_byte(file_byte),.file_last(file_last),.rd_req_valid(rd_req_valid),.rd_cancel(rd_cancel),
        .rd_req_ready(rd_req_ready),.rd_req_lba(rd_req_lba),.rd_valid(rd_valid),.rd_ready(rd_ready),
        .rd_data(rd_data),.rd_last(rd_last),.rd_error(rd_error));
    team_bmp_parser #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT)) parser(
        .clk(clk),.rst_n(rst_n),.start(start_job),.file_size(file_size),
        .abort_file(reader_error || writer_abort),.start_ready(parser_start_ready),.busy(parser_busy),
        .file_byte(file_byte),.file_valid(file_valid),.file_ready(file_ready),.file_last(file_last),
        .pixel_rgb(pixel_rgb),.pixel_x(pixel_x),.pixel_y(pixel_y),.pixel_valid(pixel_valid),
        .pixel_ready(pixel_ready),.image_done(image_done),.image_error(image_error),.error_code(image_code));
    team_frame_store_writer #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),.ADDR_BITS(ADDR_BITS)) writer(
        .clk(clk),.rst_n(rst_n),.load_start(start_job),.load_slot(load_slot),.load_ready(writer_ready),
        .busy(writer_busy),.slot_valid(slot_valid),.pixel_rgb(pixel_rgb),.pixel_x(pixel_x),.pixel_y(pixel_y),
        .pixel_valid(pixel_valid),.pixel_ready(pixel_ready),.image_done(image_done),.image_error(image_error),
        .file_done(reader_done),.file_error(reader_error),.wr_valid(wr_valid),.wr_ready(wr_ready),
        .wr_addr(wr_addr),.wr_data(wr_data),.wr_rsp_valid(wr_rsp_valid),.wr_rsp_error(wr_rsp_error),
        .load_done(writer_done),.load_failed(writer_failed),.abort_load(writer_abort),
        .result_slot(writer_slot),.error_code(writer_code));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            job_active<=0;result_pending<=0;result_success<=0;
            load_done<=0;load_failed<=0;result_slot<=0;error_code<=0;
        end else begin
            load_done<=0;load_failed<=0;
            if(start_job) begin
                job_active<=1;result_pending<=0;result_slot<=load_slot;error_code<=0;
            end
            if(writer_done || writer_failed) begin
                result_pending<=1;result_success<=writer_done;
                result_slot<=writer_slot;error_code<=writer_code;
            end
            // A failed parser can finish before the sector reader drains.
            // Do not return the job result or accept another file until all idle.
            if(job_active && result_pending && !reader_busy && !parser_busy && !writer_busy) begin
                job_active<=0;result_pending<=0;
                load_done<=result_success;load_failed<=!result_success;
            end
        end
    end
endmodule
