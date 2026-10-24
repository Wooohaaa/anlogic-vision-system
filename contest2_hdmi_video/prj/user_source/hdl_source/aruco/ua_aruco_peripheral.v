// Camera snapshot and safe servo register bank on the hard MCU AHB master.
// Reset defaults to legacy GPIO PWM routing; v27 MCU explicitly selects safe
// hardware PWM with ARM=0 before starting image processing.
module ua_aruco_peripheral #(
    parameter integer IMG_WIDTH=1280,IMG_HEIGHT=720,ENABLE_STEPPER=0
)(
    input src_clk,bus_clk,rst_n,
    input [95:0] rgb,input valid,sof,eol,
    input [1:0] htrans,input hwrite,input [30:0] haddr,
    input [2:0] hsize,input [31:0] hwdata,
    output reg [31:0] hrdata,output reg [1:0] hresp,output reg hready,
    input legacy_pwm_a,legacy_pwm_b,output pwm_a,pwm_b,input detect_enable,
    output reg result_toggle,output reg result_valid,output reg [11:0] result_id_bcd,
    output reg [21:0] result_corner0,result_corner1,result_corner2,result_corner3,
    output reg [25:0] result_edge0,result_edge1,result_edge2,result_edge3,
    output [10:0] bus_debug,
    output [166:0] result_axes, // {valid,3*Q10 equations,centre/+X/+Y/+Z points}
    output [1:0] motor_step,motor_dir,motor_awake
);
    (* ASYNC_REG="TRUE" *) reg [1:0] src_reset,bus_reset;
    always @(posedge src_clk or negedge rst_n)
        if(!rst_n)src_reset<=0;else src_reset<={src_reset[0],1'b1};
    always @(posedge bus_clk or negedge rst_n)
        if(!rst_n)bus_reset<=0;else bus_reset<={bus_reset[0],1'b1};
    wire [19:0] paddr;wire psel,penable,pwrite;
    // Slow control level crosses from the 100MHz debounced-key domain.
    (* ASYNC_REG="TRUE" *) reg [1:0] detect_sync;
    always @(posedge bus_clk or negedge rst_n)
        if(!rst_n)detect_sync<=0;
        else detect_sync<={detect_sync[0],detect_enable};
    wire [31:0] pwdata;wire [3:0] pstrobe;
    wire [31:0] snap_data;wire snap_ready,snap_error;
    wire [31:0] bridge_rdata;wire [1:0] bridge_resp;wire bridge_ready;
    wire [2:0] bridge_state;wire bridge_invalid;
    reg [31:0] control_data;
    reg axis_valid;
    reg [87:0] axis_points;
    reg [77:0] axis_lines;
    assign result_axes={axis_valid,axis_lines,axis_points};
    reg pwm_override,pwm_arm,pwm_update;
    reg [15:0] pulse_a,pulse_b;
    wire out_a,out_b,timed_out;
    wire stepper_window=ENABLE_STEPPER!=0 && paddr>=20'h180 && paddr<20'h1a0;
    wire [31:0] stepper_data;
    wire stepper_error;
    wire snapshot_window=paddr<20'h100 || paddr>=20'h1000;
    wire control_known=paddr==20'h100 || paddr==20'h104 || paddr==20'h108 || paddr==20'h10c ||
                      paddr==20'h110 || paddr==20'h114 || paddr==20'h118 ||
                      paddr==20'h11c || paddr==20'h120 || paddr==20'h124 || paddr==20'h128 ||
                      paddr==20'h12c || paddr==20'h130 ||
                      paddr==20'h134 || paddr==20'h138 || paddr==20'h13c || paddr==20'h140 ||
                      paddr==20'h144 || paddr==20'h148 || paddr==20'h14c;
    wire control_error=!control_known || (pwrite && (pstrobe!=4'hf || paddr==20'h10c));
    wire [31:0] prdata=snapshot_window?snap_data:(stepper_window?stepper_data:control_data);
    wire pready=snapshot_window?snap_ready:1'b1;
    wire pslverr=snapshot_window?snap_error:(stepper_window?stepper_error:control_error);
    ua_aruco_ahb_bridge bridge(
        .clk(bus_clk),.rst_n(bus_reset[1]),.htrans(htrans),.hwrite(hwrite),
        .haddr(haddr),.hsize(hsize),.hwdata(hwdata),.hrdata(bridge_rdata),
        .hresp(bridge_resp),.hready(bridge_ready),.paddr(paddr),.psel(psel),
        .penable(penable),.pwrite(pwrite),.pwdata(pwdata),.pstrobe(pstrobe),
        .prdata(prdata),.pready(pready),.pslverr(pslverr),
        .debug_state(bridge_state),.debug_invalid(bridge_invalid));
    // Sampled by the top-level diagnostic trace only when the hard-MCU HRESP
    // asserts. Bits: reset, bridge state, invalid, APB select/enable/ready/error,
    // bridge HRESP[0], and bridge HREADY.
    assign bus_debug={bus_reset[1],bridge_state,bridge_invalid,psel,penable,
                      pready,pslverr,bridge_resp[0],bridge_ready};
    // Hard MCU return pins have tight hold requirements. Capture the entire
    // response on the FALLING edge: data/ready/error then remain coherent for
    // half a cycle before the MCU rising-edge sample, and half a cycle after.
    // The bridge still advances only on the following rising edge, matching
    // the master's completion edge; APB traffic is synchronous to bus_clk.
    always @(negedge bus_clk or negedge rst_n)begin
        if(!rst_n)begin hrdata<=0;hresp<=0;hready<=0;end
        else if(!bus_reset[1])begin hrdata<=0;hresp<=0;hready<=0;end
        else begin hrdata<=bridge_rdata;hresp<=bridge_resp;hready<=bridge_ready;end
    end
    ua_aruco_snapshot #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT)) snapshot(
        src_clk,src_reset[1],rgb,valid,sof,eol,bus_clk,bus_reset[1],
        paddr,psel && snapshot_window,penable,pwrite,pwdata,pstrobe,snap_data,snap_ready,snap_error);
    generate if(ENABLE_STEPPER!=0)begin:gen_stepper
        ua_stepper_position motors(.clk(bus_clk),.rst_n(bus_reset[1]),.addr(paddr[4:0]),
            .select(psel && stepper_window),.enable(penable),.write(pwrite),.wdata(pwdata),
            .strobe(pstrobe),.rdata(stepper_data),.error(stepper_error),
            .step(motor_step),.dir(motor_dir),.awake(motor_awake));
        assign out_a=0;assign out_b=0;assign timed_out=0;
    end else begin:gen_servo_fixture
        // Historical simulation compatibility only; absent from product v69.
        ua_servo_pwm_safe servo(bus_clk,bus_reset[1],pwm_arm,pwm_update,pulse_a,pulse_b,out_a,out_b,timed_out);
        assign stepper_data=0;assign stepper_error=0;
        assign motor_step=0;assign motor_dir=0;assign motor_awake=0;
    end endgenerate
    assign pwm_a=ENABLE_STEPPER!=0?1'b0:(pwm_override?out_a:legacy_pwm_a);
    assign pwm_b=ENABLE_STEPPER!=0?1'b0:(pwm_override?out_b:legacy_pwm_b);
    always @*begin
        control_data=0;
        case(paddr)
            20'h100:control_data=ENABLE_STEPPER!=0?32'd0:{23'd0,timed_out,6'd0,pwm_arm,pwm_override};
            20'h104:control_data=ENABLE_STEPPER!=0?32'd0:{16'd0,pulse_a};
            20'h108:control_data=ENABLE_STEPPER!=0?32'd0:{16'd0,pulse_b};
            20'h10c:control_data={31'd0,detect_sync[1]}; // Read-only SW2 enable.
            20'h110:control_data={result_valid,axis_valid,18'd0,result_id_bcd};
            20'h114:control_data={10'd0,result_corner0};
            20'h118:control_data={10'd0,result_corner1};
            20'h11c:control_data={10'd0,result_corner2};
            20'h120:control_data={10'd0,result_corner3};
            20'h124:control_data={6'd0,result_edge0};
            20'h128:control_data={6'd0,result_edge1};
            20'h12c:control_data={6'd0,result_edge2};
            20'h130:control_data={6'd0,result_edge3};
            20'h134:control_data={10'd0,axis_points[21:0]};
            20'h138:control_data={10'd0,axis_points[43:22]};
            20'h13c:control_data={10'd0,axis_points[65:44]};
            20'h140:control_data={10'd0,axis_points[87:66]};
            20'h144:control_data={6'd0,axis_lines[25:0]};
            20'h148:control_data={6'd0,axis_lines[51:26]};
            20'h14c:control_data={6'd0,axis_lines[77:52]};
        endcase
    end
    always @(posedge bus_clk or negedge rst_n)begin
        if(!rst_n)begin
            pwm_override<=0;pwm_arm<=0;pwm_update<=0;pulse_a<=1500;pulse_b<=1500;
            result_toggle<=0;result_valid<=0;result_id_bcd<=0;
            axis_valid<=0;axis_points<=0;axis_lines<=0;
            result_corner0<=0;result_corner1<=0;result_corner2<=0;result_corner3<=0;
            result_edge0<=0;result_edge1<=0;result_edge2<=0;result_edge3<=0;
        end else if(!bus_reset[1])begin
            pwm_override<=0;pwm_arm<=0;pwm_update<=0;pulse_a<=1500;pulse_b<=1500;
            result_toggle<=0;result_valid<=0;result_id_bcd<=0;
            axis_valid<=0;axis_points<=0;axis_lines<=0;
            result_corner0<=0;result_corner1<=0;result_corner2<=0;result_corner3<=0;
            result_edge0<=0;result_edge1<=0;result_edge2<=0;result_edge3<=0;
        end else begin
            pwm_update<=0;
            if(psel && penable && pwrite && !snapshot_window && !control_error)begin
                case(paddr)
                    20'h100:if(ENABLE_STEPPER==0)begin pwm_override<=pwdata[0];pwm_arm<=pwdata[1];pwm_update<=pwdata[2];end
                    20'h104:if(ENABLE_STEPPER==0)pulse_a<=pwdata[15:0];
                    20'h108:if(ENABLE_STEPPER==0)pulse_b<=pwdata[15:0];
                    20'h110:begin
                        result_valid<=pwdata[31];
                        axis_valid<=pwdata[31] && pwdata[30];
                        result_id_bcd<=pwdata[11:0];
                        result_toggle<=~result_toggle;
                    end
                    20'h114:result_corner0<=pwdata[21:0];
                    20'h118:result_corner1<=pwdata[21:0];
                    20'h11c:result_corner2<=pwdata[21:0];
                    20'h120:result_corner3<=pwdata[21:0];
                    20'h124:result_edge0<=pwdata[25:0];
                    20'h128:result_edge1<=pwdata[25:0];
                    20'h12c:result_edge2<=pwdata[25:0];
                    20'h130:result_edge3<=pwdata[25:0];
                    20'h134:axis_points[21:0]<=pwdata[21:0];
                    20'h138:axis_points[43:22]<=pwdata[21:0];
                    20'h13c:axis_points[65:44]<=pwdata[21:0];
                    20'h140:axis_points[87:66]<=pwdata[21:0];
                    20'h144:axis_lines[25:0]<=pwdata[25:0];
                    20'h148:axis_lines[51:26]<=pwdata[25:0];
                    20'h14c:axis_lines[77:52]<=pwdata[25:0];
                endcase
            end
        end
    end
endmodule
