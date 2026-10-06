# ModelSim 10.4 GUI-safe rerun. First cd to this sim folder.
# No application-exit command. Reuse the loaded design with restart.
# For command-line exit codes, use run_batch.do instead.
proc b_stop_test {message} {
    set ::B_LAST_RESULT FAIL
    puts "TEST_FAIL: $message"
    abort 1
}
onerror {set ::B_LAST_RESULT FAIL; puts "TEST_FAIL: ModelSim command failed; see transcript.log"; abort 1}
set B_LAST_RESULT RUNNING
if {![info exists INJECT_FAIL]} {set INJECT_FAIL 0}
if {$INJECT_FAIL != 0 && $INJECT_FAIL != 1} {
    b_stop_test "INJECT_FAIL must be 0 or 1"
}
transcript file transcript.log
transcript on
if {[file exists result.txt]} {file delete result.txt}
set b_has_design [expr {![catch {examine sim:/tb_team_frame_latch/done}]}]
if {![file isdirectory work]} {vlib work}
vmap work work
vlog ../src/team_frame_latch.v ../src/tb_team_frame_latch.v
if {$b_has_design} {
    restart -force
} else {
    vsim -voptargs=+acc work.tb_team_frame_latch
}
log -r /*
if {![batch_mode] && !$b_has_design} {
    add wave -radix unsigned sim:/tb_team_frame_latch/clk
    add wave -radix unsigned sim:/tb_team_frame_latch/rst_n
    add wave -radix unsigned sim:/tb_team_frame_latch/frame_accept
    add wave -radix unsigned sim:/tb_team_frame_latch/frame_id_in
    add wave -radix unsigned sim:/tb_team_frame_latch/frame_id_out
    add wave -radix unsigned sim:/tb_team_frame_latch/frame_valid
    add wave -radix unsigned sim:/tb_team_frame_latch/accepted_pulse
}
# Let initial assignments finish before setting the test-only injection flag.
run 2 ns
force -deposit sim:/tb_team_frame_latch/inject_fail $INJECT_FAIL
run 1098 ns
if {![batch_mode]} {
    configure wave -timelineunits ns
    wave zoom range 0ns 220ns
}
if {![file exists result.txt]} {b_stop_test "No result.txt produced"}
set b_result_handle [open result.txt r]
set b_result [read $b_result_handle]
close $b_result_handle
if {![string match "ALL_PASS*" $b_result]} {b_stop_test $b_result}
set B_LAST_RESULT PASS
puts "SCRIPT_PASS: $b_result"
