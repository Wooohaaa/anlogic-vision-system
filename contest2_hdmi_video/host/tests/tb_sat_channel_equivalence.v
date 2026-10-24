`timescale 1ns/1ps
module tb_sat_channel_equivalence;
  wire v,u,l; wire [95:0] data;
  ua_photo_finish_96 dut(1'b0,1'b0,1'b0,1'b0,1'b0,96'b0,2'b0,v,u,l,data);
  integer c,m,expected;
  initial begin
    for(c=0;c<256;c=c+1) for(m=0;m<256;m=m+1) begin
      if(c>=m) expected=c+(c-m)/4;
      else expected=c-(m-c)/4;
      if(dut.sat_channel(c,m)!==expected[7:0])
        $fatal(1,"SAT_MISMATCH c=%0d midpoint=%0d expected=%0d actual=%0d",c,m,expected[7:0],dut.sat_channel(c,m));
    end
    $display("SAT_CHANNEL_EXHAUSTIVE_PASS cases=65536");
    $finish;
  end
endmodule
