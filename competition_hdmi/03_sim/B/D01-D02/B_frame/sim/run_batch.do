# Command-line wrapper only: vsim -c -do run_batch.do
if {![batch_mode]} {
    puts "Use do run.do in the GUI; run_batch.do is for vsim -c only."
    abort 1
}
onerror {quit -force -code 1}
set B_LAST_RESULT RUNNING
do run.do
if {$B_LAST_RESULT eq "PASS"} {
    quit -force -code 0
} else {
    quit -force -code 1
}
