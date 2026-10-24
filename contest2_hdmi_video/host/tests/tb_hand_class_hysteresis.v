`timescale 1ns/1ps
module tb_hand_class_hysteresis;
 reg clk=0,rst=0,clear=0;always #5 clk=~clk;
 wire [1:0] id;wire box;
 ua_hand_profile #(.DYNAMIC_ROI(1),.SAMPLE_STEP(4),.CLASS_SWITCH_FRAMES(6)) dut(
  .I_clk(clk),.I_rst_n(rst),.I_clear(clear),.I_sample_valid(1'b0),
  .I_motion_hit(1'b0),.I_x_grp(10'd0),.I_y(10'd0),.I_rgb(96'd0),
  .I_frame_done(1'b0),.O_result_valid(),.O_id(id),.O_tip_count(),
  .O_box_valid(box),.O_box_xmin(),.O_box_xmax(),.O_box_ymin(),.O_box_ymax());
 task commit;
 input [1:0] candidate;
 begin
  @(negedge clk);force dut.classified=candidate;dut.state=6;
  @(negedge clk);release dut.classified;
 end
 endtask
 integer i;
 initial begin
  repeat(4)@(negedge clk);rst=1;
  commit(3);if(id!==0)$fatal(1,"single frame acquired");
  commit(3);if(id!==3)$fatal(1,"initial acquisition slowed");
  commit(2);commit(2);commit(3);
  if(id!==3)$fatal(1,"brief wrong POINT replaced OPEN");
  commit(1);commit(1);commit(1);commit(1);commit(1);
  if(id!==3)$fatal(1,"switch occurred before sixth candidate");
  commit(1);if(id!==1)$fatal(1,"deliberate fist transition rejected");
  for(i=0;i<4;i=i+1)begin
   commit(0);if(id!==1)$fatal(1,"early withdrawal");
  end
  commit(0);if(id!==0 || box)$fatal(1,"withdrawal stuck");
  @(negedge clk);clear=1;@(negedge clk);clear=0;
  if(dut.pending_votes!==0)$fatal(1,"clear retained votes");
  $display("HAND_CLASS_HYSTERESIS_PASS acquisition2 switch6 withdrawal5 clear");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
