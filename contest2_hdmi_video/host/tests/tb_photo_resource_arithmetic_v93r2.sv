`timescale 1ns/1ps
module tb_photo_resource_arithmetic_v93r2;
 ua_photo_finish_96 #(.INPUT_BITS(9),.SHADOW_COLOR_DENOISE(1),.SELECTIVE_SHADOW_BOOST(1)) dut(
 .I_clk(1'b0),.I_rst_n(1'b0),.I_tvalid(1'b0),.I_tuser(1'b0),.I_tlast(1'b0),.I_tdata(108'd0),.I_strength(2'd0));
 ua_photo_finish_v93_reference #(.INPUT_BITS(9),.SHADOW_COLOR_DENOISE(1),.SELECTIVE_SHADOW_BOOST(1)) ref_dut(
 .I_clk(1'b0),.I_rst_n(1'b0),.I_tvalid(1'b0),.I_tuser(1'b0),.I_tlast(1'b0),.I_tdata(108'd0),.I_strength(2'd0));
 integer i,j,k,base,delta,value,seed=939332;
 reg [26:0] center,neighbors[0:4];reg [23:0] color;reg [1:0] strength;
 initial begin
  for(i=0;i<100000;i=i+1)begin
   center={$random(seed),$random(seed)};color=$random(seed);strength=i%4;
   for(j=0;j<5;j=j+1)for(k=0;k<3;k=k+1)begin
    base=center[k*9+:9];delta=($random(seed)&32'h7fffffff)%71-35;
    value=(i%7==0)?($random(seed)&511):(base+delta);
    if(value<0)value=0;if(value>511)value=511;
    neighbors[j][k*9+:9]=value;
   end
   if(dut.range5(center,neighbors[0],neighbors[1],neighbors[2],neighbors[3],neighbors[4])!==
      ref_dut.range5(center,neighbors[0],neighbors[1],neighbors[2],neighbors[3],neighbors[4]))
    $fatal(1,"range arithmetic mismatch vector=%0d",i);
   if(dut.finish_pixel(color,strength)!==ref_dut.finish_pixel(color,strength))
    $fatal(1,"finish arithmetic mismatch vector=%0d",i);
  end
  $display("PHOTO_RESOURCE_ARITHMETIC_PASS vectors=100000");$finish;
 end
endmodule
