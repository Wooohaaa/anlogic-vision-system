`timescale 1ns/1ps
module tb_digit_v66;
`ifdef PRODUCT_GEOMETRY
 localparam W=1280,H=720,X=520,Y=192,CW=48,CH=48,OX=496,OY=168,OW=288,OH=384;
`else
 localparam W=160,H=128,X=28,Y=20,CW=20,CH=12,OX=8,OY=4,OW=144,OH=120;
`endif
 localparam SAMPLES=CW*((CH+3)/4), GATE=SAMPLES/8;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,v=0,u=0,l=0;reg [95:0] pixels=0;
 wire valid;wire [3:0] id;wire [7:0] confidence;
 ua_digit_recognizer #(.IMG_WIDTH(W),.IMG_HEIGHT(H),
 .OUTER_X0(OX),.OUTER_Y0(OY),.OUTER_W(OW),.OUTER_H(OH),
 .INNER_X0(X),.INNER_Y0(Y),.INNER_W(CW*5),.INNER_H(CH*7),
 .CELL_W(CW),.CELL_H(CH),.ADAPTIVE_ROI(0)) dut(clk,rst,l,u,pixels,v,valid,id,confidence,,);
 wire old_valid;wire [3:0] old_id;wire [7:0] old_confidence;
 // Same geometry, old ~4% occupancy isolates the classification change.
 ua_digit_recognizer #(.IMG_WIDTH(W),.IMG_HEIGHT(H),
 .OUTER_X0(OX),.OUTER_Y0(OY),.OUTER_W(OW),.OUTER_H(OH),
 .INNER_X0(X),.INNER_Y0(Y),.INNER_W(CW*5),.INNER_H(CH*7),
 .CELL_W(CW),.CELL_H(CH),.CELL_MIN(SAMPLES/24),.ADAPTIVE_ROI(0)) old_gate(
 clk,rst,l,u,pixels,v,old_valid,old_id,old_confidence,,);
 integer px,py,lane,x,grey,cx,cy,lx,ly,frame,valid_count,old_count,d,mode;
 reg [34:0] pattern;reg [3:0] expected;
 always @(posedge clk) begin
  #1;
  if(rst && valid)begin
   if(id!==expected)$fatal(1,"Wrong digit expected=%0d actual=%0d mode=%0d",expected,id,mode);
   valid_count=valid_count+1;
  end
  if(rst && old_valid && old_id==expected) old_count=old_count+1;
 end
 task run_case;
 input integer number,kind;
 begin
  rst=0;v=0;u=0;l=0;repeat(3)@(negedge clk);
  rst=1;valid_count=0;old_count=0;expected=number;mode=kind;
  pattern=(kind==3)?35'd0:(kind==4)?35'h7ffffffff:dut.F_template(number);
  for(frame=0;frame<5;frame=frame+1)begin
   for(py=0;py<H;py=py+1)for(x=0;x<W/4;x=x+1)begin
    @(negedge clk);v=1;u=(x==0 && py==0);l=(x==W/4-1);
    for(lane=0;lane<4;lane=lane+1)begin
     px=x*4+lane;grey=(kind==2)?110:220;
     if(px>=X && px<X+CW*5 && py>=Y && py<Y+CH*7)begin
      cx=(px-X)/CW;cy=(py-Y)/CH;lx=(px-X)%CW;ly=(py-Y)%CH;
      // Sparse central stroke (25% width), not solid template tiles.
      if(pattern[34-(cy*5+cx)] && lx>=CW/4 && lx<CW/2)grey=(kind==2)?50:24;
      // Narrow fringe in EMPTY tiles: enough to break old gate, below 1/8.
      if(kind==1 && lx<CW/12+1)grey=24;
     end
     grey=grey+((px+py+frame)%7)-3;
     pixels[95-lane*24-:24]={grey[7:0],grey[7:0],grey[7:0]};
    end
    if((x+py)%71==0)begin @(negedge clk);v=0;u=0;l=0;end
   end
   @(negedge clk);v=0;u=0;l=0;repeat(380)@(negedge clk);
  end
  if(kind<3 && valid_count==0)$fatal(1,"No stable digit %0d mode=%0d observed=%h",number,kind,dut.observed_bits);
  if(kind>=3 && valid_count!=0)$fatal(1,"Blank/solid falsely accepted");
  if(kind==1 && old_count!=0)$fatal(1,"Noise fixture did not reproduce old hole-fill failure");
  $display("DIGIT_CASE_PASS digit=%0d mode=%0d valid=%0d old_correct=%0d gate=%0d",number,kind,valid_count,old_count,GATE);
 end endtask
 initial begin
`ifdef PRODUCT_GEOMETRY
  run_case(8,1);
`else
  for(d=0;d<10;d=d+1)run_case(d,0);
  run_case(8,1);run_case(8,2);run_case(15,3);run_case(15,4);
`endif
  $display("DIGIT_V66_PASS");$finish;
 end
endmodule
