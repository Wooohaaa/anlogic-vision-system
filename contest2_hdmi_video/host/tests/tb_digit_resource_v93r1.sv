`timescale 1ns/1ps
// The existing RGB oracle supplies stimulus. The frozen pre-optimization RTL
// runs beside the candidate; compare every output and geometry update cycle.
module tb_digit_resource_v93r1;
 parameter W=320,H=240,GAPS=1,SCENES=40,CASE_BASE=0;
 tb_digit_auto_v93 #(.W(W),.H(H),.GAPS(GAPS),.SCENES(SCENES),.CASE_BASE(CASE_BASE)) stimulus();
 wire dv,ev;wire [3:0] id;wire [7:0] conf;wire [56:0] view;
 ua_digit_recognizer_v93_reference #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.AUTO_FIND(1)) reference_dut(
  .I_clk(stimulus.clk),.I_rst_n(stimulus.rst),.I_tlast(stimulus.l),.I_tuser(stimulus.u),
  .I_tdata(stimulus.rgb),.I_tvalid(stimulus.v),.O_digit_valid(dv),.O_digit_id(id),
  .O_digit_confidence(conf),.O_result_event(ev),.O_result_view(view));
 integer checks=0;
 always @(posedge stimulus.clk)begin #2;if(stimulus.rst)begin
  checks=checks+1;
  if({dv,ev,id,conf,view}!=={stimulus.dv,stimulus.event_out,stimulus.id,stimulus.conf,stimulus.view})
   $fatal(1,"RESOURCE_OUTPUT_MISMATCH cycle=%0d scene=%0d",checks,stimulus.scene);
  if({reference_dut.card_found,reference_dut.card_x0,reference_dut.card_x1,reference_dut.card_y0,reference_dut.card_y1}!==
     {stimulus.dut.card_found,stimulus.dut.card_x0,stimulus.dut.card_x1,stimulus.dut.card_y0,stimulus.dut.card_y1})
   $fatal(1,"RESOURCE_CARD_MISMATCH cycle=%0d",checks);
  if({reference_dut.geometry_ready,reference_dut.norm_x0,reference_dut.norm_y0,
      reference_dut.step_x,reference_dut.step_y,reference_dut.cell_snapshot_bits}!==
     {stimulus.dut.geometry_ready,stimulus.dut.norm_x0,stimulus.dut.norm_y0,
      stimulus.dut.step_x,stimulus.dut.step_y,stimulus.dut.cell_snapshot_bits})
   $fatal(1,"RESOURCE_GEOMETRY_MISMATCH cycle=%0d",checks);
 end end
 final $display("DIGIT_RESOURCE_V93R1_COMPARED cycles=%0d",checks);
endmodule
