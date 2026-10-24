`timescale 1ns/1ps
module tb_digit_equivalence_v67r1;
 tb_digit_video_v67 base();
 wire ov;wire [3:0] oi;wire [7:0] oc;
 ua_digit_boundary_reference #(.IMG_WIDTH(384),.IMG_HEIGHT(464),
 .OUTER_X0(24),.OUTER_Y0(40),.OUTER_W(288),.OUTER_H(384),
 .INNER_X0(48),.INNER_Y0(64),.INNER_W(240),.INNER_H(336),
 .CELL_W(48),.CELL_H(48),.CELL_MIN(72)) reference_dut(
 base.clk,base.rst,base.l,base.u,base.pixels,base.v,ov,oi,oc);
 always @(posedge base.clk)begin
  #1;
  if(base.rst)begin
   if({base.valid,base.id,base.confidence}!=={ov,oi,oc})$fatal(1,"RASTER_PUBLIC_MISMATCH");
   if(reference_dut.geometry_ready && base.v)begin
    if(base.dut.cell_sample_en!==reference_dut.cell_sample_en)$fatal(1,"RASTER_ENABLE_MISMATCH xy=%0d,%0d",base.dut.cur_x_grp,base.dut.cur_y);
    if(base.dut.cell_sample_en && {base.dut.cell_col,base.dut.cell_row}!=={reference_dut.cell_col,reference_dut.cell_row})$fatal(1,"RASTER_BIN_MISMATCH");
   end
  end
 end
endmodule
