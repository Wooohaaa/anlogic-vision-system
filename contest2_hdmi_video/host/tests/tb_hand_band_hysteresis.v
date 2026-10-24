`timescale 1ns/1ps
module tb_hand_band_hysteresis;
 reg clk=0,rst=0;always #5 clk=~clk;
 integer i;
 ua_hand_profile #(.DYNAMIC_ROI(1),.SAMPLE_STEP(4),.LOC_MIN_AREA(160),
  .LOC_BAND_HYSTERESIS(1),.FINGER_GAP_SCALE(4)) dut(
  .I_clk(clk),.I_rst_n(rst),.I_clear(1'b0),.I_sample_valid(1'b0),
  .I_motion_hit(1'b0),.I_x_grp(10'd0),.I_y(10'd0),.I_rgb(96'd0),
  .I_frame_done(1'b0),.O_result_valid(),.O_id(),.O_tip_count(),
  .O_box_valid(),.O_box_xmin(),.O_box_xmax(),.O_box_ymin(),.O_box_ymax());
 initial begin
  repeat(4)@(negedge clk);rst=1;
  @(negedge clk);
  force dut.loc_seen=1;force dut.loc_ymin=128;
  for(i=0;i<6;i=i+1)begin
   dut.loc_bin_area[i]=0;dut.loc_bin_xmin[i]=i*10;dut.loc_bin_xmax[i]=i*10+20;
  end
  dut.loc_bin_area[1]=750;dut.loc_bin_area[2]=1000;
  #1;if(dut.loc_best_bin!==1 || dut.loc_best_xmin!==10 || dut.loc_best_center_y!==192)
   $fatal(1,"equal 3/4 support must keep previous band");
  dut.loc_bin_area[1]=749;
  #1;if(dut.loc_best_bin!==2)$fatal(1,"strong new band must acquire");
  dut.loc_bin_area[1]=0;
  #1;if(dut.loc_best_bin!==2)$fatal(1,"empty old band latched");
  dut.loc_bin_area[1]=159;dut.loc_bin_area[2]=160;
  #1;if(dut.loc_best_bin!==2)$fatal(1,"unsupported old band retained");
  dut.loc_bin_area[1]=10000;dut.loc_bin_area[2]=10240;
  #1;if(dut.loc_best_bin!==1)$fatal(1,"maximum band area overflow");
  force dut.loc_seen=0;
  #1;if(dut.loc_best_bin!==2)$fatal(1,"startup must choose strongest band");
  $display("HAND_BAND_HYSTERESIS_PASS");$finish;
 end
endmodule
