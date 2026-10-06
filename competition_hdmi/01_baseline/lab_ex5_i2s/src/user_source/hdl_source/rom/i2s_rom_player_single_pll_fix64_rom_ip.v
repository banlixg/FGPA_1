module i2s_rom_player_single_pll_fix64 #(
    parameter integer SAMPLE_RATE       = 48000,
    parameter integer SAMPLE_BITS       = 24,
    parameter integer ROM_DEPTH         = 48,
    parameter integer ADDR_WIDTH        = 6,
    parameter integer NOTE_LEN_SAMPLES  = 12000  // 每个音 0.25s @ 48kHz
)(
    input  wire I_mclk,      // 12.288MHz
    input  wire I_rst,
    output reg  O_i2s_BCLK,
    output reg  O_i2s_LRCK,
    output reg  O_i2s_DOUT
);

    // ============================================================
    // 单端口 ROM IP 版：24bit / 48 深度正弦波表 + 8 音阶旋律发生器
    //
    // ROM IP 端口：module AUDIO_SAMPLE_ROM ( doa, addra, clka );
    // doa[23:0] = 单声道 24bit PCM 波表样本
    //
    // I2S 时序与当前 I2S_receiver 兼容：
    //   MCLK = 12.288MHz
    //   BCLK = 6.144MHz = MCLK / 2
    //   LRCK = 48kHz    = BCLK / 128
    //   每声道发送 64bit，其中 [63:40] 为 24bit 采样，低 40bit 补 0
    //
    // 旋律：do re mi fa so la si do (C4 D4 E4 F4 G4 A4 B4 C5)
    // 实现方式：ROM 只存一个 48 点正弦单周期，通过改变读表步进值来合成音高
    // ============================================================

    localparam [31:0] TABLE_SIZE_Q16 = (ROM_DEPTH << 16);

    // phase_step = round(freq * ROM_DEPTH / SAMPLE_RATE * 2^16)
    localparam [31:0] STEP_DO4 = 32'd17146; // C4  261.63Hz
    localparam [31:0] STEP_RE4 = 32'd19245; // D4  293.66Hz
    localparam [31:0] STEP_MI4 = 32'd21603; // E4  329.63Hz
    localparam [31:0] STEP_FA4 = 32'd22887; // F4  349.23Hz
    localparam [31:0] STEP_SO4 = 32'd25690; // G4  392.00Hz
    localparam [31:0] STEP_LA4 = 32'd28836; // A4  440.00Hz
    localparam [31:0] STEP_SI4 = 32'd32367; // B4  493.88Hz
    localparam [31:0] STEP_DO5 = 32'd34292; // C5  523.25Hz

    reg        S_mclk_div;
    reg [6:0]  S_bit_cnt;
    reg [63:0] S_left_word;
    reg [63:0] S_right_word;

    reg [ADDR_WIDTH-1:0] S_rom_addr;
    wire [23:0]          S_rom_q;

    reg [23:0]  S_sample_next;
    reg         S_capture_pending;
    reg [1:0]   S_init_step;

    reg [31:0]  S_phase_acc_q16;
    reg [31:0]  S_phase_step_q16;
    reg [15:0]  S_note_cnt;
    reg [2:0]   S_note_sel;

    reg [31:0]  S_phase_next_q16;
    reg [31:0]  S_phase_sum_q16;
    reg [31:0]  S_phase_step_next_q16;
    reg [15:0]  S_note_cnt_next;
    reg [2:0]   S_note_sel_next;
    reg [ADDR_WIDTH-1:0] S_rom_addr_next;

    AUDIO_SAMPLE_ROM u_audio_sample_rom (
        .doa   ( S_rom_q    ),
        .addra ( S_rom_addr ),
        .clka  ( I_mclk     )
    );

    function [31:0] note_step;
        input [2:0] note_idx;
        begin
            case (note_idx)
                3'd0: note_step = STEP_DO4;
                3'd1: note_step = STEP_RE4;
                3'd2: note_step = STEP_MI4;
                3'd3: note_step = STEP_FA4;
                3'd4: note_step = STEP_SO4;
                3'd5: note_step = STEP_LA4;
                3'd6: note_step = STEP_SI4;
                default: note_step = STEP_DO5;
            endcase
        end
    endfunction

    always @(*) begin
        S_phase_step_next_q16 = S_phase_step_q16;
        S_note_cnt_next       = S_note_cnt;
        S_note_sel_next       = S_note_sel;
        S_phase_sum_q16       = S_phase_acc_q16 + S_phase_step_q16;

        if (S_note_cnt == NOTE_LEN_SAMPLES - 1) begin
            if (S_note_sel == 3'd7)
                S_note_sel_next = 3'd0;
            else
                S_note_sel_next = S_note_sel + 3'd1;

            S_phase_step_next_q16 = note_step((S_note_sel == 3'd7) ? 3'd0 : (S_note_sel + 3'd1));
            S_note_cnt_next       = 16'd0;
            S_phase_next_q16      = 32'd0;
        end else begin
            S_note_cnt_next = S_note_cnt + 16'd1;

            if (S_phase_sum_q16 >= TABLE_SIZE_Q16)
                S_phase_next_q16 = S_phase_sum_q16 - TABLE_SIZE_Q16;
            else
                S_phase_next_q16 = S_phase_sum_q16;
        end

        S_rom_addr_next = S_phase_next_q16[31:16];
    end

    always @(posedge I_mclk or posedge I_rst) begin
        if (I_rst) begin
            S_mclk_div         <= 1'b0;
            S_bit_cnt          <= 7'd0;
            S_left_word        <= 64'd0;
            S_right_word       <= 64'd0;
            S_rom_addr         <= {ADDR_WIDTH{1'b0}};
            S_sample_next      <= 24'd0;
            S_capture_pending  <= 1'b0;
            S_init_step        <= 2'd0;

            S_phase_acc_q16    <= 32'd0;
            S_phase_step_q16   <= STEP_DO4;
            S_note_cnt         <= 16'd0;
            S_note_sel         <= 3'd0;

            O_i2s_BCLK         <= 1'b0;
            O_i2s_LRCK         <= 1'b0;
            O_i2s_DOUT         <= 1'b0;
        end else begin
            if (S_capture_pending) begin
                S_sample_next     <= S_rom_q;
                S_capture_pending <= 1'b0;
            end

            case (S_init_step)
                2'd0: begin
                    S_rom_addr        <= {ADDR_WIDTH{1'b0}};
                    S_phase_acc_q16   <= 32'd0;
                    S_phase_step_q16  <= STEP_DO4;
                    S_note_cnt        <= 16'd0;
                    S_note_sel        <= 3'd0;
                    S_init_step       <= 2'd1;
                    O_i2s_BCLK        <= 1'b0;
                    O_i2s_LRCK        <= 1'b0;
                    O_i2s_DOUT        <= 1'b0;
                    S_mclk_div        <= 1'b0;
                    S_bit_cnt         <= 7'd0;
                end

                2'd1: begin
                    S_sample_next     <= S_rom_q;
                    S_rom_addr        <= {ADDR_WIDTH{1'b0}};
                    S_capture_pending <= 1'b1;
                    S_init_step       <= 2'd2;
                end

                2'd2: begin
                    S_left_word       <= {S_sample_next, 40'd0};
                    S_right_word      <= {S_sample_next, 40'd0};
                    S_init_step       <= 2'd3;
                end

                default: begin
                    S_mclk_div <= ~S_mclk_div;

                    if (S_mclk_div == 1'b0) begin
                        if (O_i2s_BCLK == 1'b1) begin
                            if (S_bit_cnt < 7'd63) begin
                                O_i2s_LRCK <= 1'b0;
                                O_i2s_DOUT <= S_left_word[63];
                                S_left_word <= {S_left_word[62:0], 1'b0};
                                S_bit_cnt   <= S_bit_cnt + 7'd1;
                            end else if (S_bit_cnt == 7'd63) begin
                                O_i2s_LRCK <= 1'b1;
                                O_i2s_DOUT <= S_left_word[63];
                                S_left_word <= {S_left_word[62:0], 1'b0};
                                S_bit_cnt   <= 7'd64;
                            end else if (S_bit_cnt < 7'd127) begin
                                O_i2s_LRCK   <= 1'b1;
                                O_i2s_DOUT   <= S_right_word[63];
                                S_right_word <= {S_right_word[62:0], 1'b0};
                                S_bit_cnt    <= S_bit_cnt + 7'd1;
                            end else begin
                                O_i2s_LRCK        <= 1'b0;
                                O_i2s_DOUT        <= S_right_word[63];
                                S_left_word       <= {S_sample_next, 40'd0};
                                S_right_word      <= {S_sample_next, 40'd0};
                                S_bit_cnt         <= 7'd0;

                                S_phase_acc_q16   <= S_phase_next_q16;
                                S_phase_step_q16  <= S_phase_step_next_q16;
                                S_note_cnt        <= S_note_cnt_next;
                                S_note_sel        <= S_note_sel_next;
                                S_rom_addr        <= S_rom_addr_next;
                                S_capture_pending <= 1'b1;
                            end
                        end

                        O_i2s_BCLK <= ~O_i2s_BCLK;
                    end
                end
            endcase
        end
    end

endmodule
