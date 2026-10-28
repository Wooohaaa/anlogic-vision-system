if {[file exists deliverables/camera_system_flash.bit]} {error "release artifact exists"}
if {[catch {
 create_flash_file -target_file deliverables/camera_system_fpga.bit -added_file {../firmware/boot/boot.bin:0xE00000 tmp/release_boot/payload.bin:0xE10000} -output deliverables/camera_system_flash.bit -rom_size 128M
} issue]} {puts stderr "RELEASE_FLASH_MERGE_FAILED <$issue>";exit 1}
puts RELEASE_FLASH_MERGE_COMPLETE
exit 0
