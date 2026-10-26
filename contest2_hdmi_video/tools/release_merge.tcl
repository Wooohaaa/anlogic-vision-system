if {[file exists deliverables/camera_hdmi_v101r1_diagnostics_fps_fpga_mcu_flash.bit]} {error "v101r1 artifact exists"}
if {[catch {
 create_flash_file -target_file deliverables/camera_hdmi_v101r1_diagnostics_fps_fpga.bit -added_file {../firmware/boot/boot.bin:0xE00000 tmp/v101r1_boot/payload.bin:0xE10000} -output deliverables/camera_hdmi_v101r1_diagnostics_fps_fpga_mcu_flash.bit -rom_size 128M
} issue]} {puts stderr "V101R1_FLASH_MERGE_FAILED <$issue>";exit 1}
puts V101R1_FLASH_MERGE_COMPLETE
exit 0
