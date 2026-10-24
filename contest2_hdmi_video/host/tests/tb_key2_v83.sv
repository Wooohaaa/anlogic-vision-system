`timescale 1ns/1ps
module tb_key2_v83;
 reg clk=0,rst=0;always #5 clk=~clk;
 reg [3:0] buttons=15;wire [2:0] mode;wire prev;
 ua_mode_ctrl #(.DEBOUNCE_CYCLES(4),.KEY2_TRACKING(1)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_button(buttons),.O_algo_mode(mode),.O_mode_prev(prev));
 always @(posedge clk)if(rst && prev)$fatal(1,"KEY2 must not select mode");
 task settle;repeat(20)@(negedge clk);endtask
 initial begin
 #2;rst=0;#10;rst=1;settle;
 buttons=13;settle;if(mode!=0)$fatal(1,"KEY2 changed mode");
 buttons=15;settle;buttons=14;settle;if(mode!=1)$fatal(1,"KEY1 missing");
 repeat(4)settle;if(mode!=1)$fatal(1,"held key repeated");
 buttons=15;settle;buttons=12;settle;if(mode!=2)$fatal(1,"KEY1/2 chord");
 $display("KEY2_V83_MODE_PASS");$finish;
 end
endmodule
