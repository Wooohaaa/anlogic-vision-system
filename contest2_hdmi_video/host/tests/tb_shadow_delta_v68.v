`timescale 1ns/1ps
// Production narrow-difference kernel versus full-precision weighted reference.
module tb_shadow_delta_v68;
 parameter BITS=9;
 localparam P=3*BITS;
 wire ov,ou,ol; wire [95:0] od;
 ua_photo_finish_96 #(.INPUT_BITS(BITS),.SHADOW_COLOR_DENOISE(1)) dut(1'b0,1'b0,1'b0,1'b0,1'b0,{12*BITS{1'b0}},2'b0,ov,ou,ol,od);
 function [P-1:0] delta_kernel;
  input [P-1:0] r,a,b,c,d,e;
  reg signed [5:0] da,db,dc,dd,de;
  reg signed [8:0] sum_delta;
  reg signed [9:0] rounded;
  reg signed [BITS+2:0] result;
  reg ga,gb,gc,gd,ge;
  integer ch;
  begin
   ga=dut.similar(r,a);gb=dut.similar(r,b);gc=dut.similar(r,c);
   gd=dut.similar(r,d);ge=dut.similar(r,e);
   for(ch=0;ch<3;ch=ch+1) begin
    da=ga ? r[ch*BITS+:BITS]-a[ch*BITS+:BITS] : 6'sd0;
    db=gb ? r[ch*BITS+:BITS]-b[ch*BITS+:BITS] : 6'sd0;
    dc=gc ? r[ch*BITS+:BITS]-c[ch*BITS+:BITS] : 6'sd0;
    dd=gd ? r[ch*BITS+:BITS]-d[ch*BITS+:BITS] : 6'sd0;
    de=ge ? r[ch*BITS+:BITS]-e[ch*BITS+:BITS] : 6'sd0;
    sum_delta={{3{da[5]}},da}+{{2{db[5]}},db,1'b0}+
              {{2{dc[5]}},dc,1'b0}+{{2{dd[5]}},dd,1'b0}+{{3{de[5]}},de};
    rounded=10'sd4-$signed({sum_delta[8],sum_delta});
    result=$signed({1'b0,r[ch*BITS+:BITS]})+(rounded>>>3);
    delta_kernel[ch*BITS+:BITS]=result[BITS-1:0];
   end
  end
 endfunction
 function [P-1:0] weighted_reference;
  input [P-1:0] r,a,b,c,d,e;
  integer ch,sum;
  reg [P-1:0] aa,bb,cc,dd,ee;
  begin
   aa=dut.similar(r,a)?a:r;bb=dut.similar(r,b)?b:r;
   cc=dut.similar(r,c)?c:r;dd=dut.similar(r,d)?d:r;ee=dut.similar(r,e)?e:r;
   for(ch=0;ch<3;ch=ch+1)begin
    sum=aa[ch*BITS+:BITS]+2*bb[ch*BITS+:BITS]+2*cc[ch*BITS+:BITS]+2*dd[ch*BITS+:BITS]+ee[ch*BITS+:BITS];
    weighted_reference[ch*BITS+:BITS]=(sum+4)/8;
   end
  end
 endfunction
 reg [P-1:0] r,a,b,c,d,e;
 integer seed=10415,i,ch,k,value;
 reg [P-1:0] n[0:4];
 initial begin
  for(i=0;i<100000;i=i+1) begin
   for(ch=0;ch<3;ch=ch+1) begin
    if(i<1000)r[ch*BITS+:BITS]=i%((1<<BITS));
    else r[ch*BITS+:BITS]=$random(seed);
    for(k=0;k<5;k=k+1) begin
     value=r[ch*BITS+:BITS]+($unsigned($random(seed))%65)-32;
     if(value<0)value=0;
     if(value>=(1<<BITS))value=(1<<BITS)-1;
     n[k][ch*BITS+:BITS]=value;
    end
   end
   a=n[0];b=n[1];c=n[2];d=n[3];e=n[4];
   if(i%3==0)a=r;
   if(i%3==1)c=r;
   if(delta_kernel(r,a,b,c,d,e)!==dut.range5(r,a,b,c,d,e))
    $fatal(1,"delta kernel mismatch bits=%d case=%d",BITS,i);
   if(weighted_reference(r,a,b,c,d,e)!==dut.range5(r,a,b,c,d,e))
    $fatal(1,"weighted reference mismatch bits=%d case=%d",BITS,i);
  end
  $display("FINITE5_DELTA_EQUIVALENCE_PASS bits=%d cases=100000 rounding gate overflow",BITS);
  $finish;
 end
endmodule
