if {[catch {
 import_device ph1_35p.db -package PH1P35MDG324 -speed 3
 import_db ../../tmp/v101r1_binary_placed.db
 foreach pattern {{*u_frame_latency/gen_fps*} {*u_hdmi_mixer_user/diag_age*} {*u_compact_ref*} {*u_grid*} {*u_motion_mailbox*} {*u_card*} {*u_digit_mailbox*} {*S_digit_frame*} {*u_codebook*} {*u_blob_shared*gen_eram*storage*}} {
  set n [llength [get_cells -hier $pattern]]
  puts "V101R1_FEATURE_PRESENCE $pattern $n"
  if {$n==0} {error "Required feature pruned: $pattern"}
 }
 clear_sdc -user
 read_sdc camera_to_dsi_display.sdc
 set_param route fix_hold on
 set_param flow qor_monitor off
 route
 phys_opt -effort high -post_route -mode reroute
 route -incremental
 flow_continue_check -step route -wns 0 -name camera_hdmi_v101r1
 fix_hold
 set_param route fix_hold on
 set_param flow qor_monitor on
 # Keep the existing v55 persistent MCU boot path and payload layout.
 set cell [get_cells -hier {*u_tracking_mcu/mcu}]
 if {[llength $cell]!=1} {error "Expected one MCU"}
 set before [get_property ATTRIBUTES $cell]
 set expected [string map {{MCU_RESET_VECTOR = =32'b00001000000000000000000000000000;} {MCU_RESET_VECTOR = =32'b00100000111000000000000000000000;}} $before]
 if {$expected eq $before} {error "Unexpected old reset vector"}
 update_instance_attribute -inst [lindex $cell 0] -attr MCU_RESET_VECTOR -value {=32'b00100000111000000000000000000000}
 if {[get_property ATTRIBUTES $cell] ne $expected} {error "Unexpected MCU attributes"}
 export_db ../../tmp/v101r1_hold_attempt.db
 report_area -io_info -file ../../tmp/v101r1_final_routed.area
 set fp [open ../../tmp/v101r1_final_routed.area r];set area [read $fp];close $fp
 foreach {kind ceiling} {slice 20000 eram 108 dsp 40} {
  if {![regexp [format {(?m)^#%s\s+(\d+)} $kind] $area -> count] || $count>$ceiling} {error "Resource exceeded: $kind"}
 }
 update_timing -mode final
 report_timing_summary -file ../../tmp/v101r1_final_routed.timing
 report_timing_exception -file ../../tmp/v101r1_final_routed.exceptions
 set fp [open ../../tmp/v101r1_final_routed.timing r];set timing [read $fp];close $fp
 if {![regexp {Confidence\s*:\s*Routed} $timing]} {error "Not Routed"}
 if {![regexp {50\.000\s+[0-9]+\s+sys_clk_50m} $timing]} {error "Missing MCU clock"}
 foreach metric {SWNS HWNS STNS HTNS} {
  if {![regexp [format {%s:\s*([-0-9.]+)ns} $metric] $timing -> v]} {error "Missing $metric"}
  if {$v<0 || (($metric=="STNS" || $metric=="HTNS") && $v!=0)} {error "Failed $metric"}
 }
 export_db ../../tmp/v101r1_binary_routed.db
 bitgen -mcu -bit ../../deliverables/camera_hdmi_v101r1_diagnostics_fps_fpga.bit
} issue]} {puts stderr "HDMI_V101R1_ROUTE_FAILED $issue";exit 1}
puts HDMI_V101R1_ROUTED_BIT_COMPLETE
exit 0
