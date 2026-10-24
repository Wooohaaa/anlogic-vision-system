`timescale 1ns/1ps
module tb_awb_wide_arithmetic;
 reg clk=0,rst=0;always #8 clk=~clk;
 wire ir,ol,ou,ov;wire [107:0] od;
 ua_awb_frame #(.OUTPUT_CHANNEL_BITS(9)) dut(.I_clk(clk),.I_rst_n(rst),.I_tlast(1'b0),.I_tuser(1'b0),.I_tdata(96'd0),.I_tvalid(1'b0),.I_tready(ir),.O_tlast(ol),.O_tuser(ou),.O_tdata(od),.O_tvalid(ov),.O_tready(1'b1));
 integer c,g,i;
 reg [19:0] gain;
 reg [31:0] rng=32'h7140a5c3;
 reg [8:0] expected;
 initial begin
  for(g=0;g<4;g=g+1) begin
   case(g)
    0:gain=32768;1:gain=65536;2:gain=93622;3:gain=131072;
   endcase
   for(c=0;c<256;c=c+1) begin
    expected=(c*gain)/65536;
    if(dut.F_output_channel(c[7:0],gain)!==expected) $fatal(1,"wide boundary product mismatch");
   end
  end
  for(i=0;i<20000;i=i+1) begin
   rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
   gain=32768+(rng%98305);c=rng[7:0];
   expected=(c*gain)/65536;
   if(dut.F_output_channel(c[7:0],gain)!==expected) $fatal(1,"wide random product mismatch");
  end
  if(dut.F_output_channel(8'd255,20'd131072)!==9'd510) $fatal(1,"maximum product clipped");
  $display("AWB_WIDE_ARITHMETIC_PASS 21024_vectors min_unity_cast_max_gain full_510_headroom");
  $finish;
 end
endmodule
