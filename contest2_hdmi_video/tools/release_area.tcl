# Preserve all v53 features; only brightness control/panel/tone are modified.
set prj_name camera_to_dsi_display_hdmi
set device_name ph1_35p.db
set package_name PH1P35MDG324
set speed 3
set top_model_name design_top_user
set start_step read_design
set end_step opt_place
set area_option -packarea
set arr_filter on
set arr_rwns 0
set drHoldFix on
set ADCList {"../user_source/constraints_source/pin.adc"}
set SDCList {"camera_to_dsi_display.sdc"}
set IpADCList {ddr2 ../user_source/hdl_source/ph1p35_ddr/ddr2/src/adc/ddr2.adc}
set IpSDCList {ddr2 ../user_source/hdl_source/ph1p35_ddr/ddr2/src/sdc/ddr2.sdc w128_d512_fifo ../user_source/ip_source/w128_d512_fifo/w128_d512_fifo.tcl}
set alRun syn_1
if {[catch {
 set synWildParams {rtl adder_mux_unsharing off gate opt_area high gate pack_effort high place seed 1}
 source "$env(ANLOGIC_TD_HOME)/doc/scripts/DefaultFlow.tcl"
} issue]} {puts stderr "HDMI_RELEASE_AREA_FAILED $issue";exit 1}
puts HDMI_RELEASE_AREA_FLOW_COMPLETE
exit 0
