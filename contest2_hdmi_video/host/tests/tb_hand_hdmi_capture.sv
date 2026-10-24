`timescale 1ns/1ps
module tb_hand_hdmi_capture #(
 parameter DIRECT_SUMS=1,
 parameter ROW_GAP=4,
 parameter LOC_HYSTERESIS=0,
 parameter FINGER_GAP=2,
 parameter SWITCH_FRAMES=2,
 parameter LOCAL_GUARD=0,
 parameter MIN_R=96,
 parameter RUN_MEAN=0,
 parameter PROFILE_MIN=96,
 parameter UP_BIAS=0,
 parameter SOLID=0
);
 reg clk=0,rst=0,valid=0,done=0;
 always #5 clk=~clk;
 reg [9:0] x=0,y=0,sr=0,sg=0,sb=0;
 reg [95:0] rgb=0;
 wire result,box;
 wire [1:0] id;
 wire [2:0] tips;
 wire [9:0] xmin,xmax,ymin,ymax;
 ua_hand_profile #(.IMG_WIDTH(1280),.IMG_HEIGHT(720),.DYNAMIC_ROI(1),
  .SAMPLE_STEP(4),.MIN_AREA(100),.MAX_AREA(10000),.LOC_MIN_AREA(160),.MOTION_GATE_ENABLE(0),
  .LOC_BAND_HYSTERESIS(LOC_HYSTERESIS),.FINGER_GAP_SCALE(FINGER_GAP),
  .CLASS_SWITCH_FRAMES(SWITCH_FRAMES),.LOCAL_RUN_GUARD(LOCAL_GUARD),.SKIN_MIN_SUM(MIN_R),.RUN_MEAN_MIN(RUN_MEAN),
  .PROFILE_MIN_SUM(PROFILE_MIN),.ROI_UP_BIAS(UP_BIAS),.SOLID_CLASS_GUARD(SOLID)) dut(
  .I_clk(clk),.I_rst_n(rst),.I_clear(1'b0),.I_sample_valid(valid),.I_motion_hit(1'b1),
  .I_x_grp(x),.I_y(y),.I_rgb(rgb),.I_frame_done(done),.O_result_valid(result),
  .O_id(id),.O_tip_count(tips),.O_box_valid(box),.O_box_xmin(xmin),.O_box_xmax(xmax),
  .O_box_ymin(ymin),.O_box_ymax(ymax));
 generate if(DIRECT_SUMS)begin
  // The binary file contains exact sums of the four decoded source pixels.
  // Only these three input adders are bypassed; all color gates/ROI/FSM remain RTL.
  initial begin force dut.rs=sr;force dut.gs=sg;force dut.bs=sb;end
 end endgenerate
 reg [31:0] samples[0:57599];
 reg [4095:0] input_path;
 integer input_fd,output_fd,frame=0,start_frame=0,count=870,stride=1,bytes,seek_result;
 integer row,col,idx,pixel,candidate,geom,openhint,coherent,tipn,columns,area,base;
 integer fingerrows,upper,profilecand,bw,bh,palm,fingerheight;
 function [95:0] reconstruct(input [9:0] r,g,b);
  integer k;reg[7:0] rr,gg,bb;
  begin
   for(k=0;k<4;k=k+1)begin
    rr=(r>>2)+(k<r[1:0]);gg=(g>>2)+(k<g[1:0]);bb=(b>>2)+(k<b[1:0]);
    reconstruct[95-24*k-:24]={rr,gg,bb};
   end
  end
 endfunction
 always @(posedge clk)begin
  if(!DIRECT_SUMS && valid && (dut.rs!==sr || dut.gs!==sg || dut.bs!==sb))
   $fatal(1,"decoded RGB sum mismatch at %0d,%0d",x,y);
  if(done)begin
   fingerrows=dut.finger_best_rows;palm=dut.palm_bridge_seen;
   fingerheight=dut.finger_best_ymax-dut.finger_best_ymin;
  end
 end
 always @(negedge clk)begin
  if(dut.state==dut.GUARD && dut.guard_wait==0)begin
   geom=dut.geometry_ok;columns=dut.columns;area=dut.area;
   openhint=dut.qualified_open_hint;coherent=dut.qualified_coherent_open;
   candidate=0;tipn=0;upper=dut.upper_evidence;
   bw=dut.box_width_next;bh=dut.box_height;
  end
  if(dut.state==dut.COMMIT)begin
   candidate=dut.classified;tipn=dut.final_peaks;base=dut.baseline;
   openhint=dut.qualified_open_hint;coherent=dut.qualified_coherent_open;
   profilecand=dut.profile_classified;
  end
 end
 initial begin
  if(!$value$plusargs("input=%s",input_path))$fatal(1,"missing input");
  if($value$plusargs("frames=%d",count))begin end
  if($value$plusargs("start=%d",start_frame))begin end
  if($value$plusargs("stride=%d",stride))begin end
  input_fd=$fopen(input_path,"rb");if(!input_fd)$fatal(1,"cannot open source sums");
  output_fd=$fopen("results.csv","w");if(!output_fd)$fatal(1,"cannot open results");
  $fdisplay(output_fd,"frame,id,tips,box,xmin,xmax,ymin,ymax,candidate,geom,columns,area,baseline,open,coherent,roi_x0,roi_y0,upper,profile_candidate,width,height,finger_rows,palm_bridge,finger_height");
  seek_result=$fseek(input_fd,start_frame*230400,0);
  repeat(5)@(negedge clk);rst=1;
  for(frame=0;frame<count;frame=frame+1)begin
   bytes=$fread(samples,input_fd);if(bytes!=230400)$fatal(1,"short frame %d bytes %d",frame,bytes);
   for(row=0;row<180;row=row+1)begin
    for(col=0;col<320;col=col+1)begin
     @(negedge clk);valid=1;x=col;y=3+row*4;idx=row*320+col;
     sr=samples[idx][29:20];sg=samples[idx][19:10];sb=samples[idx][9:0];
     if(!DIRECT_SUMS)rgb=reconstruct(sr,sg,sb);
    end
    @(negedge clk);valid=0;repeat(ROW_GAP)@(negedge clk);
   end
   @(negedge clk);done=1;
   @(negedge clk);done=0;
   repeat(800)@(negedge clk);
   $fdisplay(output_fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
    start_frame+frame*stride,id,tips,box,xmin*4,xmax*4+3,ymin,ymax,candidate,geom,columns,area,base,openhint,coherent,dut.roi_x0_r*4,dut.roi_y0_r,upper,profilecand,bw,bh,fingerrows,palm,fingerheight);
   if(frame%30==0)$display("HAND_HDMI_PROGRESS frame=%0d id=%0d candidate=%0d",start_frame+frame*stride,id,candidate);
   if(stride>1)seek_result=$fseek(input_fd,(stride-1)*230400,1);
  end
  $fclose(input_fd);$fclose(output_fd);
  $display("HAND_HDMI_REPLAY_PASS frames=%0d first_frame_background=0 direct_sums=%0d row_gap=%0d",count,DIRECT_SUMS,ROW_GAP);
  $finish;
 end
endmodule
