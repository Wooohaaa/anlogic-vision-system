`timescale 1ns/1ps
module tb_aruco_ahb_bridge;
    reg clk=0,rst=0;always #5 clk=~clk;
    reg [1:0] trans=0;reg write=0;reg [30:0] address=0;
    reg [2:0] size=2;reg [31:0] data=0;
    wire [31:0] result;wire [1:0] response;wire hready;
    wire [19:0] pa;wire ps,pe,pw;wire [31:0] pd;wire [3:0] strobe;
    wire [2:0] debug_state;wire debug_invalid;
    reg [31:0] shadow=0;integer delays=0,writes=0,error_low=0;
    wire pready=delays==2;
    wire error=pa==20'h80;
    ua_aruco_ahb_bridge dut(clk,rst,trans,write,address,size,data,result,response,hready,
                           pa,ps,pe,pw,pd,strobe,shadow,pready,error,debug_state,debug_invalid);
    always @(posedge clk)begin
        if(ps && pe && !pready)delays<=delays+1;
        if(!ps)delays<=0;
        if(ps && pe && pready && pw && !error)begin shadow<=pd;writes<=writes+1;end
        if(response==1 && !hready)error_low<=error_low+1;
    end
    task transaction(input wr,input [30:0] addr,input [2:0] sz,input [31:0] value,
                     input expect_error,input [31:0] expected_read);
        integer guard;
        begin
            @(negedge clk);while(!hready)@(negedge clk);
            trans=2;write=wr;address=addr;size=sz;data=32'hdeadbeef;
            @(negedge clk);trans=0;data=value;guard=0;
            while(!hready)begin @(negedge clk);guard=guard+1;if(guard>20)$fatal(1,"AHB hung");end
            if(response!={1'b0,expect_error})$fatal(1,"AHB response %b",response);
            if(!wr && !expect_error && result!==expected_read)$fatal(1,"read %h expected %h",result,expected_read);
            @(negedge clk);data=0;
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst=1;
        transaction(1,0,2,32'h12345678,0,0);
        transaction(0,0,2,0,0,32'h12345678);
        transaction(1,1,2,32'hff,1,0); // Alignment rejection, no write.
        transaction(1,0,0,32'hff,1,0); // Byte access rejected.
        transaction(1,31'h100000,2,32'hff,1,0); // Outside aperture.
        transaction(1,31'h80,2,32'hff,1,0); // APB error -> two-cycle AHB error.
        if(writes!=1 || error_low!=4)$fatal(1,"side effect/error count %d %d",writes,error_low);
        transaction(1,0,2,32'h76543210,0,0);
        transaction(0,0,2,0,0,32'h76543210);
        $display("ARUCO_AHB_BRIDGE_PASS data_phase_wait_error_alignment_recovery");$finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
