// Team implementation: streamed Windows BMP decoder, independent of bmp_read.v.
// Input/output use ready/valid. Coordinates always refer to top-left origin.
// Only 24-bit BI_RGB of the configured dimensions is accepted.
module team_bmp_parser #(
    parameter integer IMAGE_WIDTH = 640,
    parameter integer IMAGE_HEIGHT = 480
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [31:0] file_size,
    input wire abort_file,
    output wire start_ready,
    output reg busy,
    input wire [7:0] file_byte,
    input wire file_valid,
    output wire file_ready,
    input wire file_last,
    output reg [23:0] pixel_rgb,
    output reg [15:0] pixel_x,
    output reg [15:0] pixel_y,
    output reg pixel_valid,
    input wire pixel_ready,
    output reg image_done,
    output reg image_error,
    output reg [3:0] error_code
);
    localparam [2:0] IDLE=0, HEADER=1, CHECK=2, SKIP=3,
                     PIXEL=4, PADDING=5, FINISH=6;
    localparam integer ROW_BYTES = IMAGE_WIDTH * 3;
    localparam integer PAD_BYTES = (4 - (ROW_BYTES % 4)) % 4;
    localparam [32:0] IMAGE_BYTES = (ROW_BYTES + PAD_BYTES) * IMAGE_HEIGHT;
    localparam [31:0] WIDTH_VALUE = IMAGE_WIDTH;
    localparam [31:0] HEIGHT_VALUE = IMAGE_HEIGHT;
    localparam [31:0] NEG_HEIGHT_VALUE = -IMAGE_HEIGHT;

    reg [2:0] state;
    reg [31:0] source_size;
    reg [31:0] byte_position;
    reg [15:0] signature;
    reg [31:0] declared_size;
    reg [31:0] pixel_offset;
    reg [31:0] dib_size;
    reg [31:0] bmp_width;
    reg [31:0] bmp_height;
    reg [15:0] planes;
    reg [15:0] bit_depth;
    reg [31:0] compression;
    reg top_down;
    reg [15:0] source_row;
    reg [15:0] column;
    reg [1:0] component;
    reg [1:0] pad_index;
    reg [7:0] blue_byte, green_byte;

    wire take_byte = file_valid && file_ready;
    wire final_pixel = (source_row == IMAGE_HEIGHT-1) &&
                       (column == IMAGE_WIDTH-1) && (component == 2);
    wire final_input = ((state == PIXEL) && final_pixel && (PAD_BYTES == 0)) ||
                       ((state == PADDING) && (source_row == IMAGE_HEIGHT-1) &&
                        (pad_index == PAD_BYTES-1));
    wire [32:0] dib_end = {1'b0, dib_size} + 33'd14;
    wire [32:0] payload_end = {1'b0, pixel_offset} + IMAGE_BYTES;

    assign start_ready = (state == IDLE);
    assign file_ready = (state == HEADER) || (state == SKIP) ||
                        (state == PADDING) ||
                        ((state == PIXEL) && (!pixel_valid || pixel_ready));

    // Error codes: 1 abort; 2 short stream; 3 signature; 4 DIB/offset;
    // 5 dimensions; 6 planes/depth; 7 compression; 8 file size bounds.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            busy <= 0;
            source_size <= 0;
            byte_position <= 0;
            signature <= 0;
            declared_size <= 0;
            pixel_offset <= 0;
            dib_size <= 0;
            bmp_width <= 0;
            bmp_height <= 0;
            planes <= 0;
            bit_depth <= 0;
            compression <= 0;
            top_down <= 0;
            source_row <= 0;
            column <= 0;
            component <= 0;
            pad_index <= 0;
            blue_byte <= 0;
            green_byte <= 0;
            pixel_rgb <= 0;
            pixel_x <= 0;
            pixel_y <= 0;
            pixel_valid <= 0;
            image_done <= 0;
            image_error <= 0;
            error_code <= 0;
        end else begin
            image_done <= 0;
            image_error <= 0;
            if (pixel_valid && pixel_ready)
                pixel_valid <= 0;

            if (abort_file && busy) begin
                state <= IDLE;
                busy <= 0;
                pixel_valid <= 0;
                image_error <= 1;
                error_code <= 1;
            end else if (take_byte && file_last && !final_input) begin
                state <= IDLE;
                busy <= 0;
                pixel_valid <= 0;
                image_error <= 1;
                error_code <= 2;
            end else begin
                case (state)
                    IDLE: if (start) begin
                        source_size <= file_size;
                        byte_position <= 0;
                        signature <= 0;
                        declared_size <= 0;
                        pixel_offset <= 0;
                        dib_size <= 0;
                        bmp_width <= 0;
                        bmp_height <= 0;
                        planes <= 0;
                        bit_depth <= 0;
                        compression <= 0;
                        source_row <= 0;
                        column <= 0;
                        component <= 0;
                        pad_index <= 0;
                        pixel_valid <= 0;
                        error_code <= 0;
                        if (file_size < 54) begin
                            image_error <= 1;
                            error_code <= 2;
                        end else begin
                            busy <= 1;
                            state <= HEADER;
                        end
                    end
                    HEADER: if (take_byte) begin
                        // Little-endian fields; ignore unused header metadata.
                        case (byte_position)
                            0: signature[7:0] <= file_byte;
                            1: signature[15:8] <= file_byte;
                            2: declared_size[7:0] <= file_byte;
                            3: declared_size[15:8] <= file_byte;
                            4: declared_size[23:16] <= file_byte;
                            5: declared_size[31:24] <= file_byte;
                            10: pixel_offset[7:0] <= file_byte;
                            11: pixel_offset[15:8] <= file_byte;
                            12: pixel_offset[23:16] <= file_byte;
                            13: pixel_offset[31:24] <= file_byte;
                            14: dib_size[7:0] <= file_byte;
                            15: dib_size[15:8] <= file_byte;
                            16: dib_size[23:16] <= file_byte;
                            17: dib_size[31:24] <= file_byte;
                            18: bmp_width[7:0] <= file_byte;
                            19: bmp_width[15:8] <= file_byte;
                            20: bmp_width[23:16] <= file_byte;
                            21: bmp_width[31:24] <= file_byte;
                            22: bmp_height[7:0] <= file_byte;
                            23: bmp_height[15:8] <= file_byte;
                            24: bmp_height[23:16] <= file_byte;
                            25: bmp_height[31:24] <= file_byte;
                            26: planes[7:0] <= file_byte;
                            27: planes[15:8] <= file_byte;
                            28: bit_depth[7:0] <= file_byte;
                            29: bit_depth[15:8] <= file_byte;
                            30: compression[7:0] <= file_byte;
                            31: compression[15:8] <= file_byte;
                            32: compression[23:16] <= file_byte;
                            33: compression[31:24] <= file_byte;
                            default: begin end
                        endcase
                        byte_position <= byte_position + 1'b1;
                        if (byte_position == 53)
                            state <= CHECK;
                    end
                    CHECK: begin
                        if (signature != 16'h4d42) begin
                            state <= IDLE; busy <= 0;
                            image_error <= 1; error_code <= 3;
                        end else if ((dib_size < 40) ||
                                     (dib_end > {1'b0, pixel_offset})) begin
                            state <= IDLE; busy <= 0;
                            image_error <= 1; error_code <= 4;
                        end else if ((bmp_width != WIDTH_VALUE) ||
                                     ((bmp_height != HEIGHT_VALUE) &&
                                      (bmp_height != NEG_HEIGHT_VALUE))) begin
                            state <= IDLE; busy <= 0;
                            image_error <= 1; error_code <= 5;
                        end else if ((planes != 1) || (bit_depth != 24)) begin
                            state <= IDLE; busy <= 0;
                            image_error <= 1; error_code <= 6;
                        end else if (compression != 0) begin
                            state <= IDLE; busy <= 0;
                            image_error <= 1; error_code <= 7;
                        end else if ((payload_end > {1'b0, source_size}) ||
                                     (payload_end > {1'b0, declared_size}) ||
                                     (declared_size > source_size)) begin
                            state <= IDLE; busy <= 0;
                            image_error <= 1; error_code <= 8;
                        end else begin
                            top_down <= bmp_height[31];
                            if (pixel_offset == 54) state <= PIXEL;
                            else state <= SKIP;
                        end
                    end
                    SKIP: if (take_byte) begin
                        byte_position <= byte_position + 1'b1;
                        if (byte_position + 1'b1 == pixel_offset)
                            state <= PIXEL;
                    end
                    PIXEL: if (take_byte) begin
                        case (component)
                            0: begin blue_byte <= file_byte; component <= 1; end
                            1: begin green_byte <= file_byte; component <= 2; end
                            2: begin
                                pixel_rgb <= {file_byte, green_byte, blue_byte};
                                pixel_x <= column;
                                if (top_down) pixel_y <= source_row;
                                else pixel_y <= IMAGE_HEIGHT-1-source_row;
                                pixel_valid <= 1;
                                component <= 0;
                                if (column == IMAGE_WIDTH-1) begin
                                    column <= 0;
                                    pad_index <= 0;
                                    if (PAD_BYTES != 0) state <= PADDING;
                                    else if (source_row == IMAGE_HEIGHT-1)
                                        state <= FINISH;
                                    else source_row <= source_row + 1'b1;
                                end else column <= column + 1'b1;
                            end
                            default: component <= 0;
                        endcase
                    end
                    PADDING: if (take_byte) begin
                        if (pad_index == PAD_BYTES-1) begin
                            pad_index <= 0;
                            if (source_row == IMAGE_HEIGHT-1) state <= FINISH;
                            else begin
                                source_row <= source_row + 1'b1;
                                state <= PIXEL;
                            end
                        end else pad_index <= pad_index + 1'b1;
                    end
                    FINISH: if (!pixel_valid || pixel_ready) begin
                        state <= IDLE;
                        busy <= 0;
                        image_done <= 1;
                    end
                    default: begin
                        state <= IDLE; busy <= 0; pixel_valid <= 0;
                    end
                endcase
            end
        end
    end
endmodule
