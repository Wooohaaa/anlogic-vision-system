`timescale 1ns/1ps
`ifndef DUT_MODULE
`define DUT_MODULE ua_user_algo_96
`endif
module tb_cartoon_alignment_v84 #(parameter W=80,H=12,GAPS=1);
 localparam G=W/4;
 reg clk=0,rst=0,v=0,u=0,l=0;reg[95:0]rgb=0;wire ov,ou,ol;wire[95:0]out;
 always #5 clk=~clk;
 `DUT_MODULE #(.IMG_WIDTH(W),.IMG_HEIGHT(H))dut(clk,rst,l,u,rgb,v,3'd6,1'b1,ol,ou,out,ov,);
 integer pattern,x,y,k,gray,left,above,dx,dy,strength,hist1,hist2,n=0;
 reg[8:0]qv=0,qu=0,ql=0,qe=0;
 reg expected,next_expected;
 always @(posedge clk)if(rst)begin
  qv={qv[7:0],v};qu={qu[7:0],u};ql={ql[7:0],l};qe={qe[7:0],expected};
  #1;if({ov,ou,ol}!=={qv[8],qu[8],ql[8]})$fatal(1,"sideband");
  if(ov)begin
   n=n+1;
   if((out==0)!==qe[8])$fatal(1,"cartoon spatial mismatch x=%d y=%d got=%h",x,y,out);
  end
 end
 function integer sample(input integer p,xx,yy);
  begin
   case(p)
    0:sample=100;
    1:sample=xx<G/2?32:224;
    2:sample=yy<H/2?32:224;
    3:sample=(xx+yy<G/2)?32:224;
    default:sample=(xx>=G-2)?224:32;
   endcase
  end
 endfunction
 task idle(input integer count);
  integer i;begin for(i=0;i<count;i=i+1)begin @(negedge clk);v=0;u=0;l=0;end end
 endtask
 initial begin
  repeat(3)@(negedge clk);rst=1;idle(6);
  for(pattern=0;pattern<5;pattern=pattern+1)begin
   for(y=0;y<H;y=y+1)begin
    hist1=0;hist2=0;
    for(x=0;x<G;x=x+1)begin
     gray=sample(pattern,x,y);left=sample(pattern,x==0?0:x-1,y);above=sample(pattern,x,y==0?0:y-1);
     dx=gray-left;if(dx<0)dx=-dx;dy=gray-above;if(dy<0)dy=-dy;strength=(dx+dy)/2;
     next_expected=strength>=24 || (strength>=16 && x>0 && (hist1>=16 || (x>1 && hist2>=16)));
     @(negedge clk);v=1;u=(x==0 && y==0);l=(x==G-1);rgb={12{8'(gray)}};expected=next_expected;
     hist2=hist1;hist1=strength;
     if(GAPS && x%7==3)idle(2);
    end
    if(GAPS)idle(y%3);
   end
   idle(15);
  end
  idle(15);if(n!=5*G*H)$fatal(1,"sample count");
  $display("CARTOON_V84_ALIGNED_PASS W=%d H=%d gaps=%d groups=%d",W,H,GAPS,n);$finish;
 end
 initial begin #300000000;$fatal(1,"timeout");end
endmodule
