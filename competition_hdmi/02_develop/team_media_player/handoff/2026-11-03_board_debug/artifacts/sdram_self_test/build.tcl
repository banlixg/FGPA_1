import_device eagle_s20.db -package EG4S20BG256
cd C:/Users/23167/AppData/Local/Temp/sdram_test
read_verilog -file {vendor/sdr_as_ram.enc.v vendor/sdr_init_ref.enc.v vendor/sdr_wrrd.enc.v vendor/sdr_as_ram.enc.v vendor/team_board_sdram.v team_mem_pll.v team_sdram_port.v top_sdram_test.v} -include_dir {vendor} -top top_sdram_test
read_adc pin.adc
optimize_rtl
optimize_gate
legalize_phy_inst
place
route
update_timing -mode final
fix_hold
update_timing -mode final
report_timing_summary -file timing.rpt
bitgen -bit top_sdram_test.bit -bin top_sdram_test.bin
puts SDRAM_TEST_BUILD_COMPLETE
exit
