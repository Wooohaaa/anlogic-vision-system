`timescale 1ns/1ps
// Actual maintained mixer: camera colour must be identical in both outputs
// whenever HDMI is not covered by logo/text/boxes. No transmitter IP model.
module tb_v87_gray_cover;
  reg clk=0,rst=0,vs=0,hs=0,de=0,user=0,last=0;
  reg [23:0] rgb=0;
  always #6.666667 clk=~clk;
  wire [23:0] picture,clean;
  wire ov,oh,od,read_enable;
  integer x,y,n=0,checked=0,overlays=0,pixel_count=0,gray_count=0;
  reg [23:0] expected;
  reg covered;
  hdmi_mixer_user #(.IMG_WIDTH(1280),.IMG_HEIGHT(720),
      .DEBUG_MODE(0),.DISPLAY_BRIGHT_ENABLE(0)) dut (
    .I_clk(clk),.I_rst_n(rst),.I_video_vsync(vs),.I_video_hsync(hs),
    .I_video_de(de),.I_video_user(user),.I_video_last(last),
    .I_debug_status(4'd0),.I_algo_mode(3'd0),
    .I_cam_frame_cnt(8'd0),.I_latency_valid(1'b0),.I_latency_ms(16'd0),
    .I_motion_valid(1'b0),.I_motion_count(16'd0),.I_motion_enable(1'b0),
    .I_track_valid(1'b0),.I_track_cnt(4'd0),.I_track_enable(1'b0),
    .I_t0_v(1'b0),.I_t0_x(11'd0),.I_t0_y(11'd0),.I_t0_shape(2'd0),
    .I_t0_xmin(11'd0),.I_t0_xmax(11'd0),.I_t0_ymin(11'd0),.I_t0_ymax(11'd0),
    .I_t1_v(1'b0),.I_t1_x(11'd0),.I_t1_y(11'd0),.I_t1_shape(2'd0),
    .I_t1_xmin(11'd0),.I_t1_xmax(11'd0),.I_t1_ymin(11'd0),.I_t1_ymax(11'd0),
    .I_t2_v(1'b0),.I_t2_x(11'd0),.I_t2_y(11'd0),.I_t2_shape(2'd0),
    .I_t2_xmin(11'd0),.I_t2_xmax(11'd0),.I_t2_ymin(11'd0),.I_t2_ymax(11'd0),
    .I_digit_valid(1'b0),.I_digit_id(4'd0),.I_digit_confidence(8'd0),.I_digit_enable(1'b0),
    .I_hand_valid(1'b0),.I_hand_id(2'd0),.I_hand_tips(3'd0),.I_hand_box_valid(1'b0),
    .I_hand_xmin(10'd0),.I_hand_xmax(10'd0),.I_hand_ymin(10'd0),.I_hand_ymax(10'd0),
    .I_hand_enable(1'b0),.I_video_rd_data(rgb),.O_video_rd_en(read_enable),
    .O_hdmi_vsync(ov),.O_hdmi_hsync(oh),.O_hdmi_de(od),
    .O_hdmi_data(picture),.O_hdmi_clean_data(clean));
  always @(posedge clk) begin
    expected=dut.S_video_data_3d;
    covered=dut.S_logo_hit_5d || dut.S_osd_hit_5d;
    #1;
    if(rst && od) begin
      if(clean!==expected) $fatal(1,"clean tap changed colour expected=%h actual=%h",expected,clean);
      if(pixel_count<1280) begin
        if(picture!==24'h808080) $fatal(1,"top row not gray pixel=%d value=%h",pixel_count,picture);
        gray_count=gray_count+1;
      end else if(!covered) begin
        if(clean!==picture) $fatal(1,"HDMI/network colour mismatch HDMI=%h tap=%h",picture,clean);
        checked=checked+1;
      end else overlays=overlays+1;
      pixel_count=pixel_count+1;
    end
  end
  initial begin
    repeat(4) @(negedge clk);rst=1;vs=1;user=1;
    repeat(8) @(negedge clk);vs=0;user=0;
    for(y=0;y<720;y=y+1) begin
      for(x=0;x<1280;x=x+1) begin
        @(negedge clk);de=1;last=x==1279;
        // Different channels, all code values, primary colours and neutral ramp.
        case((x/160)%8)
          0:rgb=24'hff0000;1:rgb=24'h00ff00;2:rgb=24'h0000ff;
          3:rgb=24'hffffff;4:rgb=24'h000000;
          5:rgb={8'(x),8'(x),8'(x)};
          default:rgb={8'(x),8'(y),8'(x+y)};
        endcase
      end
      @(negedge clk);de=0;last=0;rgb=0;hs=1;
      repeat(30) @(negedge clk);hs=0;
    end
    repeat(16) @(negedge clk);
    if(checked+overlays+gray_count!=921600 || gray_count!=1280 || checked<800000)
      $fatal(1,"coverage picture=%0d overlay=%0d",checked,overlays);
    $display("V87_GRAY_COVER_PASS picture=%0d overlay=%0d one_row_1280_gray_other_pixels_unchanged",checked,overlays);
    $finish;
  end
endmodule
