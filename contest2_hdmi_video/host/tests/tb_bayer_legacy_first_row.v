`timescale 1ns/1ps
// Reproduce the exact first-row window/parity assignments in the legacy
// raw_matrix_3x3_buffer: all three lines are row zero, bayer_ypos=!0.
module tb_bayer_legacy_first_row;
  reg clk=0,rst=0,v=0;
  wire [127:0] rgb;wire ov;
  always #5 clk=~clk;
  wire [95:0] row_zero={24'd0,8'd100,8'd180,8'd100,8'd180,8'd100,8'd180,24'd0};
  bilinear_interpolation #(.BAYER_MODE("BGGR")) dut(
    .I_clk(clk),.I_rst_n(rst),.I_tlast(1'b0),.I_tuser(1'b0),.I_tvalid(v),
    .I_tready(),.bayer_ypos(1'b1),.matrix_last_line(row_zero),
    .matrix_cur_line(row_zero),.matrix_next_line(row_zero),
    .O_tlast(),.O_tuser(),.O_tdata(rgb),.O_tvalid(ov),.O_tready(1'b1));
  initial begin
    repeat(4) @(negedge clk);rst=1;v=1;
    repeat(10) @(negedge clk);
    if(!ov || rgb[23:16]!==8'd100) $fatal(1,"legacy reproduction changed");
    $display("LEGACY_BAYER_TOP_ROW_REPRODUCED R=%0d expected=40 (G incorrectly used as R)",rgb[23:16]);
    $finish;
  end
endmodule
