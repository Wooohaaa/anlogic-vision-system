`timescale 1ns/1ps
module tb_digit_snapshot_equivalence;
 parameter THRESHOLD=32;
 parameter FRAMES=68;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,v=0,u=0,l=0;reg [95:0] pixels=0;
 wire av,bv;wire [3:0] ai,bi;wire [7:0] ac,bc;
 ua_digit_recognizer #(.IMG_WIDTH(160),.IMG_HEIGHT(128),
 .OUTER_X0(8),.OUTER_Y0(8),.OUTER_W(144),.OUTER_H(112),
 .INNER_X0(24),.INNER_Y0(24),.INNER_W(100),.INNER_H(70),
 .CELL_W(20),.CELL_H(10),.CELL_MIN(THRESHOLD),.ADAPTIVE_ROI(0)) candidate(clk,rst,l,u,pixels,v,av,ai,ac,,);
 ua_digit_snapshot_reference #(.IMG_WIDTH(160),.IMG_HEIGHT(128),
 .OUTER_X0(8),.OUTER_Y0(8),.OUTER_W(144),.OUTER_H(112),
 .INNER_X0(24),.INNER_Y0(24),.INNER_W(100),.INNER_H(70),
 .CELL_W(20),.CELL_H(10),.CELL_MIN(THRESHOLD)) reference_dut(clk,rst,l,u,pixels,v,bv,bi,bc);
 integer frame,x,y,lane,px,cell_x,cell_y,seed=10415,grey,i,valid_results=0;
 reg [34:0] pattern;
 always @(posedge clk) begin
  #1;
  if(rst && {av,ai,ac}!=={bv,bi,bc})
   $fatal(1,"DIGIT_SNAPSHOT_MISMATCH frame=%0d xy=%0d,%0d",frame,x,y);
  if(rst && candidate.observed_bits!==reference_dut.observed_bits)
   $fatal(1,"DIGIT_FEATURE_MISMATCH frame=%0d xy=%0d,%0d",frame,x,y);
  if(rst && av) valid_results=valid_results+1;
 end
 initial begin
  repeat(3) @(negedge clk);rst=1;
  for(frame=0;frame<FRAMES;frame=frame+1)begin
   pattern=reference_dut.F_template((frame%60)/6);
   if(frame>=60) pattern=(frame[0]) ? 35'h7ffffffff : 35'd0;
   for(y=0;y<128;y=y+1) for(x=0;x<40;x=x+1) begin
    @(negedge clk);v=1;u=(x==0 && y==0);l=(x==39);
    for(lane=0;lane<4;lane=lane+1)begin
     px=x*4+lane;grey=220;
     if(px>=24 && px<124 && y>=24 && y<94)begin
      cell_x=(px-24)/20;cell_y=(y-24)/10;
      if(pattern[34-(cell_y*5+cell_x)])grey=24;
     end
     // Deterministic intensity noise and irregular stream bubbles.
     grey=grey+($unsigned($random(seed))%17)-8;
     pixels[95-lane*24-:24]={grey[7:0],grey[7:0],grey[7:0]};
    end
    if((x+3*y+frame)%29==0)begin
     @(negedge clk);v=0;u=0;l=0;
    end
   end
   @(negedge clk);v=0;u=0;l=0;
   repeat(400) @(negedge clk);
  end
  if(THRESHOLD==32 && FRAMES>=60 && valid_results<10)
    $fatal(1,"Insufficient valid digit results: %0d",valid_results);
  // Reset after the raster must clear both paths equally.
  rst=0;repeat(2) @(negedge clk);rst=1;
  repeat(10) @(negedge clk);
  $display("DIGIT_SNAPSHOT_EQUIVALENCE_PASS frames=%0d threshold=%0d valid_results=%0d",FRAMES,THRESHOLD,valid_results);
  $finish;
 end
endmodule
