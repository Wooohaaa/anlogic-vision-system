`timescale 1ns/1ps
// Coordinate oracle independent of the DUT counters. Covers partial startup,
// truncated frames and SOF on what used to be the last pixel of a frame.
module tb_motion_sof_recovery;
parameter D=4;
localparam W=80,H=48,G=W/4;
reg clk=0;always #5 clk=~clk;
reg rst=0,valid=0,user=0,last=0;reg[95:0]rgb=0;
wire sv,fd;wire[9:0]x,y;wire[95:0]od;
ua_motion_detect #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.Y_DOWNSAMPLE(D),.ROI_ENABLE(0),.COMPACT_REFERENCE_RAM(1)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_tlast(last),.I_tuser(user),.I_tdata(rgb),.I_tvalid(valid),.I_tready(1'b1),.I_background_restart(1'b0),
 .O_tlast(),.O_tuser(),.O_tdata(od),.O_tvalid(),.O_tready(),.O_motion_sample_valid(),.O_hand_sample_valid(sv),.O_hand_frame_done(fd),
 .O_motion_hit(),.O_motion_x_grp(x),.O_motion_y(y),.O_motion_valid(),.O_motion_count());
integer n,r,c,p,checks=0,completions=0;reg expected,checking=0;reg[9:0]ex,ey;reg[95:0]edata;
task beat(input integer xx,yy,input bit sof,check);
 begin
 @(negedge clk);valid=1;user=sof;last=xx==G-1;
 rgb={32'd0,32'd0,12'd0,yy[9:0],xx[9:0]};
 expected=(yy%D)==((H-1)%D);ex=xx;ey=yy;edata=rgb;checking=check;
 @(posedge clk);#1;
 if(checking)begin
  if(sv!==expected)$fatal(1,"Sample phase D=%d x=%d y=%d sv=%b",D,ex,ey,sv);
  if(sv && (x!==ex || y!==ey || od!==edata))$fatal(1,"SOF recovery coordinate/RGB D=%d got=%d,%d expected=%d,%d",D,x,y,ex,ey);
  checks=checks+1;
 end
 end
endtask
always @(negedge clk)if(fd)completions=completions+1;
initial begin
 repeat(5)@(negedge clk);rst=1;
 // Deliberately do NOT reset between cases. Each new SOF must recover.
 for(p=0;p<8;p=p+1)begin
  case(p)
   0:n=1;1:n=13;2:n=19;3:n=20;4:n=73;5:n=959;6:n=360;default:n=123;
  endcase
  for(c=0;c<n;c=c+1)beat(c%G,(c/G)%H,0,0);
  for(r=0;r<H;r=r+1)begin
   for(c=0;c<G;c=c+1)beat(c,r,(r==0&&c==0),1);
   @(negedge clk);valid=0;user=0;last=0;checking=0;
   repeat(r%3)@(negedge clk);
  end
  repeat(4)@(negedge clk);
 end
 if(checks!=8*G*H)$fatal(1,"Missing coordinate checks");
 $display("MOTION_SOF_RECOVERY_PASS D=%d checked=%d",D,checks);$finish;
end
endmodule
