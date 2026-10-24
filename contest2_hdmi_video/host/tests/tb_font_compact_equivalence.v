`timescale 1ns/1ps
module tb_font_compact_equivalence;
 reg clk=0;always #5 clk=~clk;
 reg [7:0] code=0;reg [3:0] row=0;
 wire [15:0] sync_bits,async_bits,golden;
 reg [15:0] expected;integer c,r,n;
 osd_char_v17_reference original(code,row,golden);
 osd_char_lib #(.SYNC_READ(1)) sync_font(clk,code,row,sync_bits);
 osd_char_lib #(.SYNC_READ(0)) async_font(clk,code,row,async_bits);
 function keep;
 input integer v;
 begin keep=(v>=48&&v<=57)||(v>=65&&v<=90)||(v>=97&&v<=122)||
  v==32||v==44||v==45||v==46||v==58||v==63||v==128||v==129;end
 endfunction
 initial begin
  n=0;
  for(c=0;c<256;c=c+1)for(r=0;r<16;r=r+1)begin
   @(negedge clk);code=c;row=r;#1;
   expected=keep(c)?golden:16'd0;
   if(async_bits!==expected)$fatal(1,"async font code=%h row=%d",code,row);
   @(posedge clk);#1;
   if(sync_bits!==expected)$fatal(1,"sync font code=%h row=%d expected=%h got=%h",code,row,expected,sync_bits);
   n=n+1;
  end
  $display("FONT_COMPACT_PASS exhaustive=%0d retained_exact removed_blank sync1 async0",n);$finish;
 end
endmodule
