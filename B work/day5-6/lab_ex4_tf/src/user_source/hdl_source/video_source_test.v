

module video_source_test #(
    parameter HTOTAL  = 2200,
    parameter HACTIVE = 1920,
    parameter HFP     = 88,
    parameter HSA     = 44,
    parameter HBP     = 148,

    parameter VTOTAL  = 1125,
    parameter VACTIVE = 1080,
    parameter VFP     = 4,
    parameter VSA     = 5,
    parameter VBP     = 36
) 
(
    input wire         I_clk,
    input wire         I_rst,

    input wire         I_tpg_trig_en,

    output reg         O_video_user,
    output reg         O_video_valid,
    output reg         O_video_last,
    output wire[23:0]  O_video_data,
    input wire         I_video_ready

);


    localparam VBLANK = VTOTAL - VACTIVE;
    localparam HBLANK = HTOTAL - HACTIVE;


    reg        S_tpg_en;
    reg[13:0]  S_col_cnt;
    reg[13:0]  S_line_cnt;
	reg[7:0]   S_tpg_data;


    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst)
            S_tpg_en <= 1'b0;
        else
            if(I_tpg_trig_en)
                S_tpg_en <= 1'b1;
            else
                S_tpg_en <= S_tpg_en;
    end


    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst || !S_tpg_en)
            S_col_cnt <= 'd0;
        else
            if(S_col_cnt == HTOTAL-1)
                S_col_cnt <= 'd0;
            else
                S_col_cnt <= S_col_cnt + 1'b1;
    end


    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst || !S_tpg_en)
            S_line_cnt <= 'd0;
        else
            if(S_col_cnt == HTOTAL-1)
                begin
                    if(S_line_cnt == VTOTAL-1)
                        S_line_cnt <= 'd0;
                    else
                        S_line_cnt <= S_line_cnt + 1'b1;
                end
            else
                S_line_cnt <= S_line_cnt;
    end


    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst || !S_tpg_en)
            O_video_valid <= 1'b0;
        else
            if(S_line_cnt >= VBLANK && S_col_cnt >= HBLANK)
                O_video_valid <= 1'b1;
            else
                O_video_valid <= 1'b0;
    end

    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst || !S_tpg_en)
            O_video_user <= 1'b0;
        else
            if(S_line_cnt == VBLANK && S_col_cnt == HBLANK)
                O_video_user <= 1'b1;
            else
                O_video_user <= 1'b0;
    end

    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst || !S_tpg_en)
            O_video_last <= 1'b0;
        else
            if(S_line_cnt >= VBLANK && S_col_cnt == HTOTAL-1)
                O_video_last <= 1'b1;
            else
                O_video_last <= 1'b0;
    end

	
    always @ (posedge I_clk) begin
    	if(O_video_valid)
        	S_tpg_data <= S_tpg_data + 1'b1;
       	else	
           	S_tpg_data <= 'd0;
    end


    assign O_video_data = {8'd0,8'h0,S_tpg_data};

    
endmodule