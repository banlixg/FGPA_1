module design_top_i2s_test_single_pll_fix64 (
    input  wire I_sys_clk,
    input  wire I_key_in,

    output wire O_ddc_scl,
    inout  wire IO_ddc_sda,

    output wire O_tmds_ch0_p,
    output wire O_tmds_ch1_p,
    output wire O_tmds_ch2_p,
    output wire O_tmds_clk_p
);

    wire       S_pll_lock;
    wire       S_rst;
    wire       S_pixel_clk;
    wire       S_serial_clk;
    wire       S_audio_mclk;

    wire       S_i2s_BCLK;
    wire       S_i2s_LRCK;
    wire       S_i2s_DOUT;

    wire       S_axis_s_user;
    wire       S_axis_s_valid;
    wire       S_axis_s_last;
    wire[23:0] S_axis_s_data;
    wire       S_axis_s_ready;

    wire       S_audio_valid;
    wire[23:0] S_audio_left_data;
    wire[23:0] S_audio_right_data;

    wire[9:0]  S_ch0_tmds_data;
    wire[9:0]  S_ch1_tmds_data;
    wire[9:0]  S_ch2_tmds_data;
    wire[9:0]  S_clk_tmds_data;

    wire       S_acr_valid;
    wire[19:0] S_acr_cts;
    wire[19:0] S_acr_n;

    wire       S_key_trig;
    wire       S_edid_valid;
    wire[7:0]  S_edid_data;

    // refclk=50MHz
    // clk0_out=74.25MHz  (pixel)
    // clk1_out=371.25MHz (serial)
    // clk2_out=12.288MHz (audio mclk)
    PLL_HDMI_AUDIO U_pll_hdmi_audio(
        .refclk   ( I_sys_clk    ),
        .reset    ( 1'b0         ),
        .extlock  ( S_pll_lock   ),
        .clk0_out ( S_pixel_clk  ),
        .clk1_out ( S_serial_clk ),
        .clk2_out ( S_audio_mclk )
    );

    assign S_rst = ~S_pll_lock;

    i2s_test_tone_gen_single_pll_fix64 #(
        .SAMPLE_RATE ( 48000 ),
        .SAMPLE_BITS ( 24    ),
        .TONE_HZ     ( 1000  )
    ) u_i2s_test_tone_gen_single_pll_fix64 (
        .I_mclk      ( S_audio_mclk ),
        .I_rst       ( S_rst        ),
        .O_i2s_BCLK  ( S_i2s_BCLK   ),
        .O_i2s_LRCK  ( S_i2s_LRCK   ),
        .O_i2s_DOUT  ( S_i2s_DOUT   )
    );

    I2S_receiver u_I2S_receiver(
        .I_clk              ( S_pixel_clk        ),
        .I_rst              ( S_rst              ),
        .I_i2s_BCLK         ( S_i2s_BCLK         ),
        .I_i2s_LRCK         ( S_i2s_LRCK         ),
        .I_i2s_DOUT         ( S_i2s_DOUT         ),
        .O_audio_valid      ( S_audio_valid      ),
        .O_audio_left_data  ( S_audio_left_data  ),
        .O_audio_right_data ( S_audio_right_data )
    );

    audio_arc_calculate #(
        .ACR_N         ( 6144 )
    ) u_audio_arc_calculate (
        .I_clk         ( S_pixel_clk    ),
        .I_rst         ( S_rst          ),
        .I_audio_valid ( S_audio_valid  ),
        .O_acr_valid   ( S_acr_valid    ),
        .O_acr_cts     ( S_acr_cts      ),
        .O_acr_n       ( S_acr_n        )
    );

    key_remove_shakes u_key_remove_shakes(
        .I_clk          ( S_pixel_clk ),
        .I_rst_n        ( S_pll_lock  ),
        .I_key_in       ( I_key_in    ),
        .O_key_trig_out ( S_key_trig  )
    );

    video_source_test #(
        .HTOTAL        ( 2200 ),
        .HACTIVE       ( 1920 ),
        .HFP           ( 88   ),
        .HSA           ( 44   ),
        .HBP           ( 148  ),
        .VTOTAL        ( 1125 ),
        .VACTIVE       ( 1080 ),
        .VFP           ( 4    ),
        .VSA           ( 5    ),
        .VBP           ( 36   )
    ) U_video_source_test(
        .I_clk         ( S_pixel_clk    ),
        .I_rst         ( S_rst          ),
        .I_tpg_trig_en ( 1'b1           ),
        .O_video_user  ( S_axis_s_user  ),
        .O_video_valid ( S_axis_s_valid ),
        .O_video_last  ( S_axis_s_last  ),
        .O_video_data  ( S_axis_s_data  ),
        .I_video_ready ( S_axis_s_ready )
    );

    hdmi_1_4b_transmitter_core_wrapper #(
        .DEVICE                 ( "EG"     ),
        .HTOTAL                 ( 1650     ),
        .HSA                    ( 40       ),
        .HFP                    ( 110      ),
        .HBP                    ( 220      ),
        .HACTIVE                ( 1280     ),
        .VTOTAL                 ( 750      ),
        .VSA                    ( 5        ),
        .VFP                    ( 5        ),
        .VBP                    ( 20       ),
        .VACTIVE                ( 720      ),
        .VIDEO_VIC              ( 69       ),
        .VIDEO_TPG              ( "Enable" ),
        .VIDEO_FORMAT           ( "RGB"    ),
        .AUDIO_SAMPLE_RATE      ( "48K"    ),
        .IIC_SCL_DIV            ( 125      )
    ) u_hdmi_1_4b_transmitter_core_wrapper(
        .I_pixel_clk        ( S_pixel_clk        ),
        .I_rst              ( S_rst              ),
        .I_edid_read_trig   ( S_key_trig         ),
        .O_edid_read_valid  ( S_edid_valid       ),
        .O_edid_read_data   ( S_edid_data        ),
        .I_axis_s_user      ( S_axis_s_user      ),
        .I_axis_s_valid     ( S_axis_s_valid     ),
        .I_axis_s_last      ( S_axis_s_last      ),
        .I_axis_s_data      ( S_axis_s_data      ),
        .O_axis_s_ready     ( S_axis_s_ready     ),
        .I_audio_valid      ( S_audio_valid      ),
        .I_audio_left_data  ( S_audio_left_data  ),
        .I_audio_right_data ( S_audio_right_data ),
        .I_acr_valid        ( S_acr_valid        ),
        .I_acr_cts          ( S_acr_cts          ),
        .I_acr_n            ( S_acr_n            ),
        .O_video_locked     (                    ),
        .O_ddc_scl          ( O_ddc_scl          ),
        .IO_ddc_sda         ( IO_ddc_sda         ),
        .O_ch0_tmds_data    ( S_ch0_tmds_data    ),
        .O_ch1_tmds_data    ( S_ch1_tmds_data    ),
        .O_ch2_tmds_data    ( S_ch2_tmds_data    ),
        .O_clk_tmds_data    ( S_clk_tmds_data    )
    );

    hdmi_phy_wrapper #(
        .DEVICE ( "EG" )
    ) u_hdmi2phy_wrapper(
        .I_pixel_clk        ( S_pixel_clk     ),
        .I_serial_clk       ( S_serial_clk    ),
        .I_rst              ( S_rst           ),
        .I_tmds_channel_0   ( S_ch0_tmds_data ),
        .I_tmds_channel_1   ( S_ch1_tmds_data ),
        .I_tmds_channel_2   ( S_ch2_tmds_data ),
        .I_tmds_channel_clk ( S_clk_tmds_data ),
        .O_tmds_ch0_p       ( O_tmds_ch0_p    ),
        .O_tmds_ch1_p       ( O_tmds_ch1_p    ),
        .O_tmds_ch2_p       ( O_tmds_ch2_p    ),
        .O_tmds_clk_p       ( O_tmds_clk_p    )
    );

endmodule
