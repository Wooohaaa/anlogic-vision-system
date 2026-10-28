`timescale 1ns/1ps
// Isolate result publication from pixels: accepted contradictory evidence must
// invalidate hold immediately, while uncertain observations retain a bounded hold.
module tb_digit_publication;
 reg clk=0,rst=0;always #5 clk=~clk;
 wire valid,event_out;wire[3:0]id;wire[7:0]confidence;wire[56:0]view;
 ua_digit_recognizer #(.AUTO_FIND(1)) dut(clk,rst,1'b0,1'b0,96'd0,1'b0,valid,id,confidence,event_out,view);
 integer checks=0;
 task observation(input integer digit,input integer best,input integer second,input integer expect_valid,input integer expect_id);
 begin
  @(negedge clk);dut.result_digit=digit;dut.result_best_distance=best;
  dut.result_second_distance=second;dut.state=3;
  @(posedge clk);#1;
  if(!event_out || valid!==expect_valid[0] || (valid && id!=expect_id))
   $fatal(1,"HOLD_CONTRACT check=%0d observed=%0d best=%0d expected=%0d/%0d actual=%0d/%0d age=%0d",checks,digit,best,expect_valid,expect_id,valid,id,dut.held_age);
  checks=checks+1;
 end endtask
 task reset_case;
 begin
  @(negedge clk);rst=0;repeat(2)@(negedge clk);rst=1;
  force dut.snapshot_geometry_good=1;force dut.current_card_overlaps=1;
  force dut.geometry_ready=1;force dut.feature_quality=1;force dut.frame_count=3;
 end endtask
 initial begin
  reset_case;
  observation(5,0,5,0,15);observation(5,0,5,0,15);observation(5,0,5,1,5);
  // A one-frame rejection is tolerable; a confident different class is not.
  observation(5,9,10,1,5);
  observation(8,0,5,0,15);
  observation(8,0,5,0,15);observation(8,0,5,1,8);
  // Five uncertain frames maximum, followed by silence.
  repeat(5)observation(8,9,10,1,8);
  observation(8,9,10,0,15);
  reset_case;
  observation(3,0,5,0,15);observation(3,0,5,0,15);observation(3,0,5,1,3);
  force dut.snapshot_geometry_good=0;
  observation(3,9,10,0,15);
  force dut.snapshot_geometry_good=1;
  // Returning card must reacquire; missing geometry cannot bridge votes.
  observation(3,0,5,0,15);observation(3,0,5,0,15);observation(3,0,5,1,3);
  reset_case;
  // Alternating accepted classes must never accumulate a false confirmation.
  repeat(4)begin observation(2,0,5,0,15);observation(7,0,5,0,15);end
  $display("DIGIT_PUBLICATION_PASS checks=%0d",checks);$finish;
 end
endmodule
