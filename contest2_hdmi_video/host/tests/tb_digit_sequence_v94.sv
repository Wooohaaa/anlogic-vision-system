`timescale 1ns/1ps
// Consecutive, distinct HDMI frames; no repetition of one still image.
module tb_digit_sequence_v94;
 parameter FRAMES=12;
 reg clk=0,rst=0,v=0,u=0,l=0;reg[95:0]data=0;
 always #5 clk=~clk;
 wire dv,ev;wire[3:0]id;wire[7:0]conf;wire[56:0]view;
 ua_digit_recognizer #(.AUTO_FIND(1))dut(clk,rst,l,u,data,v,dv,id,conf,ev,view);
 reg[95:0]pixels[0:230399];string folder,path;
 integer f,x,y,accepted=0,events=0,expected=15;
 always @(posedge clk)begin #1;if(ev)begin
  events=events+1;
  $display("SEQUENCE_RESULT frame=%0d valid=%0d id=%0d confidence=%0d",f,dv,id,conf);
  if(dv)begin
   accepted=accepted+1;
   if(id!=expected)$fatal(1,"SEQUENCE_WRONG_DIGIT expected=%0d id=%0d",expected,id);
  end
 end end
 initial begin
  if(!$value$plusargs("FOLDER=%s",folder))$fatal(1,"folder missing");
  if(!$value$plusargs("EXPECTED=%d",expected))$fatal(1,"label missing");
  repeat(4)@(negedge clk);rst=1;
  for(f=0;f<FRAMES;f=f+1)begin
   path=$sformatf("%s/%0d.hex",folder,f);$readmemh(path,pixels);
   for(y=0;y<720;y=y+1)for(x=0;x<320;x=x+1)begin
    @(negedge clk);v=1;u=x==0&&y==0;l=x==319;data=pixels[y*320+x];
   end
   @(negedge clk);v=0;u=0;l=0;repeat(600)@(negedge clk);
  end
  repeat(24000)@(negedge clk);
  if(accepted<3 || events<3)$fatal(1,"SEQUENCE_NO_STABLE_RECOGNITION accepted=%0d events=%0d",accepted,events);
  $display("DIGIT_SEQUENCE_V94_PASS expected=%0d accepted=%0d events=%0d",expected,accepted,events);$finish;
 end
endmodule
