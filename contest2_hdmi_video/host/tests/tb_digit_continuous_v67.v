`timescale 1ns/1ps
module tb_digit_continuous_v67;
 localparam W=384,H=464;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,v=0,u=0,l=0;reg [95:0] pixels=0;
 wire valid;wire [3:0] id;wire [7:0] conf;
 ua_digit_recognizer #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.OUTER_X0(24),.OUTER_Y0(40),
 .OUTER_W(288),.OUTER_H(384),.INNER_X0(48),.INNER_Y0(64),.INNER_W(240),.INNER_H(336),
 .CELL_W(48),.CELL_H(48),.CELL_MIN(72)) dut(clk,rst,l,u,pixels,v,valid,id,conf,,);
 reg [95:0] image[0:W*H/4-1];string prefix,path;
 integer f,x,y,valid_count=0;
 always @(posedge clk)begin
  #1;
  if(rst && valid)begin
   if(f>=30 || id!=8)$fatal(1,"CONTINUOUS_WRONG frame=%0d id=%0d",f,id);
   valid_count=valid_count+1;
  end
 end
 initial begin
  if(!$value$plusargs("PREFIX=%s",prefix))$fatal(1,"PREFIX missing");
  repeat(3)@(negedge clk);rst=1;
  for(f=0;f<34;f=f+1)begin
   if(f<30)begin path=$sformatf("%0s_%0d.hex",prefix,400+f);$readmemh(path,image);end
   for(y=0;y<H;y=y+1)for(x=0;x<W/4;x=x+1)begin
    @(negedge clk);v=1;u=(x==0&&y==0);l=(x==W/4-1);
    pixels=(f<30)?image[y*(W/4)+x]:{12{8'd220}};
    if((x+y+f)%83==0)begin @(negedge clk);v=0;u=0;l=0;end
   end
   @(negedge clk);v=0;u=0;l=0;repeat(400)@(negedge clk);
  end
  if(valid_count<5 || id!=15)$fatal(1,"CONTINUOUS_NO_STABILITY count=%0d id=%0d",valid_count,id);
  $display("DIGIT_CONTINUOUS_V67_PASS frames=30 blank_frames=4 valid8=%0d",valid_count);$finish;
 end
endmodule
