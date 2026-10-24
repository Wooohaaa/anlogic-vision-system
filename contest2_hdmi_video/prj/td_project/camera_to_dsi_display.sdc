create_clock -name {sys_clk_50m} -period 20.000 -waveform {0.000 10.000} [get_ports {I_sys_clk}]
create_clock -name {mipi_rx_ck_pad} -period 4.167 -waveform {0.000 2.083} [get_nets {IO_rx_clk_pad_p}]

derive_clocks

# MCU DPLL bypass follows the vendor MCU wrapper: all Fabric AHB registers
# use I_sys_clk / sys_clk_50m directly. The primitive ahb_clk pin is connected
# only to its fb_clk input and does not launch a separate Fabric clock domain.

rename_clock -name {pll_clk_100m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {pll_clk_24m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}]
rename_clock -name {HDMI_PIXEL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]
rename_clock -name {HDMI_SERIAL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[5]}]

# The 720p product path instantiates the MIPI receiver under gen_ae.  Keep the
# generated-scope marker in the clock query; the old unsuffixed path leaves the
# clock group empty and makes TD analyze CDC paths as synchronous.
rename_clock -name {MIPI_RX_BYTE_CLK} [get_clocks {gen_ae$u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.o_fabric_div4_8_clk}]

set_clock_groups -asynchronous \
    -group [get_clocks {mipi_rx_ck_pad MIPI_RX_BYTE_CLK}] \
    -group [get_clocks {sys_clk_50m pll_clk_100m pll_clk_24m HDMI_PIXEL_CLK HDMI_SERIAL_CLK}] \
    -group [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}]

# AE display only: request/acknowledge synchronizers between 100m and 24m.
# Match only the first receiver stage and restrict the launching clock; even
# when two stages share a packed cell, meta -> sync remains normally timed.
# v56+ compact panel: use the unique source net, not a renamed/packed flop.
set_false_path -from [get_clocks {pll_clk_100m}] -through [get_nets {gen_ae$u_ae_panel/req}] -to [get_clocks {pll_clk_24m}]
# The ack receiver is packed under another register's name by TD. Use its
# unique SOURCE net instead; ack_meta -> ack_sync launches at 100m and is
# therefore not excluded by this 24m source-clock restriction.
set_false_path -from [get_clocks {pll_clk_24m}] -through [get_nets {gen_ae$u_ae_panel/ack}] -to [get_clocks {pll_clk_100m}]
# The source holds the complete AE/AG packet until the next request. The
# receiver samples DATA after ack_meta, ack_sync and the FSM's subsequent
# edge: at least 20ns after source capture. Bound only this held DATA path
# (including gain arithmetic) to 15ns, leaving >=5ns protocol margin.
set_max_delay 15.000 -datapath_only -from [get_clocks {pll_clk_24m}] -through [get_nets {gen_ae$u_ae_panel/packet[*]}] -to [get_clocks {pll_clk_100m}]

# SW2 is a debounced, held control LEVEL, intentionally received by the
# detect_sync[0] -> detect_sync[1] 2FF synchronizer in the 50MHz MCU domain.
# The first flop may resolve asynchronously; functional use is exclusively
# detect_sync[1]. Exclude only 100MHz launch -> first receiver, NOT the whole
# clock pair. Restricting the source clock preserves 50MHz meta -> sync timing
# even if TD packs both registers into a common cell. '?' matches literal
# square brackets in the synthesized register name detect_sync_reg[0].
set_false_path -from [get_clocks {pll_clk_100m}] -to [get_cells -hier {*u_tracking_mcu/gen_aruco$peripheral/detect_sync_reg?0?*}]
