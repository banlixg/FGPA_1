module i2s_test_tone_gen_single_pll_fix64 #(
    parameter integer SAMPLE_RATE = 48000,
    parameter integer SAMPLE_BITS = 24,
    parameter integer TONE_HZ     = 1000
)(
    input  wire I_mclk,      // 12.288MHz
    input  wire I_rst,
    output reg  O_i2s_BCLK,
    output reg  O_i2s_LRCK,
    output reg  O_i2s_DOUT
);

    // 这版不是标准 32bit-slot I2S，而是专门匹配你给的 I2S_receiver：
    //   - 每个声道发送 64 个 BCLK
    //   - 接收端在声道切换时取 shift_reg[63:40]
    // 因此这里把 24bit 音频样本放在每个 64bit 声道字的最高 24bit：
    //   [63:40] = sample[23:0]
    //   [39:0]  = 0
    //
    // 时钟关系：
    //   MCLK = 12.288MHz
    //   BCLK = 6.144MHz = MCLK / 2
    //   LRCK = 48kHz    = BCLK / 128

    localparam integer CHANNEL_BITS        = 64;
    localparam integer FRAME_BITS          = 128;
    localparam integer TONE_PERIOD_SAMPLES = SAMPLE_RATE / TONE_HZ;
    localparam integer HALF_PERIOD_SAMPLES = TONE_PERIOD_SAMPLES / 2;
    localparam signed [23:0] AMP           = 24'sd2000000;

    reg        mclk_div;
    reg [6:0]  bit_cnt;
    reg [63:0] left_word;
    reg [63:0] right_word;
    reg [15:0] tone_cnt;

    always @(posedge I_mclk or posedge I_rst) begin
        if (I_rst) begin
            mclk_div   <= 1'b0;
            O_i2s_BCLK <= 1'b0;
            O_i2s_LRCK <= 1'b0;
            O_i2s_DOUT <= AMP[23];
            bit_cnt    <= 7'd0;
            tone_cnt   <= 16'd0;
            left_word  <= {AMP, 40'd0};
            right_word <= {AMP, 40'd0};
        end else begin
            mclk_div <= ~mclk_div;

            // 每 1 个 I_mclk 周期翻转一次 BCLK => BCLK = I_mclk / 2
            if (mclk_div == 1'b0) begin
                // 在 BCLK 下降沿更新 LRCK 和 DOUT，供接收端在 BCLK 上升沿采样
                if (O_i2s_BCLK == 1'b1) begin
                    if (bit_cnt < 7'd63) begin
                        O_i2s_LRCK <= 1'b0;
                        O_i2s_DOUT <= left_word[63];
                        left_word  <= {left_word[62:0], 1'b0};
                        bit_cnt    <= bit_cnt + 7'd1;
                    end else if (bit_cnt == 7'd63) begin
                        O_i2s_LRCK <= 1'b1;
                        O_i2s_DOUT <= left_word[63];
                        left_word  <= {left_word[62:0], 1'b0};
                        bit_cnt    <= 7'd64;
                    end else if (bit_cnt < 7'd127) begin
                        O_i2s_LRCK <= 1'b1;
                        O_i2s_DOUT <= right_word[63];
                        right_word <= {right_word[62:0], 1'b0};
                        bit_cnt    <= bit_cnt + 7'd1;
                    end else begin
                        O_i2s_LRCK <= 1'b0;
                        O_i2s_DOUT <= right_word[63];
                        bit_cnt    <= 7'd0;

                        if (tone_cnt < HALF_PERIOD_SAMPLES) begin
                            left_word  <= { AMP, 40'd0};
                            right_word <= { AMP, 40'd0};
                        end else begin
                            left_word  <= {-AMP, 40'd0};
                            right_word <= {-AMP, 40'd0};
                        end

                        if (tone_cnt == TONE_PERIOD_SAMPLES - 1)
                            tone_cnt <= 16'd0;
                        else
                            tone_cnt <= tone_cnt + 16'd1;
                    end
                end

                O_i2s_BCLK <= ~O_i2s_BCLK;
            end
        end
    end

endmodule
