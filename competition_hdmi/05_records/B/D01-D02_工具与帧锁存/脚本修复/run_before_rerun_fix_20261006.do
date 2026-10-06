# ModelSim 10.4. First cd to this sim folder, then do run.do.
# Relative paths; finite run; keep GUI open.
proc abort_run {message} {
    puts "TEST_FAIL: $message"
    if {[batch_mode]} {quit -force -code 1}
    error $message
}
onerror {abort_run "ModelSim command failed; see transcript.log"}
catch {quit -sim}
transcript file transcript.log
transcript on
if {[file exists result.txt]} {file delete result.txt}
if {![file isdirectory work]} {vlib work}
vmap work work
vlog ../src/team_frame_latch.v ../src/tb_team_frame_latch.v
if {[info exists INJECT_FAIL] && $INJECT_FAIL} {
    vsim -voptargs=+acc work.tb_team_frame_latch +INJECT_FAIL
} else {
    vsim -voptargs=+acc work.tb_team_frame_latch
}
log -r /*
if {![batch_mode]} {
    add wave -radix unsigned sim:/tb_team_frame_latch/clk
    add wave -radix unsigned sim:/tb_team_frame_latch/rst_n
    add wave -radix unsigned sim:/tb_team_frame_latch/frame_accept
    add wave -radix unsigned sim:/tb_team_frame_latch/frame_id_in
    add wave -radix unsigned sim:/tb_team_frame_latch/frame_id_out
    add wave -radix unsigned sim:/tb_team_frame_latch/frame_valid
    add wave -radix unsigned sim:/tb_team_frame_latch/accepted_pulse
}
run 1100 ns
if {![file exists result.txt]} {abort_run "No result.txt produced"}
set result_handle [open result.txt r]
set result [read $result_handle]
close $result_handle
if {![string match "ALL_PASS*" $result]} {abort_run $result}
puts "SCRIPT_PASS: $result"
if {![batch_mode]} {wave zoom full}
if {[batch_mode]} {quit -force -code 0}
