`timescale 1ns/1ps
module tb_hand_upper_extent;
 reg clk=0;always #5 clk=~clk;
 reg reset_n=0,clear=0,valid=0,done=0;
 reg [9:0] x=0,y=0;reg [95:0] rgb=0;
 wire result,box;wire [1:0] id;wire [2:0] tips;
 wire [9:0] xmin,xmax,ymin,ymax;
 ua_hand_profile #(.IMG_WIDTH(320),.IMG_HEIGHT(180),.DYNAMIC_ROI(1),
 .SAMPLE_STEP(4),.MOTION_GATE_ENABLE(0)) dut(
 .I_clk(clk),.I_rst_n(reset_n),.I_clear(clear),.I_sample_valid(valid),
 .I_motion_hit(1'b0),.I_x_grp(x),.I_y(y),.I_rgb(rgb),.I_frame_done(done),
 .O_result_valid(result),.O_id(id),.O_tip_count(tips),.O_box_valid(box),
 .O_box_xmin(xmin),.O_box_xmax(xmax),.O_box_ymin(ymin),.O_box_ymax(ymax));
 integer row,col;
 task frame;
 input [23:0] color;
 begin
  for(row=40;row<=56;row=row+8)begin
   for(col=0;col<80;col=col+1)begin
    @(negedge clk);valid=1;x=col;y=row;
    rgb=(col>=20&&col<=24)?{4{color}}:96'd0;
   end
  end
  @(negedge clk);valid=0;
  repeat(2)@(negedge clk);
  done=1;@(negedge clk);done=0;
  repeat(6)@(negedge clk);
 end
 endtask
 initial begin
  repeat(3)@(negedge clk);reset_n=1;
  force dut.roi_x0_r=10;force dut.roi_y0_r=80;force dut.roi_valid_r=1;
  frame(24'hbba094); // valid skin RG/GB=27/12, rejected by legacy 2:1 gate
  if(!dut.extent_box_valid||dut.extent_box_xmin!=20||dut.extent_box_ymin!=40)
   $fatal(1,"upper extent failed valid=%b xmin=%d ymin=%d",dut.extent_box_valid,dut.extent_box_xmin,dut.extent_box_ymin);
  force dut.classified=2;force dut.pending_once=1;force dut.pending=2;
  force dut.qualified_open_hint=0;force dut.qualified_coherent_open=0;
  force dut.xmin=21;force dut.xmax=23;force dut.ymin=90;
  force dut.state=6;
  @(negedge clk);
  if(!box||xmin!=20||xmax!=24||ymin!=40) $fatal(1,"published extent wrong");
  release dut.state;release dut.classified;release dut.pending_once;release dut.pending;
  release dut.qualified_open_hint;release dut.qualified_coherent_open;
  release dut.xmin;release dut.xmax;release dut.ymin;
  @(negedge clk);clear=1;@(negedge clk);clear=0;
  if(dut.extent_box_valid||dut.extent_hit_d1) $fatal(1,"clear did not invalidate extent");
  frame(24'h506482); // R<G<B must not pass unsigned subtract/ratio comparisons
  if(dut.extent_box_valid) $fatal(1,"cool background accepted");
  frame(24'h808080);
  if(dut.extent_box_valid) $fatal(1,"gray background accepted");
  $display("HAND_UPPER_EXTENT_PASS");$finish;
 end
endmodule
