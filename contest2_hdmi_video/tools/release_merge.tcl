if {[file exists deliverables/camera_hdmi_v94_fpga_mcu_flash.bit]} {error "v94 artifact exists"}
if {[catch {
 create_flash_file -target_file deliverables/camera_hdmi_v94_digit_auto_fpga.bit -added_file {../firmware/boot/boot.bin:0xE00000 tmp/v94_boot/payload.bin:0xE10000} -output deliverables/camera_hdmi_v94_fpga_mcu_flash.bit -rom_size 128M
} issue]} {puts stderr "V94_FLASH_MERGE_FAILED <$issue>";exit 1}
puts V94_FLASH_MERGE_COMPLETE
exit 0
