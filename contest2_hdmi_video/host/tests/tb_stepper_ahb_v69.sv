`timescale 1ns/1ps
module tb_stepper_ahb_v69;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0;reg [1:0] htrans=0;reg hwrite=0;
    reg [30:0] haddr=0;reg [2:0] hsize=2;reg [31:0] hwdata=0;
    wire [31:0] hrdata;wire [1:0] hresp;wire hready;
    wire [1:0] step,dir,awake;wire result_valid;wire [11:0] result_id;
    ua_aruco_peripheral #(.IMG_WIDTH(64),.IMG_HEIGHT(32),.ENABLE_STEPPER(1)) dut(
        .src_clk(clk),.bus_clk(clk),.rst_n(rst_n),.rgb(96'd0),.valid(1'b0),.sof(1'b0),.eol(1'b0),
        .htrans(htrans),.hwrite(hwrite),.haddr(haddr),.hsize(hsize),.hwdata(hwdata),
        .hrdata(hrdata),.hresp(hresp),.hready(hready),.legacy_pwm_a(1'b1),.legacy_pwm_b(1'b1),
        .detect_enable(1'b1),.result_valid(result_valid),.result_id_bcd(result_id),
        .motor_step(step),.motor_dir(dir),.motor_awake(awake));
    task transaction(input wr,input [30:0] a,input [31:0] d,input [31:0] expected);
        integer cycles;
        begin
            @(negedge clk);while(!hready)@(negedge clk);
            htrans=2;hwrite=wr;haddr=a;hsize=2;
            @(negedge clk);htrans=0;hwdata=d;cycles=0;
            do begin @(posedge clk);cycles++;
                if(cycles>20)$fatal(1,"AHB timeout %h",a);
            end while(!hready);
            if(hresp)$fatal(1,"AHB error %h",a);
            if(!wr && hrdata!==expected)$fatal(1,"Read %h got %h want %h",a,hrdata,expected);
            @(negedge clk);hwdata=0;hwrite=0;
        end
    endtask
    initial begin
        repeat(6)@(negedge clk);rst_n=1;repeat(5)@(negedge clk);
        transaction(0,0,0,32'h41525531);
        transaction(0,31'h180,0,32'h53545032);
        transaction(0,31'h184,0,0);
        transaction(1,31'h100,7,0); // stale old servo firmware cannot drive motors
        if(step || awake || dut.pwm_a || dut.pwm_b)$fatal(1,"Old servo route survived");
        transaction(1,31'h190,32'h5a45524f,0);
        transaction(0,31'h184,0,2);
        transaction(1,31'h190,32'h41524d32,0);
        transaction(0,31'h184,0,11);
        transaction(1,31'h188,32'hfff60014,0);
        transaction(1,31'h18c,32'hff9c00c8,0);
        transaction(1,31'h190,32'h434d5432,0);
        transaction(0,31'h198,0,32'hfff60014);
        transaction(0,31'h19c,0,32'hff9c00c8);
        // ArUco publication remains independent while motors are armed.
        transaction(1,31'h110,32'h80000023,0);
        if(!result_valid || result_id!=12'h023)$fatal(1,"ArUco bank corrupted");
        transaction(1,31'h190,0,0);repeat(800)@(negedge clk);
        if(step || awake)$fatal(1,"AHB OFF failed");
        $display("STEPPER_ARUCO_AHB_V69_PASS");$finish;
    end
    initial begin #1000000;$fatal(1,"timeout");end
endmodule
