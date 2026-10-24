`timescale 1ns/1ps
module tb_digit_vector_v94;
 parameter W=320,H=240,FRAMES=8;
 reg clk=0,rst=0,v=0,u=0,l=0;reg[95:0]rgb=0;
 always #5 clk=~clk;
 wire dv,ev;wire[3:0]id;wire[7:0]conf;wire[56:0]view;
 ua_digit_recognizer #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.AUTO_FIND(1))dut(clk,rst,l,u,rgb,v,dv,id,conf,ev,view);
 reg[95:0]memory[0:W*H/4-1];reg[2047:0]path;
 integer expected=15,f,x,y,count=0;
 always @(posedge clk)begin #1;if(dv)begin
  if(expected==15 || id!=expected)$fatal(1,"VECTOR_WRONG expected=%0d actual=%0d bbox=%0d,%0d,%0d,%0d bits=%h",expected,id,dut.card_x0,dut.card_x1,dut.card_y0,dut.card_y1,dut.observed_bits);
  count=count+1;
 end end
 initial begin
  if(!$value$plusargs("INPUT=%s",path))$fatal(1,"input missing");
  if($value$plusargs("EXPECTED=%d",expected))begin end
  $readmemh(path,memory);repeat(4)@(negedge clk);rst=1;
  for(f=0;f<FRAMES;f=f+1)begin
   for(y=0;y<H;y=y+1)for(x=0;x<W/4;x=x+1)begin
    @(negedge clk);v=1;u=x==0&&y==0;l=x==W/4-1;rgb=memory[y*(W/4)+x];
    if(x%29==7)begin @(negedge clk);v=0;u=0;l=0;end
   end
   @(negedge clk);v=0;u=0;l=0;repeat(24000)@(negedge clk);
  end
  if(expected!=15 && count==0)$fatal(1,"VECTOR_NO_RESULT expected=%0d card=%b box=%0d,%0d,%0d,%0d bits=%h best=%0d second=%0d",expected,dut.card_found,dut.card_x0,dut.card_x1,dut.card_y0,dut.card_y1,dut.observed_bits,dut.result_best_distance,dut.result_second_distance);
  $display("DIGIT_VECTOR_V94_PASS expected=%0d results=%0d",expected,count);$finish;
 end
endmodule
