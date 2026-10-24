if {[catch {
 debug_mode off
 connect_cable -host_name 127.0.0.1:5555
 set target [string trim [read_device_id -level 1 -total 2 -cable 0 -host_name 127.0.0.1:5555]]
 if {$target ne "PH1P35MDG324"} {error "Unexpected target <$target>"}
 puts DELIVERY_V94_TARGET_CONFIRMED
 download -bit firmware/camera_hdmi_v94_fpga_mcu_flash.bit -mode program_spi -v -spd 7 -cable 0 -flashsize 128 -total_dev 2 -cur_dev 1 -bypass 5
} issue]} {puts stderr "DELIVERY_V94_PROGRAM_FAILED <$issue>";exit 1}
puts DELIVERY_V94_FLASH_PROGRAM_VERIFY_COMPLETE
exit 0
