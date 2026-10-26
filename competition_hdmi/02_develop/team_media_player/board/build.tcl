set here [file dirname [info script]]
cd $here
import_device eagle_s20.db -package EG4S20BG256
read_verilog -file {../rtl/audio/team_audio_file.v ../rtl/audio/team_pcm_fifo.v ../rtl/audio/team_wav_parser.v ../rtl/image/team_bmp_parser.v ../rtl/storage/team_boot_loader.v ../rtl/storage/team_fat32_catalog.v ../rtl/storage/team_fat32_file_reader.v ../rtl/storage/team_fat32_mount.v ../rtl/storage/team_frame_store_writer.v ../rtl/storage/team_image_loader.v ../rtl/storage/team_sd_spi_reader.v ../rtl/storage/team_sdram_port.v ../rtl/storage/team_sector_guard.v ../rtl/storage/team_spi_byte.v ../rtl/team_player_core.v ../rtl/video/team_frame_commit_bridge.v ../rtl/video/team_line_scanout.v ../rtl/video/team_player_control.v ../extensions/fade/rtl/team_fade_ctrl.v ../extensions/fade/rtl/team_fade_effect.v ../extensions/fade/rtl/team_fade_rgb.v vendor/hdmi_1_4b_transmitter_core_wrapper.enc.v vendor/hdmi_phy_warpper.v vendor/lane_lvds_10_1.v vendor/sdr_as_ram.enc.v vendor/sdr_init_ref.enc.v vendor/sdr_wrrd.enc.v vendor/sys_pll.v vendor/team_board_sdram.v vendor/video_pll.v team_mem_pll.v team_video_pll.v team_top.v} -include_dir {vendor} -top team_top
read_adc pin.adc
read_sdc timing.sdc
optimize_rtl
report_area -file team_player_rtl.area
optimize_gate -packarea team_player_gate.area
legalize_phy_inst
export_db team_player_gate.db
place
route
update_timing -mode final
fix_hold
update_timing -mode final
report_area -io_info -file team_player_phy.area
report_timing_summary -file team_player_pr.timing
check_timing -file team_player_check.timing
bitgen -bit team_player.bit
puts TEAM_BUILD_COMPLETE
exit
