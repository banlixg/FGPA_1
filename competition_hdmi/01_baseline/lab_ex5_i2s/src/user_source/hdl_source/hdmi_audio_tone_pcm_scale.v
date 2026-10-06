
module hdmi_audio_tone_pcm_scale #(
    parameter integer CLK_FREQ_HZ       = 25_000_000,
    parameter integer SAMPLE_RATE_HZ    = 48_000,
    parameter signed [23:0] AMP         = 24'sd2000000,
    parameter integer NOTE_HOLD_SAMPLES = 24_000
)(
    input  wire        I_clk,
    input  wire        I_rst,
    output reg         O_audio_valid,
    output reg  [23:0] O_audio_left_data,
    output reg  [23:0] O_audio_right_data
);

// do/re/mi/fa/so/la/si/do  （C4 D4 E4 F4 G4 A4 B4 C5）
// 相位增量按 48kHz 采样率计算
function [31:0] note_inc_lut;
    input [2:0] idx;
    begin
        case (idx)
            3'd0: note_inc_lut = 32'd23409862; // do  C4 261.63Hz
            3'd1: note_inc_lut = 32'd26276681; // re  D4 293.66Hz
            3'd2: note_inc_lut = 32'd29494578; // mi  E4 329.63Hz
            3'd3: note_inc_lut = 32'd31248410; // fa  F4 349.23Hz
            3'd4: note_inc_lut = 32'd35075155; // so  G4 392.00Hz
            3'd5: note_inc_lut = 32'd39370534; // la  A4 440.00Hz
            3'd6: note_inc_lut = 32'd44191930; // si  B4 493.88Hz
            default: note_inc_lut = 32'd46819716; // do  C5 523.25Hz
        endcase
    end
endfunction

reg [31:0] S_sample_acc;
reg [31:0] S_phase_acc;
reg [2:0]  S_note_idx;
reg [31:0] S_note_sample_cnt;
reg signed [23:0] S_pcm_sample;
reg [31:0] S_acc_add;

wire [31:0] W_note_inc = note_inc_lut(S_note_idx);

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        O_audio_valid      <= 1'b0;
        O_audio_left_data  <= 24'd0;
        O_audio_right_data <= 24'd0;
        S_sample_acc       <= 32'd0;
        S_phase_acc        <= 32'd0;
        S_note_idx         <= 3'd0;
        S_note_sample_cnt  <= 32'd0;
        S_pcm_sample       <= 24'sd0;
        S_acc_add          <= 32'd0;
    end else begin
        O_audio_valid <= 1'b0;
        S_acc_add = S_sample_acc + SAMPLE_RATE_HZ;

        // 分数分频产生 48kHz 采样使能
        if (S_acc_add >= CLK_FREQ_HZ) begin
            S_sample_acc  <= S_acc_add - CLK_FREQ_HZ;
            O_audio_valid <= 1'b1;

            // 下一个采样点
            S_phase_acc <= S_phase_acc + W_note_inc;
            if (S_phase_acc[31])
                S_pcm_sample <= AMP;
            else
                S_pcm_sample <= -AMP;

            O_audio_left_data  <= S_pcm_sample;
            O_audio_right_data <= S_pcm_sample;

            // do/re/mi/fa/so/la/si/do 循环
            if (S_note_sample_cnt == NOTE_HOLD_SAMPLES - 1) begin
                S_note_sample_cnt <= 32'd0;
                if (S_note_idx == 3'd7)
                    S_note_idx <= 3'd0;
                else
                    S_note_idx <= S_note_idx + 3'd1;
            end else begin
                S_note_sample_cnt <= S_note_sample_cnt + 32'd1;
            end
        end else begin
            S_sample_acc <= S_acc_add;
        end
    end
end

endmodule
