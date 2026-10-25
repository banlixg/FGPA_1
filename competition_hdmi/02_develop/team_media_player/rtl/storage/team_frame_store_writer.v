// Team frame residency controller. All ports use clk; word addresses, not bytes.
// Published slots are immutable until reset. One memory write may be outstanding.
// The memory adapter must acknowledge every accepted write, including failures.
module team_frame_store_writer #(
    parameter integer IMAGE_WIDTH = 640,
    parameter integer IMAGE_HEIGHT = 480,
    parameter integer ADDR_BITS = 21
)(
    input wire clk,
    input wire rst_n,
    input wire load_start,
    input wire [1:0] load_slot,
    output wire load_ready,
    output reg busy,
    output reg [3:0] slot_valid,
    input wire [23:0] pixel_rgb,
    input wire [15:0] pixel_x,
    input wire [15:0] pixel_y,
    input wire pixel_valid,
    output wire pixel_ready,
    input wire image_done,
    input wire image_error,
    input wire file_done,
    input wire file_error,
    output wire wr_valid,
    input wire wr_ready,
    output reg [ADDR_BITS-1:0] wr_addr,
    output reg [31:0] wr_data,
    input wire wr_rsp_valid,
    input wire wr_rsp_error,
    output reg load_done,
    output reg load_failed,
    output reg abort_load,
    output reg [1:0] result_slot,
    output reg [3:0] error_code
);
    localparam integer FRAME_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;
    reg [1:0] target_slot;
    reg [31:0] pixels_accepted, writes_completed;
    reg [15:0] expected_x, expected_y;
    reg bottom_up;
    reg image_ok, file_ok, fault;
    reg request_pending, outstanding;

    assign load_ready = !busy && !slot_valid[load_slot];
    assign pixel_ready = busy && !fault && !image_ok &&
                         !image_error && !file_error &&
                         !request_pending && !outstanding &&
                         (pixels_accepted < FRAME_PIXELS);
    assign wr_valid = request_pending;
    wire take_pixel = pixel_valid && pixel_ready;
    wire take_write = wr_valid && wr_ready;
    wire first_pixel = (pixels_accepted == 0);
    wire coord_ok = (pixel_x < IMAGE_WIDTH) && (pixel_y < IMAGE_HEIGHT) &&
        (first_pixel ? ((pixel_x == 0) &&
                       ((pixel_y == 0) || (pixel_y == IMAGE_HEIGHT-1))) :
                      ((pixel_x == expected_x) && (pixel_y == expected_y)));
    wire good_pixel = take_pixel && coord_ok;
    wire [31:0] accepted_after = pixels_accepted + (good_pixel ? 32'd1 : 32'd0);
    wire response_expected = outstanding || take_write;
    wire bad_count = image_done && (accepted_after != FRAME_PIXELS);
    wire bad_response = wr_rsp_valid && (!response_expected || wr_rsp_error);
    wire fault_event = image_error || file_error ||
                       (take_pixel && !coord_ok) || bad_count || bad_response;
    wire memory_drained = !request_pending && !outstanding;
    // Maximum default address is 4*307200-1, within the 21-bit word space.
    wire [31:0] pixel_address = target_slot * FRAME_PIXELS +
                                pixel_y * IMAGE_WIDTH + pixel_x;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 0;
            slot_valid <= 0;
            target_slot <= 0;
            pixels_accepted <= 0;
            writes_completed <= 0;
            expected_x <= 0;
            expected_y <= 0;
            bottom_up <= 0;
            image_ok <= 0;
            file_ok <= 0;
            fault <= 0;
            request_pending <= 0;
            outstanding <= 0;
            wr_addr <= 0;
            wr_data <= 0;
            load_done <= 0;
            load_failed <= 0;
            abort_load <= 0;
            result_slot <= 0;
            error_code <= 0;
        end else begin
            load_done <= 0;
            load_failed <= 0;
            abort_load <= 0;
            if (!busy) begin
                if (load_start && load_ready) begin
                    busy <= 1;
                    target_slot <= load_slot;
                    result_slot <= load_slot;
                    pixels_accepted <= 0;
                    writes_completed <= 0;
                    expected_x <= 0;
                    expected_y <= 0;
                    bottom_up <= 0;
                    image_ok <= 0;
                    file_ok <= 0;
                    fault <= 0;
                    error_code <= 0;
                end
            end else begin
                if (good_pixel) begin
                    pixels_accepted <= pixels_accepted + 1'b1;
                    wr_addr <= pixel_address[ADDR_BITS-1:0];
                    wr_data <= {pixel_rgb, 8'd0};
                    request_pending <= 1;
                    if (first_pixel)
                        bottom_up <= (pixel_y != 0);
                    if (pixel_x == IMAGE_WIDTH-1) begin
                        expected_x <= 0;
                        if (first_pixel ? (pixel_y != 0) : bottom_up)
                            expected_y <= pixel_y - 1'b1;
                        else
                            expected_y <= pixel_y + 1'b1;
                    end else begin
                        expected_x <= pixel_x + 1'b1;
                        expected_y <= pixel_y;
                    end
                end
                if (take_write) begin
                    request_pending <= 0;
                    outstanding <= 1;
                end
                if (wr_rsp_valid && response_expected) begin
                    outstanding <= 0;
                    if (!wr_rsp_error)
                        writes_completed <= writes_completed + 1'b1;
                end
                if (image_done) image_ok <= 1;
                if (file_done) file_ok <= 1;
                if (!fault && fault_event) begin
                    fault <= 1;
                    abort_load <= 1;
                    // 1 BMP; 2 file; 3 coordinate/order; 4 pixel count;
                    // 5 memory write failure; 6 unsolicited memory response.
                    if (image_error) error_code <= 1;
                    else if (file_error) error_code <= 2;
                    else if (take_pixel && !coord_ok) error_code <= 3;
                    else if (bad_count) error_code <= 4;
                    else if (wr_rsp_error && response_expected) error_code <= 5;
                    else error_code <= 6;
                end
                // Preserve an already offered request even on source abort.
                // Drain its response before admitting another load transaction.
                if (fault && memory_drained) begin
                    busy <= 0;
                    load_failed <= 1;
                end else if (!fault && !fault_event && image_ok && file_ok &&
                             memory_drained &&
                             pixels_accepted == FRAME_PIXELS &&
                             writes_completed == FRAME_PIXELS) begin
                    slot_valid[target_slot] <= 1;
                    busy <= 0;
                    load_done <= 1;
                end
            end
        end
    end
endmodule
