`timescale 1ns/1ps
// Vendor-wrapper contract model, not an instruction-level hard-MCU model.
// Raw primitive feedback clock deliberately differs from bypass core_clk.
module tb_aruco_mcu_bypass #(parameter integer RAW_CLOCK_NEGATIVE=0);
    reg clk=0,video=0,display=0,rst=0;
    always #10 clk=~clk;
    always #7 video=~video;
    always #6 display=~display;
    wire uart,enable,pa,pb,valid;wire [11:0] id;
    ua_tracking_mcu #(.ENABLE_ARUCO(1),.IMG_WIDTH(64),.IMG_HEIGHT(32)) dut(
        .clk_50m(clk),.uart_rx(1'b1),.target_uart(1'b1),.uart_tx(uart),
        .target_enable(enable),.servo_pwm(pa),.servo_pwm_b(pb),
        .video_clk(video),.video_rst_n(rst),.video_rgb(96'd0),
        .video_valid(1'b0),.video_sof(1'b0),.video_eol(1'b0),.aruco_enable(1'b0),
        .display_clk(display),.display_rst_n(rst),.O_aruco_valid(valid),
        .O_aruco_id_bcd(id));
    generate if(RAW_CLOCK_NEGATIVE)begin
        initial force dut.ahb_clock=dut.ahb_clock_feedback;
    end endgenerate
    initial begin #101;rst=1;wait(dut.mcu.done);
        if(pa || pb || enable)$fatal(1,"unexpected motion output");
        $display("ARUCO_MCU_BYPASS_PASS core50_raw25_signature_read_PWM_OFF");$finish;
    end
    initial begin #1000000;$fatal(1,"bypass interface timeout");end
endmodule

module PH1P_PHY_MCU #(
    parameter MCU_JTAG_SEL="0",MCU_RESET_VECTOR=32'h08000000,
    MCU_DPLL_FEED_TYPE="EXTERNAL",MCU_DPLL_BYPASS="ENABLE",
    MCU_DPLL_POST_DIV=0,AHB_FREQ="50",QSPI1_FREQ="12.5"
)(
    input core_clk,timer_clk,fb_clk,core_reset,por_reset,core_clk_en,
    input dbg_stop,dbg_stop_on_reset,dbg_stop_at_boot,input [1:0] dbg_mux_sel,
    input nmi,input [22:0] clic_irq,input jtag_tck,jtag_tms,jtag_tdi,
    input gpio0_in,output gpio0_out,input gpio1_in,output gpio1_out,
    input gpio2_in,output gpio2_out,input gpio3_in,gpio4_in,gpio5_in,
    input gpio6_in,output gpio6_out,input gpio7_in,
    input uart0_rx,output uart0_tx,input uart1_rx,
    input i2c_sda_in,i2c_scl_in,qspi1_d0_in,qspi1_d1_in,qspi1_d2_in,qspi1_d3_in,
    input qspi0_dw32_sel,qspi0_spare_sel,output reg ahb_clk=0,
    output reg [1:0] htrans=0,output reg hwrite=0,output reg [30:0] haddr=0,
    output reg [2:0] hsize=2,output reg [31:0] hwdata=0,
    input [31:0] hrdata,input [1:0] hresp,input hready,
    input apb_clk,apb_rst,input [31:0] prdata,input pready,pslverr,
    input scan_mode_n,scan_en_n,pll_bypass,pib_pll_bypass,scan_rst_n,
    input [72:0] scan_in,input wrapper_scan_in_0,wrapper_scan_in_1,chain_scan_in
);
    assign gpio0_out=0;assign gpio1_out=0;assign gpio2_out=0;
    assign gpio6_out=0;assign uart0_tx=1;
    always @(posedge core_clk)ahb_clk<=~ahb_clk;
    reg done=0;integer cycles;
    initial begin
        wait(core_reset===1'b0);repeat(8)@(negedge core_clk);
        // Align request to a falling RAW edge. Sampling requests with raw25
        // instead of bypass core50 loses this one-cycle address phase.
        while(ahb_clk!==1'b1)@(negedge core_clk);
        htrans=2;hwrite=0;haddr=0;hsize=2;
        @(posedge core_clk);@(negedge core_clk);htrans=0;
        cycles=0;
        do begin @(posedge core_clk);cycles=cycles+1;
            if(cycles>12)$fatal(1,"signature transaction missed by bypass clock");
        end while(!hready);
        if(hresp!==0 || hrdata!==32'h41525531)
            $fatal(1,"signature response=%b data=%h",hresp,hrdata);
        if(fb_clk!==ahb_clk)$fatal(1,"raw feedback clock disconnected");
        done=1;
    end
endmodule

module PH1P_LOGIC_QSPI2MCU(input qspi_pib_sel_i);
endmodule
