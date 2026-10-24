`timescale 1ns/1ps
module tb_digit_video_v67;
 localparam W=384,H=464;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,v=0,u=0,l=0;reg [95:0] pixels=0;
 wire valid;wire [3:0] id;wire [7:0] confidence;
 ua_digit_recognizer #(.IMG_WIDTH(W),.IMG_HEIGHT(H),
  .OUTER_X0(24),.OUTER_Y0(40),.OUTER_W(288),.OUTER_H(384),
  .INNER_X0(48),.INNER_Y0(64),.INNER_W(240),.INNER_H(336),
  .CELL_W(48),.CELL_H(48),.CELL_MIN(72)) dut(clk,rst,l,u,pixels,v,valid,id,confidence,,);
 wire old_valid;wire [3:0] old_id;wire [7:0] old_conf;
 ua_digit_snapshot_reference #(.IMG_WIDTH(W),.IMG_HEIGHT(H),
  .OUTER_X0(24),.OUTER_Y0(40),.OUTER_W(288),.OUTER_H(384),
  .INNER_X0(48),.INNER_Y0(64),.INNER_W(240),.INNER_H(336),
  .CELL_W(48),.CELL_H(48),.CELL_MIN(72)) old_dut(clk,rst,l,u,pixels,v,old_valid,old_id,old_conf);
 reg [95:0] image[0:W*H/4-1];reg [2047:0] path;
 integer f,x,y,expected=8,valid_count=0,old_correct=0;
 always @(posedge clk)begin
  #1;
  if(rst && valid)begin
   if(id!=expected)$fatal(1,"VIDEO_WRONG_DIGIT expected=%0d actual=%0d",expected,id);
   valid_count=valid_count+1;
  end
  if(rst && old_valid && old_id==expected)old_correct=old_correct+1;
 end
 initial begin
  if(!$value$plusargs("INPUT=%s",path))$fatal(1,"INPUT missing");
  if($value$plusargs("EXPECTED=%d",expected))begin end
  $readmemh(path,image);
  repeat(3)@(negedge clk);rst=1;
  for(f=0;f<6;f=f+1)begin
   for(y=0;y<H;y=y+1)for(x=0;x<W/4;x=x+1)begin
    @(negedge clk);v=1;u=(x==0&&y==0);l=(x==W/4-1);pixels=image[y*(W/4)+x];
    if((x+y)%179==0)begin @(negedge clk);v=0;u=0;l=0;end
   end
   @(negedge clk);v=0;u=0;l=0;repeat(400)@(negedge clk);
  end
  if(expected!=15 && valid_count==0)$fatal(1,"VIDEO_NO_RESULT observed=%h bbox=%0d,%0d step=%0d,%0d bg=%0d gate=%0d",dut.observed_bits,dut.norm_x0,dut.norm_y0,dut.step_x,dut.step_y,dut.bg_luma,dut.occupancy_gate);
  if(expected==15 && valid_count!=0)$fatal(1,"VIDEO_CLIPPED_ACCEPTED");
  $display("DIGIT_VIDEO_V67_PASS expected=%0d correct=%0d old_correct=%0d",expected,valid_count,old_correct);$finish;
 end
endmodule
