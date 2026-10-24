`timescale 1ns/1ps
module tb_aruco_peripheral_errors;
    reg src=0,clk=0,rst=0;always #7 src=~src;always #10 clk=~clk;
    reg [1:0] trans=0;reg wr=0;reg [30:0] addr=0;reg [31:0] data=0;
    wire [31:0] result;wire [1:0] response;wire ready,pa,pb;
    wire result_toggle,result_valid;wire [11:0] result_id_bcd;
    wire [21:0] result_corner0,result_corner1,result_corner2,result_corner3;
    wire [25:0] result_edge0,result_edge1,result_edge2,result_edge3;
    wire [10:0] bus_debug;
    integer errors_low=0;
    reg detect_enable=0;
    ua_aruco_peripheral #(.IMG_WIDTH(64),.IMG_HEIGHT(32)) dut(
        src,clk,rst,96'd0,1'b0,1'b0,1'b0,trans,wr,addr,3'd2,data,
        result,response,ready,1'b0,1'b0,pa,pb,detect_enable,
        result_toggle,result_valid,result_id_bcd,result_corner0,result_corner1,result_corner2,result_corner3,
        result_edge0,result_edge1,result_edge2,result_edge3,bus_debug,);
    always @(posedge clk)if(rst && response==1 && !ready)errors_low=errors_low+1;
    task transaction(input write,input [30:0] address,input [31:0] value,input expected_error);
        integer guard;
        begin
            @(negedge clk);#1;while(!ready)begin @(negedge clk);#1;end
            trans=2;wr=write;addr=address;
            @(negedge clk);#1;trans=0;data=value;
            @(posedge clk);guard=0;
            while(!ready)begin @(posedge clk);guard=guard+1;if(guard>20)$fatal(1,"hung");end
            #1;if(response!={1'b0,expected_error})$fatal(1,"response %b addr%h",response,address);
            if(!expected_error && !write && address==0 && result!==32'h41525531)$fatal(1,"identity");
            if(!expected_error && !write && address=='h10c && result!=={31'd0,detect_enable})$fatal(1,"detector enable CDC");
            @(negedge clk);#1;data=0;
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);rst=1;repeat(8)@(negedge clk);
        transaction(0,0,0,0);
        transaction(0,'h10c,0,0);
        detect_enable=1;repeat(4)@(negedge clk);
        transaction(0,'h10c,0,0);
        detect_enable=0;repeat(4)@(negedge clk);
        transaction(0,'h10c,0,0);
        transaction(0,1,0,1); // Misaligned AHB access.
        transaction(0,'h1000,0,1); // Snapshot not ready.
        transaction(1,'h200,7,1); // Unknown control register cannot arm PWM.
        transaction(1,'h104,1600,0);
        transaction(1,'h100,1,0); // Select hardware PWM, ARM=0.
        transaction(0,0,0,0);
        if(errors_low!=3 || pa || pb)$fatal(1,"error framing/output %d",errors_low);
        $display("ARUCO_PERIPHERAL_PASS half_cycle_return_errors_off_recovery");$finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
