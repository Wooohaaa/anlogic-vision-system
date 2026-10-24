`timescale 1ns/1ps
module tb_aruco_axes_path;
 parameter TRACE_FILE="tmp/aruco/v37_axes_runtime.hex";
 parameter FRAME_FILE="tmp/aruco/v37_axes_frame.rgb";
 parameter EXPECT_BLUE=1;
 reg clk=0,vid=0,disp=0,rst=0,vs=0,de=0,user_sof=0,line_last=0;
 always #10 clk=~clk;
 always #7 vid=~vid;
 always #6 disp=~disp;
 wire [166:0] axes;reg enable=1;reg [31:0] trace[0:15];integer red=0,green=0,blue=0;
 integer image_file,pixel_count=0;reg save_frame=0;
 wire result_valid; wire [11:0] id;
 wire [21:0] corner[0:3];wire [25:0] edge_eq[0:3];
 wire [23:0] picture;wire od;
 reg [1:0] trans=0;reg wr=0;reg [30:0] addr=0;reg [31:0] data=0;
 integer x,y,cyan=0,yellow=0,commits=0,i;
 integer ax[0:3],ay[0:3];
 function [25:0] equation(input integer x0,y0,x1,y1);
  integer dx,dy,major,minor,slope,intercept,origin,ordinate,flag;
  begin
   dx=x1-x0;dy=y1-y0;flag=($abs(dx)>=$abs(dy));
   major=flag?dx:dy;minor=flag?dy:dx;origin=flag?x0:y0;ordinate=flag?y0:x0;
   slope=major? $rtoi(1024.0*minor/major):0;
   intercept=$rtoi(2.0*ordinate-2.0*slope*origin/1024.0);
   equation=(flag<<25)|((intercept&8191)<<12)|(slope&4095);
  end
 endfunction
 ua_tracking_mcu #(.ENABLE_ARUCO(1)) bridge(
  .clk_50m(clk),.uart_rx(1'b1),.target_uart(1'b1),
  .video_clk(vid),.video_rst_n(rst),.video_rgb(96'd0),
  .video_valid(1'b0),.video_sof(1'b0),.video_eol(1'b0),.aruco_enable(1'b1),
  .display_clk(disp),.display_rst_n(rst),.O_aruco_valid(result_valid),
  .O_aruco_axes(axes),.O_aruco_id_bcd(id),.O_aruco_corner0(corner[0]),.O_aruco_corner1(corner[1]),
  .O_aruco_corner2(corner[2]),.O_aruco_corner3(corner[3]),
  .O_aruco_edge0(edge_eq[0]),.O_aruco_edge1(edge_eq[1]),
  .O_aruco_edge2(edge_eq[2]),.O_aruco_edge3(edge_eq[3]));
 hdmi_mixer_user #(.H_OFFSET(0),.V_OFFSET(0),.DISPLAY_BRIGHT_ENABLE(0)) mixer(
  .I_clk(disp),.I_rst_n(rst),.I_video_vsync(vs),.I_video_hsync(1'b0),
  .I_video_de(de),.I_video_user(user_sof),.I_video_last(line_last),
  .I_debug_status(4'd0),.I_algo_mode(3'd0),.I_cam_frame_cnt(8'd0),
  .I_latency_valid(1'b0),.I_latency_ms(16'd0),
  .I_motion_enable(1'b0),.I_track_enable(1'b0),.I_digit_enable(1'b0),.I_hand_enable(1'b0),
  .I_aruco_axes(axes),.I_aruco_enable(enable),.I_aruco_valid(result_valid),.I_aruco_id_bcd(id),
  .I_aruco_corner0(corner[0]),.I_aruco_corner1(corner[1]),
  .I_aruco_corner2(corner[2]),.I_aruco_corner3(corner[3]),
  .I_aruco_edge0(edge_eq[0]),.I_aruco_edge1(edge_eq[1]),
  .I_aruco_edge2(edge_eq[2]),.I_aruco_edge3(edge_eq[3]),
  .I_video_rd_data(24'h202020),.O_hdmi_data(picture),.O_hdmi_de(od));
 task write_word(input [30:0] a,input [31:0] v);
 begin
  @(negedge clk);while(!bridge.ahb_ready)@(negedge clk);
  trans=2;wr=1;addr=a;data=0;
  @(posedge clk);@(negedge clk);trans=0;data=v;
  do @(posedge clk);while(!bridge.ahb_ready);
  if(bridge.ahb_resp!==0)$fatal(1,"write error");
  @(negedge clk);wr=0;data=0;
 end endtask
 always @(posedge disp)begin
  #1;if(od && picture==24'h00ffff)cyan=cyan+1;
  if(od && save_frame)begin
   $fwrite(image_file,"%c%c%c",picture[23:16],picture[15:8],picture[7:0]);pixel_count=pixel_count+1;
  end
  if(od && picture==24'hff0000)red=red+1;
  if(od && picture==24'h00ff00)green=green+1;
  if(od && picture==24'h0000ff)blue=blue+1;
  if(od && picture==24'hfff200 && mixer.S_y_2d>=136 && mixer.S_y_2d<160 &&
     mixer.S_x_5d>=200 && mixer.S_x_5d<296)yellow=yellow+1;
 end
 always @(bridge.aruco_result_toggle_bus)if(rst)commits=commits+1;
 initial begin
  #101;rst=1;wait(bridge.mcu.done);@(negedge clk);
  force bridge.ahb_trans=trans;force bridge.ahb_write=wr;
  force bridge.ahb_addr=addr;force bridge.ahb_wdata=data;
  $readmemh(TRACE_FILE,trace);
  for(i=0;i<15;i=i+1)write_word('h114+4*i,trace[i]);
  repeat(12)@(negedge disp);
  if(result_valid || axes[166])$fatal(1,"uncommitted payload became valid");
  write_word('h110,trace[15]);
  repeat(12)@(negedge disp);
  if(!result_valid || !axes[166] || id!='h23 || commits!=1)$fatal(1,"axis CDC commit missing");
  for(i=0;i<4;i=i+1)if(axes[22*i+:22]!==trace[8+i][21:0])$fatal(1,"point CDC mismatch");
  for(i=0;i<3;i=i+1)if(axes[88+26*i+:26]!==trace[12+i][25:0])$fatal(1,"equation CDC mismatch");
  image_file=$fopen(FRAME_FILE,"wb");
  save_frame=1;
  vs=1;user_sof=1;repeat(8)@(negedge disp);vs=0;user_sof=0;
  for(y=0;y<720;y=y+1)begin
   for(x=0;x<1280;x=x+1)begin @(negedge disp);de=1;line_last=(x==1279);end
   @(negedge disp);de=0;line_last=0;repeat(30)@(negedge disp);
  end
  repeat(12)@(negedge disp);
  save_frame=0;$fclose(image_file);
  if(pixel_count!=1280*720)$fatal(1,"capture pixel count=%d",pixel_count);
  if(cyan<1000 || red<15 || green<15 || (EXPECT_BLUE && blue<15) || (!EXPECT_BLUE && blue>10))
   $fatal(1,"HDMI axes mismatch cyan=%d R=%d G=%d B=%d expect_blue=%d",cyan,red,green,blue,EXPECT_BLUE);
  write_word('h110,'h80000023);repeat(12)@(negedge disp);
  user_sof=1;repeat(3)@(negedge disp);user_sof=0;repeat(12)@(negedge disp);
  if(!mixer.S_aruco_valid_disp || mixer.S_aruco_axes_disp[166] || mixer.S_aruco_axis_hit_5d)
   $fatal(1,"an axes-invalid commit must retain the marker box and clear axes");
  enable=0;repeat(12)@(negedge disp);
  if(mixer.S_aruco_axes_disp[166] || mixer.S_aruco_axis_hit_5d)$fatal(1,"disable left stale axes");
  enable=1;
  write_word('h110,0);repeat(10)@(negedge disp);
  if(result_valid || id!=0)$fatal(1,"CDC invalidation failed");
  user_sof=1;repeat(3)@(negedge disp);user_sof=0;
  repeat(10)@(negedge disp);
  if(mixer.S_aruco_valid_disp || mixer.S_aruco_edge_hit_2d || mixer.S_aruco_axes_disp[166] || mixer.S_aruco_axis_hit_5d)$fatal(1,"stale overlay survived invalidation");
  $display("ARUCO_AXES_HDMI_PATH_PASS C_MMIO_AHB_CDC_HDMI cyan=%0d R=%0d G=%0d B=%0d commits=%0d clear_pass",cyan,red,green,blue,commits);$finish;
 end
 initial begin #30000000;$fatal(1,"timeout");end
endmodule
