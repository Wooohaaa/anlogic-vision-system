`timescale 1ns/1ps
module tb_motion_grid_v92;
 parameter GAPS=0,W=128,H=96,FRAMES=280;
 localparam G=W/4,TILES=((W+31)/32)*((H+31)/32);
 localparam RECOVERY_BASE=(FRAMES==16)?40:80;
 reg clk=0,rst=0,v=0,u=0,l=0,step=0,restart=0;
 reg [95:0] rgb=0;
 always #5 clk=~clk;
 wire sv,hit,fd,rv;wire [9:0] sx,sy;wire [52:0] result;
 ua_motion_detect #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.Y_DOWNSAMPLE(4),
 .LOW_LIGHT_LEVEL(96),.LOW_LIGHT_THRESHOLD(16),.HOLD_BACKGROUND_ON_MOTION(0)) detector(
 .I_clk(clk),.I_rst_n(rst),.I_tlast(l),.I_tuser(u),.I_tdata(rgb),.I_tvalid(v),
 .I_tready(1'b1),.I_background_restart(restart),.O_tlast(),.O_tuser(),.O_tdata(),
 .O_tvalid(),.O_tready(),.O_motion_sample_valid(),.O_hand_sample_valid(sv),
 .O_hand_frame_done(fd),.O_motion_hit(hit),.O_motion_x_grp(sx),.O_motion_y(sy),
 .O_motion_valid(),.O_motion_count());
 ua_motion_grid #(.WIDTH(W),.HEIGHT(H)) grid(
 .clk(clk),.rst_n(rst),.sample_valid(sv),.hit(hit),.frame_done(fd),.camera_step(step),
 .x_grp(sx),.y(sy),.result_valid(rv),.result(result));
 integer f,x,y,pixel,received=0,expected_pct,expected_box,expected_cam;
 reg [52:0] saved;
 always @(posedge clk)begin #1;if(rv)begin received=received+1;saved=result;end end
 task idle(input integer n);
 integer i;begin for(i=0;i<n;i=i+1)begin @(negedge clk);v=0;u=0;l=0;step=0;end end endtask
 task check_result;
 begin
  expected_pct=-1;expected_box=-1;expected_cam=0;
  case(f)
   0:begin expected_pct=0;expected_box=0;end
   1:begin expected_pct=100/TILES;expected_box=1;end
   2,3:begin expected_pct=0;expected_box=1;end
   4:begin expected_pct=0;expected_box=0;end
   5:begin expected_pct=100/TILES;expected_box=1;end
   6,7:expected_pct=0;
   8:begin expected_pct=100/TILES;expected_box=1;end
   9:begin expected_pct=100;expected_box=1;end
   10:expected_pct=0;
   11,12,13,14:begin expected_pct=0;expected_box=0;expected_cam=1;end
   15:expected_pct=0;
   16:expected_pct=100;
   17,18,19,20,21,22,23,24,25:expected_pct=0;
   default:if(f>=26)begin expected_pct=100/TILES;expected_box=1;end
  endcase
  if(expected_pct>=0 && saved[50:44]!==expected_pct[6:0])
   $fatal(1,"percent frame=%0d got=%0d want=%0d",f,saved[50:44],expected_pct);
  if(expected_box>=0 && saved[51]!==expected_box[0])$fatal(1,"box frame=%0d",f);
  if(saved[52]!==expected_cam[0])$fatal(1,"camera frame=%0d got=%b",f,saved[52]);
  if(f==1 && saved[43:0]!=={11'd32,11'd63,11'd32,11'd63})$fatal(1,"tile bounds");
  if(f==8 && saved[43:0]!=={11'(W-32),11'(W-1),11'(((H-1)/32)*32),11'(H-1)})$fatal(1,"last tile bounds");
 end endtask
 initial begin
  repeat(4)@(negedge clk);rst=1;
  for(f=0;f<FRAMES;f=f+1)begin
   for(y=0;y<H;y=y+1)for(x=0;x<G;x=x+1)begin
    pixel=80;
    if(f>=1 && f<=4 && x>=8 && x<16 && y>=32 && y<64)pixel=180;
    if(f==6 && x==12 && y==39)pixel=180;
    if(f==8 && x>=G-8 && y>=((H-1)/32)*32)pixel=180;
    if(f>=9 && f<=15)pixel=40;
    if(f>=26 && f%2==0 && x>=8 && x<16 && y>=32 && y<64)pixel=180;
    @(negedge clk);v=1;u=x==0&&y==0;l=x==G-1;rgb={12{8'(pixel)}};
    step=f==11&&x==5&&y==50;
    restart=f==21&&x==5&&y==10;
    if(GAPS && x%11==7)idle(2);
   end
   idle(140);check_result();
  end
  if(received!=FRAMES)$fatal(1,"missing frame results %0d",received);
  // Missing EOF followed by a valid SOF: partial tile votes must be dropped.
  for(y=0;y<20;y=y+1)for(x=0;x<G;x=x+1)begin
   @(negedge clk);v=1;u=x==0&&y==0;l=x==G-1;rgb={12{8'(RECOVERY_BASE)}};
  end
  idle(140);
  if(received!=FRAMES)$fatal(1,"partial frame incorrectly published");
  for(y=0;y<H;y=y+1)for(x=0;x<G;x=x+1)begin
   @(negedge clk);v=1;u=x==0&&y==0;l=x==G-1;rgb={12{8'(RECOVERY_BASE)}};
  end
  idle(140);
  if(received!=FRAMES+1 || saved[50:44]!==7'd0)$fatal(1,"bad-frame SOF recovery");
  if(detector.frame_n!==8'd2)$fatal(1,"initialization counter not saturated");
  $display("MOTION_GRID_V92_PASS frames=%0d gaps=%0d stationary noise full_frame camera stop rollover",received,GAPS);$finish;
 end
 initial begin #300000000;$fatal(1,"timeout");end
endmodule
