`timescale 1ns/1ps
module tb_dark_edge_effect_v88;
localparam W=160,H=24,G=W/4;
reg clk=0;always #5 clk=~clk;
reg rst=0,v=0,u=0,l=0;reg[95:0]rgb=0;reg[2:0]mode=6;
wire ov0,ov1,ou0,ou1,ol0,ol1;wire[95:0]a,b;
ua_user_algo_96 #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.DARK_EDGE_ENABLE(0)) old_dut(clk,rst,l,u,rgb,v,mode,1'b1,ol0,ou0,a,ov0,);
ua_user_algo_96 #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.DARK_EDGE_ENABLE(1)) new_dut(clk,rst,l,u,rgb,v,mode,1'b1,ol1,ou1,b,ov1,);
integer pattern,x,y,m,c,n0=0,n1=0,compared=0;reg[23:0]pixel;
always @(posedge clk)if(rst)begin
 #1;if({ov0,ou0,ol0}!=={ov1,ou1,ol1})$fatal(1,"latency/sidebands changed");
 if(ov0)begin
  compared=compared+1;
  if(pattern==0)begin if(a==0)n0=n0+1;if(b==0)n1=n1+1;end
  else if(a!==b)$fatal(1,"bright/noise/colour regression mode=%d pattern=%d",mode,pattern);
 end
end
task idle;
 integer i;begin for(i=0;i<16;i=i+1)begin @(negedge clk);v=0;u=0;l=0;end end
endtask
task frame;
 begin
 for(y=0;y<H;y=y+1)begin
  for(x=0;x<G;x=x+1)begin
   if(pattern==0)c=(x<G/2)?16:40; // raw contour=12: missed before, strong=24 now
   else if(pattern==1)c=24+((x*17+y*13)%3)-1; // small dark flicker, no new outlines
   else c=(x<G/2)?96:160; // bright contours unchanged
   pixel={3{8'(c)}};
   if(pattern==3)pixel={8'(x*17+y*23),8'(x*33+y*7),8'(x*9+y*41)};
   @(negedge clk);v=1;u=(x==0 && y==0);l=(x==G-1);rgb={4{pixel}};
  end
  @(negedge clk);v=0;u=0;l=0;
 end
 idle;
 end
endtask
initial begin
 repeat(4)@(negedge clk);rst=1;idle;
 pattern=0;frame;
 if(n0!=0 || n1!=H)$fatal(1,"dark contour not recovered at the correct column old=%d new=%d",n0,n1);
 pattern=1;frame;pattern=2;frame;
 pattern=3;
 for(m=0;m<=5;m=m+1)if(m==0 || m==1 || m==3 || m==5)begin mode=m;idle;frame;end
 $display("DARK_EDGE_EFFECT_V88_PASS old_contours=%d new_contours=%d compared=%d",n0,n1,compared);$finish;
end
endmodule
