`timescale 1ns/1ps
module tb_aruco_peripheral_ahb;
    reg clk=0;
    always #10 clk=~clk;
    reg rst_n=0;
    reg [1:0] htrans=0;
    reg hwrite=0;
    reg [30:0] haddr=0;
    reg [2:0] hsize=2;
    reg [31:0] hwdata=0;
    wire [31:0] hrdata;
    wire [1:0] hresp;
    wire hready;
    wire pwm_a,pwm_b,result_toggle,result_valid;
    wire [11:0] result_id_bcd;
    integer cycles;

    ua_aruco_peripheral #(.IMG_WIDTH(1280),.IMG_HEIGHT(720)) dut(
        .src_clk(clk),.bus_clk(clk),.rst_n(rst_n),
        .rgb(96'd0),.valid(1'b0),.sof(1'b0),.eol(1'b0),
        .htrans(htrans),.hwrite(hwrite),.haddr(haddr),.hsize(hsize),.hwdata(hwdata),
        .hrdata(hrdata),.hresp(hresp),.hready(hready),
        .legacy_pwm_a(1'b0),.legacy_pwm_b(1'b0),.pwm_a(pwm_a),.pwm_b(pwm_b),
        .detect_enable(1'b0),.result_toggle(result_toggle),.result_valid(result_valid),
        .result_id_bcd(result_id_bcd));

    task ahb_read(input [30:0] addr,input [31:0] expected);
        begin
            @(negedge clk);
            while(!hready) @(negedge clk);
            htrans=2'b10;hwrite=0;haddr=addr;hsize=3'd2;
            @(posedge clk); // Address phase accepted while idle HREADY is high.
            @(negedge clk);htrans=0;
            cycles=0;
            do begin
                @(posedge clk);cycles=cycles+1;
                if(cycles>12)$fatal(1,"AHB read timeout addr=%h",addr);
            end while(!hready);
            if(hresp!==2'b00)$fatal(1,"AHB read error addr=%h resp=%b",addr,hresp);
            if(hrdata!==expected)$fatal(1,"AHB read data addr=%h got=%h expected=%h",addr,hrdata,expected);
            @(negedge clk);
        end
    endtask

    task ahb_write(input [30:0] addr,input [31:0] value);
        begin
            @(negedge clk);
            while(!hready) @(negedge clk);
            htrans=2'b10;hwrite=1;haddr=addr;hsize=3'd2;hwdata=32'h0;
            @(posedge clk); // Address phase accepted while idle HREADY is high.
            @(negedge clk);htrans=0;hwdata=value;
            cycles=0;
            do begin
                @(posedge clk);cycles=cycles+1;
                if(cycles>12)$fatal(1,"AHB write timeout addr=%h",addr);
            end while(!hready);
            if(hresp!==2'b00)$fatal(1,"AHB write error addr=%h resp=%b",addr,hresp);
            @(negedge clk);hwdata=0;hwrite=0;
        end
    endtask

    initial begin
        repeat(6)@(negedge clk);rst_n=1;
        repeat(5)@(negedge clk);
        ahb_read(31'h00000000,32'h41525531);
        ahb_read(31'h00000004,32'h00000000);
        ahb_write(31'h00000100,32'h00000001);
        ahb_read(31'h00000100,32'h00000101); // Override plus servo timeout status.
        $display("ARUCO_PERIPHERAL_AHB_PASS registered_response_signature_control");
        $finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
