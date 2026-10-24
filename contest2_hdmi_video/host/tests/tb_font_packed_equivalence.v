`timescale 1ns/1ps
module tb_font_packed_equivalence;
 reg clk=0;always #5 clk=~clk;
 reg [7:0] code=255;reg [3:0] row=15;
 wire [15:0] bits;
 wire [15:0] golden;reg [15:0] expected;integer a,i,seed=10415;
 osd_char_v17_reference baseline(code,row,golden);
 osd_char_lib #(.SYNC_READ(1)) dut(clk,code,row,bits);
 initial begin
  for(i=0;i<8192;i=i+1)begin
   a=(i<4096)?i:($unsigned($random(seed))%4096);
   @(negedge clk);code=a/16;row=a%16;
   #1;expected=golden;
   @(posedge clk);#1;
   if(bits!==expected)$fatal(1,"FONT_MISMATCH code=%h row=%d expected=%h actual=%h",code,row,expected,bits);
  end
  $display("FONT_PACKED_EXHAUSTIVE_PASS codes=256 rows=16 random=4096 latency=one_clock");
  $finish;
 end
endmodule
