`timescale 1ns/1ps
module tb_hand_finger_gap;
 reg clk=0,rst=0,valid=0;always #5 clk=~clk;
 ua_hand_profile #(.DYNAMIC_ROI(1),.SAMPLE_STEP(4),.FINGER_GAP_SCALE(4)) dut(
  .I_clk(clk),.I_rst_n(rst),.I_clear(1'b0),.I_sample_valid(valid),
  .I_motion_hit(1'b0),.I_x_grp(10'd100),.I_y(10'd150),.I_rgb(96'd0),
  .I_frame_done(1'b0),.O_result_valid(),.O_id(),.O_tip_count(),
  .O_box_valid(),.O_box_xmin(),.O_box_xmax(),.O_box_ymin(),.O_box_ymax());
 initial begin
  repeat(4)@(negedge clk);rst=1;
  force dut.finger_run_complete=1;force dut.finger_row_run_count=2;
  force dut.loc_seen=1;force dut.loc_xmin=30;force dut.loc_xmax=100;
  force dut.loc_ymin=200;force dut.loc_complete_len=8;
  force dut.loc_prev1_len=8;force dut.loc_prev2_len=8;
  force dut.finger_prev2_start=30;force dut.loc_prev2_end=37;
  force dut.finger_prev1_start=70;force dut.loc_prev1_end=77;
  force dut.loc_complete_start=95;force dut.loc_complete_end=102;
  valid=1;#1;
  if(dut.finger_triplet!==1)$fatal(1,"valid 4x gap boundary rejected");
  force dut.finger_prev1_start=71;#1;
  if(dut.finger_triplet!==0)$fatal(1,"gap above 4x accepted");
  force dut.finger_prev1_start=70;force dut.loc_complete_len=17;#1;
  if(dut.finger_triplet!==0)$fatal(1,"unbalanced run sizes accepted");
  force dut.loc_complete_len=8;force dut.loc_ymin=100;#1;
  if(dut.finger_triplet!==0)$fatal(1,"runs below palm accepted");
  valid=0;#1;
  if(dut.finger_triplet!==0)$fatal(1,"invalid sample created evidence");
  $display("HAND_FINGER_GAP_PASS gap_boundary ratio palm invalid_sample");$finish;
 end
endmodule
