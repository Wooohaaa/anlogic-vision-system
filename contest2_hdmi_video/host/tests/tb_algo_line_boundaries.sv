`timescale 1ns/1ps
`ifndef DUT_MODULE
`define DUT_MODULE ua_user_algo_96
`endif
module tb_algo_line_boundaries #(
 parameter integer WIDTH=80,HEIGHT=12,GAPS=1,FIRST_MODE=0,LAST_MODE=6,PATTERNS=4
);
 localparam G=WIDTH/4;
 reg clk=0,rst=0,valid=0,sof=0,eol=0;reg [95:0] data=0;
 reg [2:0] mode=0;wire ov,ou,ol,ready;wire [95:0] out;
 always #5 clk=~clk;
 `DUT_MODULE #(.IMG_WIDTH(WIDTH),.IMG_HEIGHT(HEIGHT)) dut(
  .I_clk(clk),.I_rst_n(rst),.I_tlast(eol),.I_tuser(sof),.I_tdata(data),
  .I_tvalid(valid),.I_mode(mode),.I_tready(1'b1),.O_tlast(ol),.O_tuser(ou),
  .O_tdata(out),.O_tvalid(ov),.O_tready(ready));
 integer image[0:G*HEIGHT-1],smooth[0:G*HEIGHT-1];
 reg [95:0] expected=0,queue[0:8];reg ev[0:8],eu[0:8],el[0:8],ec[0:8];
 reg cart=0;integer coord_x=0,coord_y=0,qx[0:8],qy[0:8];
 integer checked=0,errors=0,left_errors=0,right_errors=0,cycles=0,j;
 function integer sample(input integer y,x);
  integer xx,yy;
  begin xx=x<0?0:x;yy=y<0?0:y;sample=smooth[yy*G+xx];end
 endfunction
 always @(posedge clk)begin
  if(!rst)begin
   for(j=0;j<9;j=j+1)begin queue[j]=0;ev[j]=0;eu[j]=0;el[j]=0;ec[j]=0;qx[j]=0;qy[j]=0;end
  end else begin
   for(j=8;j>0;j=j-1)begin queue[j]=queue[j-1];ev[j]=ev[j-1];eu[j]=eu[j-1];el[j]=el[j-1];ec[j]=ec[j-1];qx[j]=qx[j-1];qy[j]=qy[j-1];end
   queue[0]=expected;ev[0]=valid;eu[0]=sof;el[0]=eol;ec[0]=cart;qx[0]=coord_x;qy[0]=coord_y;
   #1;cycles=cycles+1;
   if(ov!==ev[8] || ou!==eu[8] || ol!==el[8])$fatal(1,"fixed 8-clock sideband mismatch cycle=%0d",cycles);
   if(ov)begin
    checked=checked+1;
    if(ec[8] ? ((out==0)!=(queue[8]==0)) : out!==queue[8])begin
     errors=errors+1;if(qx[8]<6)left_errors=left_errors+1;if(qx[8]>=G-6)right_errors=right_errors+1;
     if(errors<=12)$display("PIXEL_MISMATCH mode=%0d pattern=%0d xgrp=%0d y=%0d got=%h want=%h",mode,p,qx[8],qy[8],out,queue[8]);
    end
   end
  end
 end
 task idle(input integer n);
  integer k;begin for(k=0;k<n;k=k+1)begin @(negedge clk);valid=0;sof=0;eol=0;end end
 endtask
 integer m,p,x,y,k,s,dx,dy,value,emb,prev1,prev2,v0,v1,v2;
 initial begin
  repeat(4)@(negedge clk);rst=1;
  for(m=FIRST_MODE;m<=LAST_MODE;m=m+1)begin
   idle(12);mode=m;idle(4);
   for(p=0;p<PATTERNS;p=p+1)begin
    for(y=0;y<HEIGHT;y=y+1)for(x=0;x<G;x=x+1)begin
     case(p)
      0:image[y*G+x]=128;
      1:image[y*G+x]=(x*73+y*29+(x/5)*41)&255;
      2:image[y*G+x]=x>=G-5?(((x+y)&1)?230:12):100;
      default:image[y*G+x]=(x<5)?(x*35+y*11)&255:(y*17+40)&255;
     endcase
     v0=image[y*G+x];v1=image[y*G+(x>0?x-1:0)];v2=image[y*G+(x>1?x-2:0)];
     smooth[y*G+x]=(v0+2*v1+v2)/4;
    end
    for(y=0;y<HEIGHT;y=y+1)begin
     prev1=0;prev2=0;
     for(x=0;x<G;x=x+1)begin
      dx=-sample(y-2,x-2)+sample(y-2,x)-2*sample(y-1,x-2)+2*sample(y-1,x)-sample(y,x-2)+sample(y,x);
      dy=sample(y-2,x-2)+2*sample(y-2,x-1)+sample(y-2,x)-sample(y,x-2)-2*sample(y,x-1)-sample(y,x);
      s=((dx<0?-dx:dx)+(dy<0?-dy:dy))/8;
      emb=sample(y,x)-sample(y-2,x-2)+128;if(emb<0)emb=0;if(emb>255)emb=255;
      case(m)
       2:value=s;
       3:value=(sample(y,x)>128)?255:0;
       4:value=255-s;
       5:value=emb;
       6:value=(s>=24 || (s>=16 && x>0 && (prev1>=16 || (x>1 && prev2>=16))))?0:1;
       default:value=image[y*G+x];
      endcase
      @(negedge clk);valid=1;sof=(x==0 && y==0);eol=(x==G-1);
      data={12{8'(image[y*G+x])}};expected={12{8'(value)}};cart=(m==6);coord_x=x;coord_y=y;
      prev2=prev1;prev1=s;
      if(GAPS && x%7==3)idle(1+(x%3));
     end
     if(GAPS)idle(y%6);
    end
    idle(12);
   end
  end
  idle(12);
  if(errors)$fatal(1,"ALGO_BOUNDARY_FAIL errors=%0d left=%0d right=%0d checked=%0d",errors,left_errors,right_errors,checked);
  $display("ALGO_BOUNDARY_PASS width=%0d height=%0d gaps=%0d modes=%0d..%0d patterns=%0d checked=%0d fixed_latency=8",WIDTH,HEIGHT,GAPS,FIRST_MODE,LAST_MODE,PATTERNS,checked);$finish;
 end
 initial begin #300000000;$fatal(1,"watchdog");end
endmodule
