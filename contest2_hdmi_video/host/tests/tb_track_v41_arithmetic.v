`timescale 1ns/1ps
module tb_track_v41_arithmetic;
 reg clk=0,rst=0;always #5 clk=~clk;
 ua_track_detect dut(.I_clk(clk),.I_rst_n(rst),.I_tvalid(1'b0),.I_tready(1'b1));
 track_v40_reference ref_dut(.I_clk(clk),.I_rst_n(rst),.I_tvalid(1'b0),.I_tready(1'b1));
 reg [19:0] a;reg [23:0] b;reg [27:0] c;
 reg [30:0] box0,box45,box22;
 reg [11:0] wp,du,dv;reg [9:0] h;reg [13:0] dp,dq;
 reg [17:0] area;integer i,seed=414141;
 initial begin
  repeat(4)@(negedge clk);rst=1;
  force dut.fe_d=9'b000011100;force ref_dut.fe_d=9'b000011100;
  force dut.c_ba0=a;force dut.c_ba1=a;force dut.c_ba2=a;
  force ref_dut.c_ba0=a;force ref_dut.c_ba1=a;force ref_dut.c_ba2=a;
  force dut.c_box450=b;force dut.c_box451=b;force dut.c_box452=b;
  force ref_dut.c_box450=b;force ref_dut.c_box451=b;force ref_dut.c_box452=b;
  force dut.c_box220=c;force dut.c_box221=c;force dut.c_box222=c;
  force ref_dut.c_box220=c;force ref_dut.c_box221=c;force ref_dut.c_box222=c;
  for(i=0;i<4096;i=i+1)begin
   @(negedge clk);a=$random(seed);b=$random(seed);c=$random(seed);
   if(i==0)begin a=0;b=0;c=0;end
   if(i==1)begin a=20'hfffff;b=24'hffffff;c=28'hfffffff;end
   if(i==2)begin a=20'h80000;b=24'h800000;c=28'h8000000;end
   @(posedge clk);#1;
   if(dut.c_bs00!==ref_dut.c_bs00 || dut.c_bs01!==ref_dut.c_bs01 || dut.c_bs02!==ref_dut.c_bs02 ||
      dut.c_bs450!==ref_dut.c_bs450 || dut.c_bs451!==ref_dut.c_bs451 || dut.c_bs452!==ref_dut.c_bs452 ||
      dut.c_bs220!==ref_dut.c_bs220 || dut.c_bs221!==ref_dut.c_bs221 || dut.c_bs222!==ref_dut.c_bs222)
    $fatal(1,"normalization boundary/random mismatch %0d",i);
  end
  for(i=0;i<100000;i=i+1)begin
   box0=$random(seed);box45=$random(seed);box22=$random(seed);
   wp=$random(seed);du=$random(seed);dv=$random(seed);h=$random(seed);
   dp=$random(seed);dq=$random(seed);area=$random(seed);
   if(i==0)begin box0=0;box45=0;box22=0;area=0;end
   if(i==1)begin box0=31'h7fffffff;box45=31'h7fffffff;box22=31'h7fffffff;area=18'h3ffff;end
   if(dut.classify_rot(box0,box45,box22,wp,du,dv,h,dp,dq,area,1'b1)!==
      ref_dut.classify_rot(box0,box45,box22,wp,du,dv,h,dp,dq,area,1'b1))
    $fatal(1,"shape function mismatch %0d",i);
   if(dut.F_elongated(dp,dq)!==ref_dut.F_elongated(dp,dq))$fatal(1,"ratio mismatch");
  end
  $display("TRACK_V41_ARITHMETIC_PASS normalized=4096 random_classifiers=100000 all_ones_zero_boundaries");$finish;
 end
endmodule
