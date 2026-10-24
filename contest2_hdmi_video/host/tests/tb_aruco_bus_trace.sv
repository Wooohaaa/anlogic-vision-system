`timescale 1ns/1ps
module tb_aruco_bus_trace;
    reg bus=0,sys=0,rst=0,step=0;
    always #10 bus=~bus;always #7 sys=~sys;
    reg [1:0] trans=0,resp=0;
    reg [30:0] addr=0;reg [2:0] size=0;reg wr=0,ready=0;
    reg [10:0] debug=11'h5a5;
    wire bit_out;reg [63:0] record;integer i;
    ua_aruco_bus_trace dut(bus,rst,trans,addr,size,wr,ready,resp,debug,sys,step,bit_out);
    reg sampled_bit;
    always @(posedge sys)begin
        sampled_bit=bit_out;
        #1;if(rst && bit_out!==sampled_bit)$fatal(1,"scan return changed at MCU rising sample");
    end
    task read_record;
        begin
            for(i=0;i<64;i=i+1)begin
                @(negedge sys);record[i]=bit_out;step=1;
                repeat(3)@(negedge sys);step=0;
                repeat(3)@(negedge sys);
            end
        end
    endtask
    initial begin
        repeat(5)@(negedge sys);rst=1;
        @(negedge bus);trans=2;addr=31'h40000000;size=2;
        @(negedge bus);trans=0;
        repeat(3)@(negedge bus);resp=1;ready=0;
        @(negedge bus);ready=1;
        @(negedge bus);resp=0;
        // A later address cannot overwrite first-transaction evidence.
        trans=2;addr=12;size=1;wr=1;
        @(negedge bus);trans=0;
        repeat(3)@(negedge sys);read_record;
        if(record!=={8'ha8,1'b1,1'b1,1'b1,1'b1,2'd2,1'b0,3'd2,11'h5a5,20'h0,15'h52a5})
            $fatal(1,"wrong trace %h",record);
        read_record;
        if(record[63:56]!==8'ha8 || record[45:35]!==11'h5a5)$fatal(1,"wrap");
        rst=0;repeat(5)@(negedge sys);rst=1;repeat(5)@(negedge sys);read_record;
        if(record[55:53]!==0 || record[45:35]!==0)$fatal(1,"reset");
        $display("ARUCO_BUS_TRACE_V30_PASS first_address_size_error_debug_wrap_reset");$finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
