`timescale 1ns/1ps
// Actual maintained mixer: camera colour must be identical in both outputs
// whenever HDMI is not covered by logo/text/boxes. No transmitter IP model.
module tb_mixer_v37_equivalence #(parameter BOXES=0);
  reg clk=0,rst=0,vs=0,hs=0,de=0;
  reg [23:0] rgb=0;
  always #6.666667 clk=~clk;
  wire [23:0] picture,clean;
  wire ov,oh,od,read_enable;
  integer x,y,n=0,checked=0,overlays=0;
  reg [23:0] expected;
  reg covered;
  hdmi_mixer_user #(.IMG_WIDTH(1280),.IMG_HEIGHT(720),
      .DEBUG_MODE(0),.DISPLAY_BRIGHT_ENABLE(0)) dut (
    .I_clk(clk),.I_rst_n(rst),.I_video_vsync(vs),.I_video_hsync(hs),
    .I_video_de(de),.I_video_user(1'b0),.I_video_last(1'b0),
    .I_debug_status(4'd0),.I_algo_mode(3'd0),
    .I_cam_frame_cnt(8'd0),.I_latency_valid(1'b1),.I_latency_ms(16'd123),
    .I_motion_valid(1'b1),.I_motion_count(16'd65535),.I_motion_enable(1'b1),
    .I_track_valid(1'b1),.I_track_cnt(4'd3),.I_track_enable(1'b1),
    .I_t0_v(BOXES != 0),.I_t0_x(11'd0),.I_t0_y(11'd0),.I_t0_shape(2'd0),
    .I_t0_xmin(11'd300),.I_t0_xmax(11'd650),.I_t0_ymin(11'd100),.I_t0_ymax(11'd600),
    .I_t1_v(BOXES != 0),.I_t1_x(11'd0),.I_t1_y(11'd0),.I_t1_shape(2'd1),
    .I_t1_xmin(11'd480),.I_t1_xmax(11'd830),.I_t1_ymin(11'd100),.I_t1_ymax(11'd600),
    .I_t2_v(BOXES != 0),.I_t2_x(11'd0),.I_t2_y(11'd0),.I_t2_shape(2'd2),
    .I_t2_xmin(11'd660),.I_t2_xmax(11'd1010),.I_t2_ymin(11'd100),.I_t2_ymax(11'd600),
    .I_digit_valid(1'b1),.I_digit_id(4'd8),.I_digit_confidence(8'haf),.I_digit_enable(1'b1),
    .I_hand_valid(1'b1),.I_hand_id(2'd3),.I_hand_tips(3'd4),.I_hand_box_valid(BOXES != 0),
    .I_hand_xmin(10'd120),.I_hand_xmax(10'd220),.I_hand_ymin(10'd140),.I_hand_ymax(10'd650),
    .I_aruco_axes(167'd0),.I_hand_enable(1'b1),.I_aruco_enable(1'b0),.I_aruco_valid(1'b0),.I_video_rd_data(rgb),.O_video_rd_en(read_enable),
    .O_hdmi_vsync(ov),.O_hdmi_hsync(oh),.O_hdmi_de(od),
    .O_hdmi_data(picture),.O_hdmi_clean_data(clean));
  wire [23:0] ref_picture,ref_clean; wire rv,rh,rd,read_ref;
  hdmi_mixer_v35_reference #(.IMG_WIDTH(1280),.IMG_HEIGHT(720),
      .DEBUG_MODE(0),.DISPLAY_BRIGHT_ENABLE(0)) reference (
    .I_clk(clk),.I_rst_n(rst),.I_video_vsync(vs),.I_video_hsync(hs),
    .I_video_de(de),.I_video_user(1'b0),.I_video_last(1'b0),
    .I_debug_status(4'd0),.I_algo_mode(3'd0),
    .I_cam_frame_cnt(8'd0),.I_latency_valid(1'b1),.I_latency_ms(16'd123),
    .I_motion_valid(1'b1),.I_motion_count(16'd65535),.I_motion_enable(1'b1),
    .I_track_valid(1'b1),.I_track_cnt(4'd3),.I_track_enable(1'b1),
    .I_t0_v(BOXES != 0),.I_t0_x(11'd0),.I_t0_y(11'd0),.I_t0_shape(2'd0),
    .I_t0_xmin(11'd300),.I_t0_xmax(11'd650),.I_t0_ymin(11'd100),.I_t0_ymax(11'd600),
    .I_t1_v(BOXES != 0),.I_t1_x(11'd0),.I_t1_y(11'd0),.I_t1_shape(2'd1),
    .I_t1_xmin(11'd480),.I_t1_xmax(11'd830),.I_t1_ymin(11'd100),.I_t1_ymax(11'd600),
    .I_t2_v(BOXES != 0),.I_t2_x(11'd0),.I_t2_y(11'd0),.I_t2_shape(2'd2),
    .I_t2_xmin(11'd660),.I_t2_xmax(11'd1010),.I_t2_ymin(11'd100),.I_t2_ymax(11'd600),
    .I_digit_valid(1'b1),.I_digit_id(4'd8),.I_digit_confidence(8'haf),.I_digit_enable(1'b1),
    .I_hand_valid(1'b1),.I_hand_id(2'd3),.I_hand_tips(3'd4),.I_hand_box_valid(BOXES != 0),
    .I_hand_xmin(10'd120),.I_hand_xmax(10'd220),.I_hand_ymin(10'd140),.I_hand_ymax(10'd650),
    .I_hand_enable(1'b1),.I_aruco_enable(1'b0),.I_aruco_valid(1'b0),.I_video_rd_data(rgb),.O_video_rd_en(read_ref),
    .O_hdmi_vsync(rv),.O_hdmi_hsync(rh),.O_hdmi_de(rd),
    .O_hdmi_data(ref_picture),.O_hdmi_clean_data(ref_clean));

  always @(posedge clk) begin
    #1;
    if(rst && {ov,oh,od,picture,clean,read_enable} !==
              {rv,rh,rd,ref_picture,ref_clean,read_ref})
      $fatal(1,"mixer mismatch x=%0d y=%0d rgb=%h ref=%h",x,y,picture,ref_picture);
    if(rst && od) checked=checked+1;
  end

  initial begin
    repeat(4) @(negedge clk);rst=1;vs=1;
    repeat(8) @(negedge clk);vs=0;
    for(y=0;y<720;y=y+1) begin
      for(x=0;x<1280;x=x+1) begin
        @(negedge clk);de=1;
        // Different channels, all code values, primary colours and neutral ramp.
        case((x/160)%8)
          0:rgb=24'hff0000;1:rgb=24'h00ff00;2:rgb=24'h0000ff;
          3:rgb=24'hffffff;4:rgb=24'h000000;
          5:rgb={8'(x),8'(x),8'(x)};
          default:rgb={8'(x),8'(y),8'(x+y)};
        endcase
      end
      @(negedge clk);de=0;rgb=0;hs=1;
      repeat(30) @(negedge clk);hs=0;
    end
    repeat(16) @(negedge clk);
    $display("MIXER_V37_AXIS_DISABLED_EQUIVALENCE_PASS pixels=%0d",checked);
    $finish;
  end
endmodule
