`timescale 1ns/1ps
module tb_top_row_repair_v84r1 #(parameter W=80,H=8,GAPS=1);
 localparam G=W/4;
 reg clk=0,rst=0,v=0,u=0,l=0;reg[95:0]rgb=0;
 wire ov,ou,ol;wire[95:0]out;integer frames=0,count=0,x,y,f,xx,yy;
 always #5 clk=~clk;
 ua_top_row_repair_96 #(.IMG_WIDTH(W),.IMG_HEIGHT(H))dut(clk,rst,rgb,v,u,l,out,ov,ou,ol);
 function[95:0]color(input integer frame,row,col);
  begin color={32'(frame+1),32'(row*29+col*7+3),32'(row*19+col+10)};end
 endfunction
 always @(posedge clk)begin
  #1;if(ov)begin
   if(ou)begin if(count && count!=G*H)$fatal(1,"short frame");count=0;frames=frames+1;end
   xx=count%G;yy=count/G;
   if(ol!==(xx==G-1))$fatal(1,"EOL position");
   if(out!==color(frames-1,yy==0?1:yy,xx))$fatal(1,"row mismatch y=%d x=%d got=%h expected=%h",yy,xx,out,color(frames-1,yy==0?1:yy,xx));
   count=count+1;
  end
 end
 task idle(input integer n);integer i;begin for(i=0;i<n;i=i+1)begin @(negedge clk);v=0;u=0;l=0;end end endtask
 initial begin
  repeat(3)@(negedge clk);rst=1;
  // An incomplete first row followed by SOF must not leak stale RAM.
  @(negedge clk);v=1;u=1;l=0;rgb={4{24'hff0000}};
  idle(3);
  for(f=0;f<3;f=f+1)begin
   if(f==1)begin @(negedge clk);rst=0;idle(3);rst=1;end
   for(y=0;y<H;y=y+1)begin
    for(x=0;x<G;x=x+1)begin
     @(negedge clk);v=1;u=(x==0 && y==0);l=x==G-1;
     rgb=y==0?{4{24'hff0000}}:color(f,y,x);
     if(GAPS && x%7==3)idle(1+x%3);
    end
    if(GAPS)idle(y%5);
   end
   idle(2*G+5);if(count!=G*H)$fatal(1,"missing final flush %d",count);
  end
  if(frames!=3)$fatal(1,"frame count");
  $display("TOP_ROW_V84_REPAIR_PASS W=%d H=%d gaps=%d frames=%d",W,H,GAPS,frames);$finish;
 end
 initial begin #300000000;$fatal(1,"timeout");end
endmodule
