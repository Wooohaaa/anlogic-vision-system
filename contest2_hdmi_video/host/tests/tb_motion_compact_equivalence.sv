`timescale 1ns/1ps
module tb_motion_compact_equivalence;
parameter W=1280,H=720,DOWNSAMPLE=4,ROI=0,HOLD=1;
localparam G=W/4;
reg clk=0;always #5 clk=~clk;
reg rst=0,valid=0,last=0,user=0,ready=1,restart=0;reg[95:0]data=0;
wire[140:0]old_result,new_result;
genvar k;
generate for(k=0;k<2;k=k+1)begin:instance_pair
 wire ol,ou,ov,orr,ms,hs,hd,mhit,mv;wire[95:0]od;wire[9:0]mx,my;wire[15:0]count;
 ua_motion_detect #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.Y_DOWNSAMPLE(DOWNSAMPLE),
 .ROI_ENABLE(ROI),.ROI_X0_GRP(G/4),.ROI_X1_GRP(3*G/4-1),.ROI_Y0(H/4),.ROI_Y1(3*H/4-1),
 .LOW_LIGHT_LEVEL(96),.LOW_LIGHT_THRESHOLD(16),.HOLD_BACKGROUND_ON_MOTION(HOLD),.COMPACT_REFERENCE_RAM(k)) core(
 clk,rst,last,user,data,valid,ready,restart,ol,ou,od,ov,orr,ms,hs,hd,mhit,mx,my,mv,count);
 if(k==0)assign old_result={ol,ou,od,ov,orr,ms,hs,hd,mhit,mx,my,mv,count};
 else assign new_result={ol,ou,od,ov,orr,ms,hs,hd,mhit,mx,my,mv,count};
end endgenerate
integer frame,y,x,j,checked=0,frame_pulses=0,hand_frames=0;reg[31:0]rng=32'h18517329;reg[7:0]value;
always @(posedge clk)begin
 #1;
 if(rst)begin
  if(old_result!==new_result)$fatal(1,"motion equivalence cycle=%0d old=%h new=%h",checked,old_result,new_result);
  checked=checked+1;
  if(instance_pair[1].mv)frame_pulses=frame_pulses+1;
  if(instance_pair[1].hd)hand_frames=hand_frames+1;
 end
end
initial begin
 repeat(5)@(negedge clk);rst=1;
 for(frame=0;frame<8;frame=frame+1)begin
  for(y=0;y<H;y=y+1)begin
   for(x=0;x<G;x=x+1)begin
    @(negedge clk);rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
    value=(7*x+3*y)&255;
    if(frame>=2 && frame<=6 && x>=G/3 && x<G/3+G/5 && y>=H/3 && y<H/3+H/4)value=value+8'd65;
    if(frame==7)value=8'd255-value;
    data={12{value}};valid=1;user=x==0 && y==0;last=x==G-1;ready=rng[0];
    restart=frame==4 && y==H/2 && x==G/2;
   end
   @(negedge clk);valid=0;last=0;user=0;restart=0;
   for(j=0;j<(y%4);j=j+1)begin @(negedge clk);data=~data;end
  end
  repeat(5)@(negedge clk);
 end
 repeat(10)@(negedge clk);
 if(hand_frames!=8 || frame_pulses==0)$fatal(1,"frame completion mismatch hand=%0d motion=%0d",hand_frames,frame_pulses);
 $display("MOTION_COMPACT_EQUIVALENCE_PASS W=%0d H=%0d D=%0d ROI=%0d HOLD=%0d cycles=%0d",W,H,DOWNSAMPLE,ROI,HOLD,checked);$finish;
end
endmodule

// Simulation-only model of the old macro's same-clock DP/NOREG contract.
// This does not replace vendor timing models or implementation checks.
module PH1P_LOGIC_ERAM #(
 parameter DATA_WIDTH_A=8,DATA_WIDTH_B=8,ADDR_WIDTH_A=16,ADDR_WIDTH_B=16,
 parameter DATA_DEPTH_A=57600,DATA_DEPTH_B=57600,MODE="DP",REGMODE_A="NOREG",REGMODE_B="NOREG",
 parameter WRITEMODE_A="NORMAL",WRITEMODE_B="NORMAL",CLKMODE="ASYNC",IMPLEMENT="20K(FAST)",
 parameter FILL_ALL="NONE",ECC_ENCODE="DISABLE",ECC_DECODE="DISABLE"
)(input clka,cea,wea,input[ADDR_WIDTH_A-1:0]addra,input[DATA_WIDTH_A-1:0]dia,
 output[DATA_WIDTH_A-1:0]doa,input bea,rsta,ocea,
 input clkb,ceb,web,input[ADDR_WIDTH_B-1:0]addrb,input[DATA_WIDTH_B-1:0]dib,
 output reg[DATA_WIDTH_B-1:0]dob,input beb,rstb,oceb,
 output ecc_sbiterr,ecc_dbiterr,input ecc_sbiterrinj,ecc_dbiterrinj);
 reg[DATA_WIDTH_A-1:0]mem[0:DATA_DEPTH_A-1];
 always @(posedge clka)if(cea && wea)begin
  if(addra>=DATA_DEPTH_A)$fatal(1,"legacy write address overflow");mem[addra]<=dia;
 end
 always @(posedge clkb)if(ceb)begin
  if(web || addrb>=DATA_DEPTH_B)$fatal(1,"legacy read contract");dob<=mem[addrb];
 end
 assign doa=0;assign ecc_sbiterr=0;assign ecc_dbiterr=0;
endmodule
