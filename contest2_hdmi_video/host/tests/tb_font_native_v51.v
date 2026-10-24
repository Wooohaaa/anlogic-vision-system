`timescale 1ns/1ps
module tb_font_native_v51;
reg clk=0;always #5 clk=~clk;
reg [7:0]code=0;reg[3:0]row=0;wire[15:0]actual,expected;
osd_char_lib #(.SYNC_READ(1)) dut(clk,code,row,actual);
font_v49_reference #(.SYNC_READ(1)) ref_dut(clk,code,row,expected);
integer c,r;
initial begin
 repeat(10)@(negedge clk); // Vendor global start-up releases at 20 ns.
 for(c=0;c<256;c=c+1)for(r=0;r<16;r=r+1)begin
  @(negedge clk);code=c;row=r;
  @(posedge clk);#1;
  if(actual!==expected)$fatal(1,"FONT_NATIVE_MISMATCH code=%h row=%d actual=%h expected=%h",code,row,actual,expected);
 end
 $display("FONT_NATIVE_EXACT_PASS rows=4096");$finish;
end
endmodule
