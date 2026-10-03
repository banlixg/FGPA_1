onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_key_led/sys_clk
add wave -noupdate /tb_key_led/sys_rst_n
add wave -noupdate -radix binary /tb_key_led/key
add wave -noupdate -radix binary /tb_key_led/led
add wave -noupdate -radix unsigned /tb_key_led/uut/led_control
add wave -noupdate -radix unsigned /tb_key_led/uut/cnt
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {4297920 ps} 0}
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
configure wave -timelineunits ns
update
WaveRestoreZoom {0 ps} {4725 ns}
