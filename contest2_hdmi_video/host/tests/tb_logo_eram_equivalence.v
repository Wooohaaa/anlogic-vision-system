`timescale 1ns/1ps
module tb_logo_eram_equivalence;
 reg clk=0;always #5 clk=~clk;
 reg [14:0] address=32767;
 wire [24:0] pixel;wire present;
 wire [24:0] golden;reg [24:0] expected=0;
 reg [24:0] expected2=0;
 logo_v17_reference baseline(address,golden);
 integer i,a,prev=0,seed=10415;
 anlogic_logo_rom dut(clk,address,pixel,present);
 initial begin
  repeat(3) @(negedge clk);
  for(i=0;i<65536;i=i+1)begin
   a=(i<32768)?i:($unsigned($random(seed))%32768);
   address=a;
   #1;
   @(posedge clk);#1;
   if(pixel!==expected2 || present!==expected[24])
    $fatal(1,"LOGO_ERAM_MISMATCH address=%0d prev=%0d expected=%h actual=%h",a,prev,expected,pixel);
   expected2=expected;expected=golden;prev=a;@(negedge clk);
  end
  $display("LOGO_ERAM_EXHAUSTIVE_PASS addresses=32768 random=32768 original_RGB_alpha internal_latency=3 contract_model");
  $finish;
 end
endmodule
