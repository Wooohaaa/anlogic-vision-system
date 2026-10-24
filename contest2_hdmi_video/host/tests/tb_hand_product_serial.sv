`timescale 1ns/1ps
module tb_hand_product_serial;
parameter A_BITS=32,B_BITS=32,HARD_MULTIPLY=0,COMPACT=1;
reg clk=0;always #5 clk=~clk;
reg rst=0,clear=0,start=0;reg[A_BITS-1:0]a;reg[B_BITS-1:0]b;wire busy,done;wire[A_BITS+B_BITS-1:0]product;
ua_hand_product_serial #(.A_BITS(A_BITS),.B_BITS(B_BITS),.HARD_MULTIPLY(HARD_MULTIPLY),.COMPACT(COMPACT)) dut(clk,rst,clear,start,a,b,busy,done,product);
reg[63:0]rng=64'h18541791ca73ef15;reg[A_BITS+B_BITS-1:0]expected;
integer i,j;
task launch;
begin start=1;@(negedge clk);start=0;end endtask
initial begin
 repeat(5)@(negedge clk);rst=1;
 for(i=0;i<2048;i=i+1)begin
  rng=rng*64'd6364136223846793005+64'd1442695040888963407;a=rng;
  rng=rng*64'd6364136223846793005+64'd1442695040888963407;b=rng;
  case(i)
  0:begin a=0;b={B_BITS{1'b1}};end
  1:begin a={A_BITS{1'b1}};b={B_BITS{1'b1}};end
  2:begin a={1'b1,{(A_BITS-1){1'b0}}};b={1'b1,{(B_BITS-1){1'b0}}};end
  3:begin a=1;b={B_BITS{1'b1}};end
  endcase
  expected={{B_BITS{1'b0}},a}*{{A_BITS{1'b0}},b};
  if(i%31==0)begin
   launch();repeat(i%29+1)@(negedge clk);clear=1;@(negedge clk);clear=0;
   if(busy || done)$fatal(1,"clear");
   repeat(34)begin @(negedge clk);if(done)$fatal(1,"late done");end
  end
  launch();j=0;
  while(!done)begin
   @(negedge clk);j=j+1;
   // Busy start must not restart or replace operands.
   start=j==4;
   if(j>B_BITS+1)$fatal(1,"latency");
  end
  start=0;
  if(busy || product!==expected || j!=(HARD_MULTIPLY ? 1 : B_BITS))$fatal(1,"product %0d got %h expected %h cycles %0d",i,product,expected,j);
  @(negedge clk);if(done)$fatal(1,"done pulse");
 end
 $display("HAND_PRODUCT_SERIAL_PASS tests=2048");$finish;
end
endmodule
