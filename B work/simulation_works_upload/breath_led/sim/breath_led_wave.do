onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -format Analog-Step -height 150 -max 50000.0 -radix unsigned /tb_breath_led/uut/duty_cycle
add wave -noupdate /tb_breath_led/uut/inc_dec_flag
add wave -noupdate -label LED1 {/tb_breath_led/uut/led[0]}
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {4105562482821 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits us
update
WaveRestoreZoom {4103501 us} {4106501 us}
