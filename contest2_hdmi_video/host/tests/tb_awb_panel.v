`timescale 1ns/1ps
module tb_awb_panel;
reg clk=0,source_clk=0,rst=0;
reg [3:0] buttons=4'b1111;
wire [3:0] states;wire [2:0] mode;
wire key=states[2];
ua_mode_ctrl #(.DEBOUNCE_CYCLES(4)) keys(.I_clk(clk),.I_rst_n(rst),.I_button(buttons),
 .O_algo_mode(mode),.O_button_state(states),.O_mode_changed(),.O_mode_next(),.O_mode_prev(),.O_exposure_inc(),.O_exposure_dec());
always #5 clk=~clk;always #7 source_clk=~source_clk;
wire request;
integer i;
ua_button_toggle_embedded dut(clk,rst,key,request);
initial begin
 repeat(4) @(negedge clk);rst=1;
 repeat(150) @(negedge clk);
 if(!request) $fatal(1,"reset/default snapshot");
 // Sub-debounce contact chatter must not toggle AWB.
 for(i=0;i<3;i=i+1) begin buttons[2]=0;@(negedge clk);buttons[2]=1;@(negedge clk);end
 repeat(20) @(negedge clk);if(!request) $fatal(1,"button chatter toggled AWB");
 buttons[2]=0;repeat(80) @(negedge clk);
 if(request) $fatal(1,"long press repeated/failed toggle");
 buttons[2]=1;repeat(20) @(negedge clk);buttons[2]=0;
 repeat(20) @(negedge clk);buttons[2]=1;
 if(!request) $fatal(1,"second press failed");
 repeat(20) @(negedge clk);buttons[3]=0;repeat(30) @(negedge clk);buttons[3]=1;
 repeat(20) @(negedge clk);if(!request || mode!=0) $fatal(1,"KEY4 changed state");
 buttons[0]=0;repeat(30) @(negedge clk);buttons[0]=1;repeat(20) @(negedge clk);
 if(mode!=1 || !request) $fatal(1,"KEY1 mode control changed");
 buttons[1]=0;repeat(30) @(negedge clk);buttons[1]=1;repeat(20) @(negedge clk);
 if(mode!=0 || !request) $fatal(1,"KEY2 mode control changed");
 $display("AWB_PANEL_PASS actual_key_debounce KEY1_KEY2_unchanged KEY3_one_toggle_per_press");$finish;
end
endmodule
