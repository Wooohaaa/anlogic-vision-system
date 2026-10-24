`timescale 1ns/1ps
module tb_digit_real_v94;
 parameter FRAMES=8;
 reg clk=0,rst=0,v=0,u=0,l=0;reg[95:0]data=0;
 always #5 clk=~clk;
 wire dv,ev;wire[3:0]id;wire[7:0]conf;wire[56:0]view;
 ua_digit_recognizer #(.AUTO_FIND(1))dut(clk,rst,l,u,data,v,dv,id,conf,ev,view);
 reg[95:0]pixels[0:230399];reg[2047:0]path;
 integer f,x,y,accepted=0,expected=15;
 always @(posedge clk)begin #1;if(ev)begin
  $display("REAL_RESULT frame=%0d valid=%0d id=%0d conf=%0d card=%0d box=%0d,%0d,%0d,%0d bg=%0d fg=%0d geometry=%0d snap=%0d bits=%h distance=%0d second=%0d",f,dv,id,conf,dut.card_found,
   dut.card_x0,dut.card_x1,dut.card_y0,dut.card_y1,dut.bg_luma,dut.fg_seen,dut.geometry_ready,dut.snapshot_geometry_good,dut.observed_bits,dut.result_best_distance,dut.result_second_distance);
  if(dv)begin accepted=accepted+1;if(expected!=15 && id!=expected)$fatal(1,"REAL_WRONG_DIGIT");end
 end end
 initial begin
  if(!$value$plusargs("INPUT=%s",path))$fatal(1,"input missing");
  if($value$plusargs("EXPECTED=%d",expected))begin end
  $readmemh(path,pixels);repeat(4)@(negedge clk);rst=1;
  for(f=0;f<FRAMES;f=f+1)begin
   for(y=0;y<720;y=y+1)for(x=0;x<320;x=x+1)begin
    @(negedge clk);v=1;u=x==0&&y==0;l=x==319;data=pixels[y*320+x];
   end
   @(negedge clk);v=0;u=0;l=0;repeat(600)@(negedge clk);
  end
  if(expected!=15 && accepted==0)$fatal(1,"REAL_NO_RECOGNITION");
  $display("REAL_REPLAY_DONE accepted=%0d",accepted);$finish;
 end
endmodule
