// HX1P35A: on-board clock C4, USB-UART RX J1 / TX H1.
// PH1P35 hard MCU uses a 50 MHz external clock in PLL bypass mode.
module ua_tracking_mcu #(
    parameter integer ENABLE_ARUCO=0,IMG_WIDTH=1280,IMG_HEIGHT=720,ENABLE_STEPPER=0,ENABLE_BUS_TRACE=1
)(input clk_50m, input uart_rx, input target_uart, input key2_n,
                output uart_tx, output target_enable, output servo_pwm, output servo_pwm_b,
                input video_clk,video_rst_n,input [95:0] video_rgb,
                input video_valid,video_sof,video_eol,input aruco_enable,
                input display_clk,display_rst_n,
                output O_aruco_valid,output [11:0] O_aruco_id_bcd,
                output [21:0] O_aruco_corner0,O_aruco_corner1,O_aruco_corner2,O_aruco_corner3,
                output [25:0] O_aruco_edge0,O_aruco_edge1,O_aruco_edge2,O_aruco_edge3,
                output reg [166:0] O_aruco_axes,
                output [1:0] motor_step,motor_dir,motor_awake);
    wire [2:0] key_n = {1'b1,key2_n,1'b1}; // KEY2 -> MCU GPIO4, active low.
    // Synchronize asynchronous buttons; debounce and PWM are MCU C code.
    (* ASYNC_REG = "TRUE" *) reg [2:0] key_meta = 3'b111;
    (* ASYNC_REG = "TRUE" *) reg [2:0] key_sync = 3'b111;
    always @(posedge clk_50m) begin
        key_meta <= key_n;
        key_sync <= key_meta;
    end
    reg [15:0] startup_count = 16'd0;
    always @(posedge clk_50m)
        if (!startup_count[15]) startup_count <= startup_count + 1'b1;
    // MCU core_reset / por_reset are active HIGH (board MCU guide).
    wire mcu_reset = !startup_count[15];
    // Match the TD MCU IP wrapper: with DPLL bypass enabled, the Fabric AHB
    // runs from core_clk. The primitive's raw ahb_clk is feedback only; using
    // that raw output to sample requests mixes the hard-core and Fabric phases.
    wire ahb_clock=clk_50m;
    wire ahb_clock_feedback;
    wire gpio_pwm_a,gpio_pwm_b;
    wire [1:0] ahb_trans,ahb_resp;
    wire ahb_write,ahb_ready;
    wire [30:0] ahb_addr;
    wire [2:0] ahb_size;
    wire [31:0] ahb_wdata,ahb_rdata;
    wire [10:0] ahb_debug;
    wire aruco_result_toggle_bus,aruco_result_valid_bus;
    wire [166:0] aruco_axes_bus;
    wire [11:0] aruco_result_id_bcd_bus;
    wire [21:0] aruco_result_corner0_bus,aruco_result_corner1_bus;
    wire [21:0] aruco_result_corner2_bus,aruco_result_corner3_bus;
    wire [25:0] aruco_result_edge0_bus,aruco_result_edge1_bus;
    wire [25:0] aruco_result_edge2_bus,aruco_result_edge3_bus;
    generate if(ENABLE_ARUCO!=0)begin : gen_aruco
        ua_aruco_peripheral #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT),.ENABLE_STEPPER(ENABLE_STEPPER)) peripheral(
            .src_clk(video_clk),.bus_clk(ahb_clock),.rst_n(!mcu_reset && video_rst_n),
            .rgb(video_rgb),.valid(video_valid),.sof(video_sof),.eol(video_eol),
            .htrans(ahb_trans),.hwrite(ahb_write),.haddr(ahb_addr),.hsize(ahb_size),.hwdata(ahb_wdata),
            .hrdata(ahb_rdata),.hresp(ahb_resp),.hready(ahb_ready),
            .legacy_pwm_a(gpio_pwm_a),.legacy_pwm_b(gpio_pwm_b),.pwm_a(servo_pwm),.pwm_b(servo_pwm_b),
            .detect_enable(aruco_enable),
            .result_toggle(aruco_result_toggle_bus),.result_valid(aruco_result_valid_bus),
            .result_id_bcd(aruco_result_id_bcd_bus),
            .result_corner0(aruco_result_corner0_bus),.result_corner1(aruco_result_corner1_bus),
            .result_corner2(aruco_result_corner2_bus),.result_corner3(aruco_result_corner3_bus),
            .result_edge0(aruco_result_edge0_bus),.result_edge1(aruco_result_edge1_bus),
            .result_edge2(aruco_result_edge2_bus),.result_edge3(aruco_result_edge3_bus),
            .bus_debug(ahb_debug),.result_axes(aruco_axes_bus),
            .motor_step(motor_step),.motor_dir(motor_dir),.motor_awake(motor_awake));
    end else begin : gen_legacy
        assign servo_pwm=gpio_pwm_a;assign servo_pwm_b=gpio_pwm_b;
        assign motor_step=0;assign motor_dir=0;assign motor_awake=0;
        assign ahb_rdata=0;assign ahb_resp=0;assign ahb_ready=1;
        assign aruco_result_toggle_bus=0;assign aruco_result_valid_bus=0;
        assign aruco_result_id_bcd_bus=0;
        assign aruco_result_corner0_bus=0;assign aruco_result_corner1_bus=0;
        assign aruco_result_corner2_bus=0;assign aruco_result_corner3_bus=0;
        assign aruco_result_edge0_bus=0;assign aruco_result_edge1_bus=0;
        assign aruco_result_edge2_bus=0;assign aruco_result_edge3_bus=0;
        assign ahb_debug=0;
        assign aruco_axes_bus=167'd0;
    end endgenerate
    // Bundled-data CDC: MCU writes the four coordinates and BCD ID first,
    // then toggles result_toggle_bus with the final status write. The payload
    // remains stable for the whole frame interval; HDMI captures the complete
    // bank only after the toggle traverses this 2FF synchronizer.
    (* ASYNC_REG = "TRUE" *) reg [1:0] aruco_result_toggle_sync;
    reg aruco_result_toggle_seen;
    reg aruco_result_valid_disp;
    reg [11:0] aruco_result_id_bcd_disp;
    reg [21:0] aruco_result_corner0_disp,aruco_result_corner1_disp;
    reg [21:0] aruco_result_corner2_disp,aruco_result_corner3_disp;
    reg [25:0] aruco_result_edge0_disp,aruco_result_edge1_disp;
    reg [25:0] aruco_result_edge2_disp,aruco_result_edge3_disp;
    always @(posedge display_clk or negedge display_rst_n)begin
        if(!display_rst_n)begin
            aruco_result_toggle_sync<=0;aruco_result_toggle_seen<=0;
            aruco_result_valid_disp<=0;aruco_result_id_bcd_disp<=0;
            O_aruco_axes<=167'd0;
            aruco_result_corner0_disp<=0;aruco_result_corner1_disp<=0;
            aruco_result_corner2_disp<=0;aruco_result_corner3_disp<=0;
            aruco_result_edge0_disp<=0;aruco_result_edge1_disp<=0;
            aruco_result_edge2_disp<=0;aruco_result_edge3_disp<=0;
        end else begin
            aruco_result_toggle_sync<={aruco_result_toggle_sync[0],aruco_result_toggle_bus};
            if(aruco_result_toggle_sync[1]!=aruco_result_toggle_seen)begin
                aruco_result_toggle_seen<=aruco_result_toggle_sync[1];
                aruco_result_valid_disp<=aruco_result_valid_bus;
                O_aruco_axes<=aruco_axes_bus;
                aruco_result_id_bcd_disp<=aruco_result_id_bcd_bus;
                aruco_result_corner0_disp<=aruco_result_corner0_bus;
                aruco_result_corner1_disp<=aruco_result_corner1_bus;
                aruco_result_corner2_disp<=aruco_result_corner2_bus;
                aruco_result_corner3_disp<=aruco_result_corner3_bus;
                aruco_result_edge0_disp<=aruco_result_edge0_bus;
                aruco_result_edge1_disp<=aruco_result_edge1_bus;
                aruco_result_edge2_disp<=aruco_result_edge2_bus;
                aruco_result_edge3_disp<=aruco_result_edge3_bus;
            end
        end
    end
    assign O_aruco_valid=aruco_result_valid_disp;
    assign O_aruco_id_bcd=aruco_result_id_bcd_disp;
    assign O_aruco_corner0=aruco_result_corner0_disp;assign O_aruco_corner1=aruco_result_corner1_disp;
    assign O_aruco_corner2=aruco_result_corner2_disp;assign O_aruco_corner3=aruco_result_corner3_disp;
    assign O_aruco_edge0=aruco_result_edge0_disp;assign O_aruco_edge1=aruco_result_edge1_disp;
    assign O_aruco_edge2=aruco_result_edge2_disp;assign O_aruco_edge3=aruco_result_edge3_disp;
    // Hard MCU GPIO0 -> LED1; GPIO1 -> candidate expansion signal.
    // All pulse generation is done by MCU C firmware.
    wire gpio0_out;
    // Diagnostic scan only: GPIO0 has no external pad; GPIO7 is otherwise idle.
    // No PWM/control outputs are changed. Read after the first transaction has
    // settled with the CPU halted; this is not a general coherent CDC mailbox.
    wire bus_trace_bit;
    generate if(ENABLE_BUS_TRACE!=0)begin:gen_trace
    ua_aruco_bus_trace bus_trace(
        .bus_clk(ahb_clock),.rst_n(!mcu_reset),.htrans(ahb_trans),
        .haddr(ahb_addr),.hsize(ahb_size),.hwrite(ahb_write),
        .hready(ahb_ready),.hresp(ahb_resp),.bus_debug(ahb_debug),.scan_clk(clk_50m),
        .scan_step(gpio0_out),.scan_bit(bus_trace_bit));
    end else begin:gen_no_trace
        assign bus_trace_bit=1'b0;
    end endgenerate
    PH1P_PHY_MCU #(
        .MCU_JTAG_SEL("0"),
        .MCU_RESET_VECTOR(32'h08000000),
        .MCU_DPLL_FEED_TYPE("EXTERNAL"),
        .MCU_DPLL_BYPASS("ENABLE"),
        .MCU_DPLL_POST_DIV(0),
        .AHB_FREQ("50"), .QSPI1_FREQ("12.5")
    ) mcu (
        .core_clk(clk_50m), .timer_clk(clk_50m), .fb_clk(ahb_clock_feedback),
        .core_reset(mcu_reset), .por_reset(mcu_reset), .core_clk_en(1'b1),
        .dbg_stop(1'b0), .dbg_stop_on_reset(1'b1), .dbg_stop_at_boot(1'b0),
        .dbg_mux_sel(2'b11), .nmi(1'b0), .clic_irq(23'd0),
        .jtag_tck(1'b0), .jtag_tms(1'b0), .jtag_tdi(1'b0),
        .gpio0_in(1'b0), .gpio0_out(gpio0_out), .gpio1_in(1'b0), .gpio1_out(gpio_pwm_a),
        .gpio2_in(1'b0), .gpio2_out(gpio_pwm_b), .gpio3_in(key_sync[0]),
        .gpio4_in(key_sync[1]), .gpio5_in(key_sync[2]), .gpio6_in(1'b0), .gpio6_out(target_enable), .gpio7_in(bus_trace_bit),
        .uart0_rx(uart_rx), .uart0_tx(uart_tx), .uart1_rx(target_uart),
        .i2c_sda_in(1'b1), .i2c_scl_in(1'b1),
        .qspi1_d0_in(1'b0), .qspi1_d1_in(1'b0), .qspi1_d2_in(1'b0), .qspi1_d3_in(1'b0),
        .qspi0_dw32_sel(1'b0), .qspi0_spare_sel(1'b0), .ahb_clk(ahb_clock_feedback),
        .htrans(ahb_trans),.hwrite(ahb_write),.haddr(ahb_addr),.hsize(ahb_size),.hwdata(ahb_wdata),
        .hrdata(ahb_rdata), .hresp(ahb_resp), .hready(ahb_ready),
        .apb_clk(clk_50m), .apb_rst(mcu_reset),
        .prdata(32'd0), .pready(1'b1), .pslverr(1'b0),
        .scan_mode_n(1'b1), .scan_en_n(1'b1), .pll_bypass(1'b0), .pib_pll_bypass(1'b0),
        .scan_rst_n(1'b0), .scan_in(73'd0),
        .wrapper_scan_in_0(1'b0), .wrapper_scan_in_1(1'b0), .chain_scan_in(1'b0)
    );
    PH1P_LOGIC_QSPI2MCU qspi_route(.qspi_pib_sel_i(1'b1));
endmodule

// First-transaction evidence retained independently of APB address decoding.
// A 64-bit read starts at bit0 and advances on each GPIO0 rising edge, wraps
// after bit63. CPU must stay OFF/halted and GPIO0 low outside this diagnostic.
module ua_aruco_bus_trace(
    input bus_clk,rst_n,input [1:0] htrans,input [30:0] haddr,
    input [2:0] hsize,input hwrite,hready,input [1:0] hresp,input [10:0] bus_debug,
    input scan_clk,scan_step,output reg scan_bit
);
    reg seen,error_seen,done_seen;
    reg [30:0] address;
    reg [2:0] size;
    reg write;
    reg [10:0] error_debug;
    reg [1:0] trans;
    always @(posedge bus_clk or negedge rst_n)begin
        if(!rst_n)begin seen<=0;error_seen<=0;done_seen<=0;
            address<=0;size<=0;write<=0;trans<=0;error_debug<=0;end
        else begin
            if(!seen && htrans[1])begin
                seen<=1;address<=haddr;size<=hsize;write<=hwrite;trans<=htrans;
            end
            if(seen && hresp!=0)begin
                if(!error_seen)error_debug<=bus_debug;
                error_seen<=1;
            end
            if(seen && hready)done_seen<=1;
        end
    end
    reg step_last;
    reg [5:0] position;
    always @(posedge scan_clk or negedge rst_n)begin
        if(!rst_n)begin position<=0;step_last<=0;end
        else begin
            step_last<=scan_step;
            if(scan_step && !step_last)position<=position+6'd1;
        end
    end
    wire [63:0] record={8'ha8,seen,error_seen,done_seen,1'b1,trans,write,size,
                        error_debug,address[19:0],15'h52a5};
    // Hard MCU GPIO inputs have a tight hold requirement. A falling-edge
    // output keeps the serial bit stable on both sides of its rising sample.
    always @(negedge scan_clk or negedge rst_n)begin
        if(!rst_n)scan_bit<=0;
        else scan_bit<=record[position];
    end
endmodule
