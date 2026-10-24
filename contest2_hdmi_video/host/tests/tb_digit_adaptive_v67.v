`timescale 1ns/1ps
module tb_digit_adaptive_v67;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,v=0,u=0,l=0;reg [95:0] pixels=0;
 wire valid;wire [3:0] id;wire [7:0] conf;
 ua_digit_recognizer #(.IMG_WIDTH(192),.IMG_HEIGHT(160),
 .OUTER_X0(32),.OUTER_Y0(16),.OUTER_W(128),.OUTER_H(128)) dut(clk,rst,l,u,pixels,v,valid,id,conf,,);
 integer d,f,x,y,lane,px,grey,col,row,valid_count,shift_x,shift_y,mode;
 reg [34:0] pattern;
 always @(posedge clk)begin
  #1;
  if(rst && valid)begin
   if(id!=d)$fatal(1,"ADAPTIVE_WRONG expected=%0d got=%0d mode=%0d bits=%h",d,id,mode,dut.observed_bits);
   valid_count=valid_count+1;
  end
 end
 initial begin
  for(mode=0;mode<2;mode=mode+1)for(d=0;d<10;d=d+1)begin
   @(negedge clk);rst=0;v=0;u=0;l=0;repeat(3)@(negedge clk);rst=1;valid_count=0;
   pattern=dut.F_template(d);shift_x=(mode==0)?48:68;shift_y=(mode==0)?32:48;
   for(f=0;f<6;f=f+1)begin
    for(y=0;y<160;y=y+1)for(x=0;x<48;x=x+1)begin
     @(negedge clk);v=1;u=(x==0&&y==0);l=(x==47);
     for(lane=0;lane<4;lane=lane+1)begin
      px=x*4+lane;grey=(mode==0)?220:112;
      if(px>=shift_x && px<shift_x+60 && y>=shift_y && y<shift_y+84)begin
       col=(px-shift_x)/12;row=(y-shift_y)/12;
       if(pattern[34-row*5-col])grey=(mode==0)?24:40;
      end
      grey=grey+((px+y+f)%7)-3;pixels[95-lane*24-:24]={grey[7:0],grey[7:0],grey[7:0]};
     end
    end
    @(negedge clk);v=0;u=0;l=0;repeat(400)@(negedge clk);
   end
   if(valid_count==0)$fatal(1,"ADAPTIVE_NO_RESULT digit=%0d mode=%0d bits=%h geom=%0d,%0d step=%0d,%0d gate=%0d",d,mode,dut.observed_bits,dut.norm_x0,dut.norm_y0,dut.step_x,dut.step_y,dut.occupancy_gate);
   $display("ADAPTIVE_DIGIT_PASS digit=%0d mode=%0d valid=%0d",d,mode,valid_count);
  end
  $display("DIGIT_ADAPTIVE_V67_PASS");$finish;
 end
endmodule
