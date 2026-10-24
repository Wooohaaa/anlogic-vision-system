`timescale 1ns/1ps
// State-policy unit tests; complement full raster/skin/profile regressions.
`ifndef HAND_DUT
`define HAND_DUT ua_hand_profile
`endif
module tb_hand_dropout;
 reg clk=0; always #5 clk=~clk;
 reg rst=0,clear=0,done=0;
 wire [1:0] id; wire box;
 `HAND_DUT #(.DYNAMIC_ROI(1),.SAMPLE_STEP(4),.MOTION_GATE_ENABLE(0)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_clear(clear),.I_sample_valid(1'b0),
 .I_motion_hit(1'b0),.I_x_grp(10'd0),.I_y(10'd0),.I_rgb(96'd0),
 .I_frame_done(done),.O_id(id),.O_box_valid(box),.O_result_valid(),
 .O_tip_count(),.O_box_xmin(),.O_box_xmax(),.O_box_ymin(),.O_box_ymax());
 task locate;
 input integer amount;
 begin
  force dut.loc_best_area=amount;
  @(negedge clk);done=1;@(negedge clk);done=0;
  release dut.loc_best_area;
 end
 endtask
 task commit;
 input [1:0] candidate;
 begin
  @(negedge clk);force dut.classified=candidate;dut.state=6;
  @(negedge clk);release dut.classified;
 end
 endtask
 task reset;
 begin
  @(negedge clk);clear=1;@(negedge clk);clear=0;
  repeat(100)@(negedge clk);
 end
 endtask
 integer n;
 initial begin
  repeat(4)@(negedge clk);rst=1;
  locate(200);if(!dut.roi_valid_r)$fatal(1,"no acquisition");
  locate(0);if(!dut.roi_valid_r)$fatal(1,"first gap discarded ROI");
  locate(0);if(!dut.roi_valid_r)$fatal(1,"second gap discarded ROI");
  locate(0);if(dut.roi_valid_r)$fatal(1,"stale ROI survived third miss");
  reset;
  commit(1);commit(0);commit(1);
  if(id!=1||!box)$fatal(1,"single-gap candidate not acquired");
  for(n=0;n<4;n=n+1)begin
   commit(0);if(id!=1)$fatal(1,"early dropout %0d",n);
  end
  commit(0);if(id!=0||box)$fatal(1,"withdrawn hand did not clear");
  reset;
  commit(1);commit(0);commit(0);commit(1);
  if(id!=0)$fatal(1,"two-gap evidence falsely confirmed");
  commit(2);if(id!=0)$fatal(1,"different class falsely confirmed");
  commit(2);if(id!=2)$fatal(1,"matching new class not confirmed");
  reset;if(id!=0||box||dut.roi_valid_r)$fatal(1,"clear incomplete");
  $display("HAND_DROPOUT_PASS bounded_ROI one_gap_acquire withdrawal class_change clear");
  $finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
