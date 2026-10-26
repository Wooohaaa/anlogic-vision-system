// ============================================================================
// isp_top_user : 相机图像处理子系统。
// 主支路：RAW10 -> demosaic -> 官方 AWB -> 颜色偏移平衡 -> 自适应暗光 Gamma
//         -> motion旁路 -> ua_user_algo_96
//         -> 96/128 位宽转换。
// 检测支路观察同一份 AWB+Gamma 彩色流，不受灰度/Sobel/卡通显示模式影响。
// tvalid=数据有效，tuser=帧首，tlast=行尾；发生流水延迟时三者必须一起对齐。
// ============================================================================
module isp_top_user #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    parameter ENABLE_TRACK = 1,
    parameter ENABLE_ALGO = 1,
    parameter ENABLE_MOTION = 1,
    parameter ENABLE_MOTION_OVERLAY = 0,
    parameter ENABLE_HAND = 0,
    parameter ENABLE_STATS = 1,
    parameter ENABLE_DIGIT = 1,
    // 产品顶层打开；独立历史 testbench 默认关闭以保持原像素结果。
    parameter ENABLE_LOWLIGHT_ENHANCE = 0,
    // 亮度增强之后的轻量对比度恢复。默认关闭以保持独立历史
    // testbench 的 bit-exact 行为；产品顶层显式打开。
    parameter ENABLE_CONTRAST_ENHANCE = 0,
    // Diagnostic bypass preserves the denoiser and all five stream stages.
    // Output is still demosaiced/AWB-filtered RGB, not a RAW sensor capture.
    parameter PHOTO_TONE_ENABLE = 1,
    parameter [9:0] RAW_BLACK_LEVEL = 10'd0,
    parameter integer AWB_RUNTIME_CONTROL = 0,
    parameter integer BRIGHTNESS_RUNTIME_CONTROL = 0
)(
    input 			axi4s_video_aclk,
    input 			I_rst_n			,
    input 			I_tlast			,
    input 			I_tuser			,
    input [39:0] 	I_tdata			,
    input 			I_tvalid		,
    input [9:0] 	I_tdest			,
    input       [2:0] 	I_algo_mode		,
    input 			O_tready		,
    output [127:0] 	O_tdata			,
    output 			O_tlast			,
    output 			O_tuser			,
    output 			O_tvalid		,
    output 			I_tready		,
    output            O_motion_valid,   // 运动检测: 帧末脉冲 (csi 域)
        output     [15:0] O_motion_count,   // 运动检测: 本帧运动组数
        output            O_track_valid,    // 跟踪帧末脉冲 (csi 域)
        output     [3:0]  O_obj_cnt,        // 有效目标数
        output            O_t0_v,           // 红目标有效
         output     [10:0] O_t0_x, O_t0_y,   // 红目标中心(像素)
         output     [1:0]  O_t0_shape,       // 红目标形状: 0圆 1方 2条 3三角
         output     [10:0] O_t0_xmin, O_t0_xmax, O_t0_ymin, O_t0_ymax, // 红目标包围盒
         output            O_t1_v,           // 绿目标有效
         output     [10:0] O_t1_x, O_t1_y,
         output     [1:0]  O_t1_shape,
         output     [10:0] O_t1_xmin, O_t1_xmax, O_t1_ymin, O_t1_ymax, // 绿目标包围盒
         output            O_t2_v,           // 蓝目标有效
         output     [10:0] O_t2_x, O_t2_y,
         output     [1:0]  O_t2_shape,
         output     [10:0] O_t2_xmin, O_t2_xmax, O_t2_ymin, O_t2_ymax, // 蓝目标包围盒
        output            O_digit_valid,    // 数字识别稳定帧脉冲
        output     [3:0]  O_digit_id,       // 0..9，F=未知/未就绪
        output     [7:0]  O_digit_confidence,
        output            O_hand_valid,
        output     [1:0]  O_hand_id,
        output     [2:0]  O_hand_tip_count,
        output            O_hand_box_valid,
        output     [9:0]  O_hand_xmin, O_hand_xmax, O_hand_ymin, O_hand_ymax,
        output     [7:0]  O_ae_luma,       // 中心区域帧均值，整帧保持
        output            O_ae_luma_toggle, // 每个有效统计帧翻转一次
        output [1:0]      O_ae_highlight,
        input             I_awb_enable,
        input             I_brightness_enable,
        input [4:0]       I_gain_index,
        output [10:0]     O_awb_status,
        output [95:0]     O_aruco_rgb,
        output            O_aruco_valid,O_aruco_sof,O_aruco_eol,
        input             I_camera_step,
        output [52:0]     O_motion_view,
        output            O_motion_view_valid,
        output [56:0]     O_digit_view,
        output            O_digit_view_valid
);

// Motion ROI is defined as the centered 3/4 of the active image.  Keep it
// proportional to the configured geometry so reduced-resolution full-chain
// simulations (for example 320x180) exercise the same logic instead of
// inheriting the 1280x720 constants and never reaching frame_end.
localparam integer MOTION_ROI_X0_GRP = (IMG_WIDTH >> 5); // (W/8) pixels / 4
localparam integer MOTION_ROI_X1_GRP =
    (((IMG_WIDTH - (IMG_WIDTH >> 3)) - 1) >> 2);
localparam integer MOTION_ROI_Y0 = (IMG_HEIGHT >> 3);
localparam integer MOTION_ROI_Y1 = IMG_HEIGHT - (IMG_HEIGHT >> 3) - 1;
 
wire         m_aixs_tvalid;  //synthesis keep 
  wire [127:0] m_aixs_tdata;  //synthesis keep 
  wire         m_aixs_tuser;  //synthesis keep 
  wire         m_aixs_tlast;  //synthesis keep 
  wire         m_aixs_tready;  //synthesis keep 
  
  wire [ 95:0] m_aixs_tdata_96;  //synthesis keep 


  wire         awb_O_tlast;  //synthesis keep 
  wire         awb_O_tuser;  //synthesis keep 
  localparam integer AWB_CHANNEL_BITS =
      ((ENABLE_LOWLIGHT_ENHANCE!=0 || ENABLE_CONTRAST_ENHANCE!=0) && PHOTO_TONE_ENABLE!=0)?9:8;
  wire [12*AWB_CHANNEL_BITS-1:0] awb_wide_data;
  wire [95:0] awb_O_tdata;
  genvar awb_channel;
  generate for(awb_channel=0;awb_channel<12;awb_channel=awb_channel+1) begin : gen_awb_compat
      // This legacy disabled-offset path is not the production tone input.
      assign awb_O_tdata[awb_channel*8+:8] =
          (awb_wide_data[awb_channel*AWB_CHANNEL_BITS+:AWB_CHANNEL_BITS]>255)?
          8'hff:awb_wide_data[awb_channel*AWB_CHANNEL_BITS+:AWB_CHANNEL_BITS];
  end endgenerate
  wire         awb_O_tvalid;  //synthesis keep 

  // AWB 后的轻量动态颜色偏移校正。官方 AWB 继续负责通道增益；该级只
  // 按帧缓慢修正残余蓝黄/红绿偏移，不改变帧尺寸和像素时序。
  wire         cb_O_tlast;
  wire         cb_O_tuser;
  wire [95:0]  cb_O_tdata;
  wire         cb_O_tvalid;
  wire         cb_O_tready;

  // 暗光增强位于 AWB 之后、所有显示/检测模块之前。统计支路仍观察
  // demosaic 原始亮度，因此增强不会形成亮度反馈回路。
  wire         ll_O_tlast;
  wire         ll_O_tuser;
  wire [95:0]  ll_O_tdata;
  wire         ll_O_tvalid;
  assign O_aruco_rgb=ll_O_tdata;
  assign O_aruco_valid=ll_O_tvalid;
  assign O_aruco_sof=ll_O_tuser;
  assign O_aruco_eol=ll_O_tlast;
  wire         ll_O_tready;

  wire         awb_O_tuser_128;  //synthesis keep 
  wire         awb_O_tvalid_128;  //synthesis keep 
  wire [127:0] awb_O_tdata_128;  //synthesis keep 

  wire         ua_O_tlast;  //synthesis keep
  wire         ua_O_tuser;  //synthesis keep
  wire [ 95:0] ua_O_tdata;  //synthesis keep
  wire         ua_O_tvalid; //synthesis keep
  wire         ua_O_tready; //synthesis keep

  wire         mot_O_tlast;
  wire         mot_O_tuser;
  wire [ 95:0] mot_O_tdata;
  wire         mot_O_tvalid;
  wire         mot_O_tready;
  wire         mot_O_motion_valid;
  wire [15:0]  mot_O_motion_count;
  wire         mot_O_sample_valid;
  wire         mot_O_hand_sample_valid;
  wire         mot_O_hand_frame_done;
  wire         mot_O_hit;
  wire [9:0]   mot_O_x_grp, mot_O_y;
  wire         trk_O_track_valid;
  wire [3:0]   trk_O_obj_cnt;
   wire         trk_O_v0;  wire [10:0] trk_O_x0; wire [10:0] trk_O_y0; wire [1:0] trk_O_shape0;
   wire [10:0]  trk_O_xmin0, trk_O_xmax0, trk_O_ymin0, trk_O_ymax0;
   wire         trk_O_v1;  wire [10:0] trk_O_x1; wire [10:0] trk_O_y1; wire [1:0] trk_O_shape1;
   wire [10:0]  trk_O_xmin1, trk_O_xmax1, trk_O_ymin1, trk_O_ymax1;
   wire         trk_O_v2;  wire [10:0] trk_O_x2; wire [10:0] trk_O_y2; wire [1:0] trk_O_shape2;
   wire [10:0]  trk_O_xmin2, trk_O_xmax2, trk_O_ymin2, trk_O_ymax2;
  // The tracker also exposes a pass-through stream for stand-alone use.  The
  // main ISP consumes only its frame-end object records, so terminate that
  // optional stream explicitly instead of relying on omitted-port warnings.
  wire         trk_unused_tlast, trk_unused_tuser, trk_unused_tvalid;
  wire [95:0]  trk_unused_tdata;
  wire         trk_unused_tready;
  wire         dgt_O_valid;
  wire [3:0]   dgt_O_id;
  wire [7:0]   dgt_O_confidence;

  // 显示算法已与运动检测输入解耦，切换 mode 0..6 不应再重采背景；
  // 否则用户切换显示效果时，画面中的手可能被错误写成新背景。
  // 只有暗光 Gamma 档位改变时才重采一次，避免全局亮度阶跃被误判为运动。
  wire background_restart_req;

  // [边界对齐] 官方 AWB 的 O_tuser 与 O_tvalid 不同拍。先锁存 AWB 的帧首事件，再把
  // 帧首脉冲附着到下一拍真实有效数据；不要依赖 AWB 内部固定流水拍数，
  // 否则上游 valid 出现气泡时会重新错位。
  reg awb_frame_pending;
  always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
      if (!I_rst_n) begin
          awb_frame_pending <= 1'b0;
      end else begin
          if (awb_O_tuser)
              awb_frame_pending <= 1'b1;
          if (awb_O_tvalid && (awb_frame_pending || awb_O_tuser))
              awb_frame_pending <= 1'b0;
      end
  end
  wire ua_I_tuser_aligned = awb_O_tvalid &&
                            (awb_frame_pending || awb_O_tuser);

  // [输出旁带对齐] 主视频数据在末端经过 96->128 打包：4 个 96-bit
  // 输入拍产生 3 个 128-bit 输出拍。帧首必须直接使用官方打包器给出的
  // O_128b_frame_start：video_in 会据此在首个 128-bit 数据写入前复位 FIFO。
  // 若把帧首推迟到首个 valid 同拍，FIFO 会丢掉非 24-bit 整数倍的数据，
  // 同时造成水平回卷和 RGB 字节轮转。tlast 仍按打包组末拍生成。
  reg [1:0] packed_in_count;
  reg       packed_tlast_r;
  always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
      if (!I_rst_n) begin
          packed_in_count     <= 2'd0;
          packed_tlast_r      <= 1'b0;
      end else begin
          packed_tlast_r <= 1'b0;
          if (!ua_O_tvalid) begin
              // 与 data_96bit_to_128bit 的 S_cnt 行为保持一致：
              // valid 气泡结束当前 4 拍打包组。
              packed_in_count <= 2'd0;
          end else begin
              if (packed_in_count == 2'd3) begin
                  packed_tlast_r  <= ua_O_tlast;
                  packed_in_count  <= 2'd0;
              end else begin
                  packed_in_count  <= packed_in_count + 1'b1;
              end
          end
      end
  end

  assign O_tdata  = awb_O_tdata_128;
  assign O_tlast  = packed_tlast_r;
  assign O_tuser  = awb_O_tuser_128;
  assign O_tvalid = awb_O_tvalid_128   ;
  assign O_motion_valid = mot_O_motion_valid;
  assign O_motion_count = mot_O_motion_count;
  assign O_track_valid  = trk_O_track_valid;
  assign O_obj_cnt      = trk_O_obj_cnt;
   assign O_t0_v         = trk_O_v0;  assign O_t0_x = trk_O_x0; assign O_t0_y = trk_O_y0; assign O_t0_shape = trk_O_shape0;
   assign O_t0_xmin      = trk_O_xmin0; assign O_t0_xmax = trk_O_xmax0; assign O_t0_ymin = trk_O_ymin0; assign O_t0_ymax = trk_O_ymax0;
   assign O_t1_v         = trk_O_v1;  assign O_t1_x = trk_O_x1; assign O_t1_y = trk_O_y1; assign O_t1_shape = trk_O_shape1;
   assign O_t1_xmin      = trk_O_xmin1; assign O_t1_xmax = trk_O_xmax1; assign O_t1_ymin = trk_O_ymin1; assign O_t1_ymax = trk_O_ymax1;
   assign O_t2_v         = trk_O_v2;  assign O_t2_x = trk_O_x2; assign O_t2_y = trk_O_y2; assign O_t2_shape = trk_O_shape2;
   assign O_t2_xmin      = trk_O_xmin2; assign O_t2_xmax = trk_O_xmax2; assign O_t2_ymin = trk_O_ymin2; assign O_t2_ymax = trk_O_ymax2;
  assign O_digit_valid   = dgt_O_valid;
  assign O_digit_id      = dgt_O_id;
  assign O_digit_confidence = dgt_O_confidence;

  // [自动曝光取样点] AE statistics deliberately tap the demosaic output before AWB and before
  // the selectable user algorithm.  The AWB colour loop and Sobel/binary/
  // cartoon modes therefore cannot perturb the brightness feedback loop.
  generate
  if (ENABLE_STATS != 0) begin : gen_stats
  ua_luma_stats #(
      .IMG_WIDTH (IMG_WIDTH),
      .IMG_HEIGHT(IMG_HEIGHT)
      ,.HIGHLIGHT_ENABLE(BRIGHTNESS_RUNTIME_CONTROL)
      ,.REFLECTION_TOLERANT(BRIGHTNESS_RUNTIME_CONTROL)
      ,.REFLECTION_CEILING(8'd96)
  ) u_ua_luma_stats (
      .I_clk          (axi4s_video_aclk),
      .I_rst_n        (I_rst_n),
      .I_tlast        (m_aixs_tlast),
      .I_tuser        (m_aixs_tuser),
      .I_tdata        (m_aixs_tdata_96),
      .I_tvalid       (m_aixs_tvalid),
      .O_luma_mean    (O_ae_luma),
      .O_frame_toggle (O_ae_luma_toggle),
      .O_highlight    (O_ae_highlight)
  );
  end else begin : gen_no_stats
      assign O_ae_luma = 8'd128;
      assign O_ae_luma_toggle = 1'b0;
      assign O_ae_highlight = 2'd0;
  end
  endgenerate

  // ---- 自适应暗光 Gamma ----
  // 三级状态只在完成一帧亮度统计时改变，并带迟滞，避免均值在门限附近
  // 抖动造成整幅画面明暗闪烁。0=直通，1=中等提亮，2=强提亮。
  reg       ae_luma_toggle_d;
  reg [1:0] lowlight_strength;
  reg [1:0] lowlight_strength_d;
  // These inputs are an acknowledged bundled-data mailbox from the 24MHz
  // controller. Top holds them until this CSI domain acknowledges the packet.
  wire [1:0] applied_strength = (BRIGHTNESS_RUNTIME_CONTROL != 0) ?
      (!I_brightness_enable ? 2'd0 : (I_gain_index>=5'd24) ? 2'd2 :
       (I_gain_index>=5'd20) ? 2'd1 : 2'd0) : lowlight_strength;
  always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
      if (!I_rst_n) begin
          ae_luma_toggle_d <= 1'b0;
          lowlight_strength <= 2'd2;
          lowlight_strength_d <= 2'd2;
      end else begin
          ae_luma_toggle_d <= O_ae_luma_toggle;
          lowlight_strength_d <= lowlight_strength;
          if (O_ae_luma_toggle != ae_luma_toggle_d) begin
              case (lowlight_strength)
                  2'd2: begin
                      if (O_ae_luma >= 8'd104)
                          lowlight_strength <= 2'd0;
                      else if (O_ae_luma >= 8'd64)
                          lowlight_strength <= 2'd1;
                  end
                  2'd1: begin
                      if (O_ae_luma < 8'd48)
                          lowlight_strength <= 2'd2;
                      else if (O_ae_luma >= 8'd104)
                          lowlight_strength <= 2'd0;
                  end
                  default: begin
                      if (O_ae_luma < 8'd40)
                          lowlight_strength <= 2'd2;
                      else if (O_ae_luma < 8'd88)
                          lowlight_strength <= 2'd1;
                  end
              endcase
          end
      end
  end
  assign background_restart_req = (ENABLE_LOWLIGHT_ENHANCE != 0) &&
                                  (lowlight_strength != lowlight_strength_d);

  // 连续、单调的分段暗部提升。各 RGB 通道使用相同曲线，不做固定偏色；
  // 只使用移位、加法、比较器，并在 255 处饱和。旧曲线在 128..191 使用
  // c/2+96，把这段亮度的斜率压成 1/2，直通模式也会因此发灰；这里改为
  // 保留斜率的阴影提升：暗部乘 1.5/2，中高亮度只加固定偏置。
  function [7:0] F_lowlight_channel;
      input [7:0] c;
      input [1:0] strength;
      reg [9:0] value;
      begin
          if (strength == 2'd0) begin
              value = {2'b00, c};
          end else if (strength == 2'd2) begin
              if (c < 8'd32)
                  value = {1'b0, c, 1'b0};
              else
                  value = {2'b00, c} + 10'd32;
          end else begin
              if (c < 8'd64)
                  value = {2'b00, c} + {3'b000, c[7:1]};
              else
                  value = {2'b00, c} + 10'd32;
          end
          if (value > 10'd255)
              F_lowlight_channel = 8'hff;
          else
              F_lowlight_channel = value[7:0];
      end
  endfunction

  function [23:0] F_lowlight_pixel;
      input [23:0] p;
      input [1:0] strength;
      begin
          F_lowlight_pixel = {
              F_lowlight_channel(p[23:16], strength),
              F_lowlight_channel(p[15:8], strength),
              F_lowlight_channel(p[7:0], strength)
          };
      end
  endfunction

  // 暗光模式的轻量对比度塑形：0..63 原样通过，保住提亮后的暗部层次；
  // 64..159 逐步增加对比度；160 以上用柔和肩部压缩高光。旧的
  // 1.25*c-24 曲线会把低于约 20 的值直接压成黑色，抵消前级暗部提升。
  // 三个通道共用完全相同的单调曲线，不引入额外色偏；仅含移位、加法、
  // 比较器和饱和器，不使用 DSP 或帧 RAM。
  function [7:0] F_contrast_channel;
      input [7:0] c;
      reg [7:0] delta;
      reg [9:0] value;
      begin
          if (c < 8'd64) begin
              value = {2'b00,c};
          end else if (c < 8'd160) begin
              delta = c - 8'd64;
              value = {2'b00,c} + {2'b00,delta[7:2]};
          end else begin
              delta = c - 8'd160;
              value = 10'd184 + {2'b00,delta} - {4'b0000,delta[7:2]};
          end
          F_contrast_channel = (value > 10'd255) ? 8'hff : value[7:0];
      end
  endfunction

  function [23:0] F_contrast_pixel;
      input [23:0] p;
      begin
          F_contrast_pixel = {F_contrast_channel(p[23:16]),
                              F_contrast_channel(p[15:8]),
                              F_contrast_channel(p[7:0])};
      end
  endfunction

  function [23:0] F_picture_pixel;
      input [23:0] p;
      input [1:0] strength;
      reg [23:0] lifted;
      begin
          lifted = F_lowlight_pixel(p, strength);
          F_picture_pixel = (ENABLE_CONTRAST_ENHANCE != 0) ?
                            F_contrast_pixel(lifted) : lifted;
      end
  endfunction

  generate
  if ((ENABLE_LOWLIGHT_ENHANCE != 0) || (ENABLE_CONTRAST_ENHANCE != 0)) begin : gen_lowlight_enhance
      ua_photo_finish_96 #(.IMG_WIDTH(IMG_WIDTH),
                            .TONE_ENABLE(PHOTO_TONE_ENABLE),
                            .RUNTIME_STRENGTH(BRIGHTNESS_RUNTIME_CONTROL),
                            .HIGHLIGHT_SAFE_LIFT(BRIGHTNESS_RUNTIME_CONTROL),
                            .SHADOW_COLOR_DENOISE(1),
                            .COLOR_RESTORE(0), // v75: withdraw uncalibrated v74 compensation.
                            .GENTLE_SHADOW_LIFT(1),
                            .SELECTIVE_SHADOW_BOOST(1),
                            .INPUT_BITS(AWB_CHANNEL_BITS)) u_photo_finish (
          .I_clk(axi4s_video_aclk),.I_rst_n(I_rst_n),
          .I_tlast(cb_O_tlast),.I_tuser(cb_O_tuser),
          .I_tdata(awb_wide_data),.I_tvalid(cb_O_tvalid),
          .I_strength((ENABLE_LOWLIGHT_ENHANCE != 0)?applied_strength:2'd0),
          .O_tlast(ll_O_tlast),.O_tuser(ll_O_tuser),
          .O_tdata(ll_O_tdata),.O_tvalid(ll_O_tvalid)
      );
  end else begin : gen_no_lowlight_enhance
      assign ll_O_tlast  = cb_O_tlast;
      assign ll_O_tuser  = cb_O_tuser;
      assign ll_O_tdata  = cb_O_tdata;
      assign ll_O_tvalid = cb_O_tvalid;
  end
  endgenerate
  assign ll_O_tready = mot_O_tready;
  
  //assign m_aixs_tready = O_tready;
  //assign O_tdata  = m_aixs_tdata;
  //assign O_tlast  = m_aixs_tlast    ;
  //assign O_tuser  = m_aixs_tuser    ;
  //assign O_tvalid = m_aixs_tvalid   ;
 
 
wire [39:0] corrected_raw;
ua_raw_black_40 #(.BLACK_LEVEL(RAW_BLACK_LEVEL)) u_raw_black (
    .I_raw(I_tdata), .O_raw(corrected_raw));

// Production recovery: retain the board-validated v11 demosaic chain.
// ua_demosaic_border remains an offline experiment, not the active camera ISP.
demosaic #(
    .IMG_HEIGHT          (IMG_HEIGHT),
    .IMG_WIDTH           (IMG_WIDTH),
    .data_complete_delay (50  ),
    .BAYER_MODE          ("BGGR")
)
u_demosaic
(
    .I_clk   			(axi4s_video_aclk)	,   // 时钟信号
    .I_rst_n 			(I_rst_n)	,   // 复位信号，低有效
    .axi4s_video_tdata 	(corrected_raw)	,  // RAW black corrected before demosaic
    .axi4s_video_tdest 	(I_tdest)	,
    .axi4s_video_tlast 	(I_tlast)	,  // 行结束信号
    .axi4s_video_tvalid	(I_tvalid)	,  // 数据有效信号
    .axi4s_video_tuser 	(I_tuser)	,  // 帧开始信号
    .axi4s_video_tready	(I_tready)	,  // 从模块准备好接受数据
    .O_tlast  			(m_aixs_tlast)	,  // 输出行结束信号
    .O_tuser  			(m_aixs_tuser)	,  // 输出帧开始信号
    .O_tdata  			(m_aixs_tdata)	,  // 输出数据
    .O_tvalid 			(m_aixs_tvalid)	,  // 输出数据有效信号
    .O_tready   		(m_aixs_tready)	   // 输出数据准备好信号
);
 
data128_96 u_data128_96 (
    .I_tdata(m_aixs_tdata),
    .O_tdata(m_aixs_tdata_96)
);

ua_awb_frame #(
    .IMG_HEIGHT(IMG_HEIGHT),
    .IMG_WIDTH (IMG_WIDTH),
    .OUTPUT_CHANNEL_BITS(AWB_CHANNEL_BITS),
    .RUNTIME_CONTROL(AWB_RUNTIME_CONTROL)
) u_awb (
    .I_clk   (axi4s_video_aclk),
    .I_enable(I_awb_enable),
    .O_status(O_awb_status),
    .I_rst_n (I_rst_n),
    .I_tlast (m_aixs_tlast),
    .I_tuser (m_aixs_tuser),
    .I_tdata (m_aixs_tdata_96),
    .I_tvalid(m_aixs_tvalid),
    .I_tready(m_aixs_tready),
    .O_tlast (awb_O_tlast ),
    .O_tuser (awb_O_tuser ),
    .O_tdata (awb_wide_data ),
    .O_tvalid(awb_O_tvalid),
    .O_tready(cb_O_tready)
);

// stage only observes the AWB output and applies a bounded frame-to-frame
// residual offset, so it adds no frame memory and remains compatible with the
// existing 96-bit stream/tuser alignment.
ua_color_balance_compat #(
    .IMG_WIDTH (IMG_WIDTH),
    .IMG_HEIGHT(IMG_HEIGHT),
    .ENABLE    (0) // AWB alone: whole-scene additive offsets lift black and bias coloured scenes.
) u_ua_color_balance (
    .I_clk    (axi4s_video_aclk),
    .I_rst_n  (I_rst_n),
    .I_tlast  (awb_O_tlast),
    .I_tuser  (ua_I_tuser_aligned),
    .I_tdata  (awb_O_tdata),
    .I_tvalid (awb_O_tvalid),
    .I_tready (cb_O_tready),
    .O_tlast  (cb_O_tlast),
    .O_tuser  (cb_O_tuser),
    .O_tdata  (cb_O_tdata),
    .O_tvalid (cb_O_tvalid),
    .O_tready (ll_O_tready)
);

    // The display algorithm is deliberately downstream of motion detection.
    // Therefore selectable HDMI effects cannot corrupt the background model.
    generate
    if (ENABLE_ALGO != 0) begin : gen_algo
    ua_user_algo_96 #(
        .DARK_EDGE_ENABLE(1),
        .EDGE_DETAIL_ENABLE(1),
        .CART_EDGE_THRESHOLD(8'd8),
        .CART_EDGE_STRONG_THRESHOLD(8'd16),
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .BIN_THRESHOLD(8'd128)
    ) u_ua_user_algo (
        .I_clk   (axi4s_video_aclk),
        .I_rst_n (I_rst_n),
        .I_tlast (mot_O_tlast),
        .I_tuser (mot_O_tuser),
        .I_tdata (mot_O_tdata),
        .I_tvalid(mot_O_tvalid),
        .I_mode  (I_algo_mode),
        .I_tready(O_tready),
        .O_tlast (ua_O_tlast),
        .O_tuser (ua_O_tuser),
        .O_tdata (ua_O_tdata),
        .O_tvalid(ua_O_tvalid),
        .O_tready(ua_O_tready)
    );
    end else begin : gen_no_algo
        assign ua_O_tlast  = mot_O_tlast;
        assign ua_O_tuser  = mot_O_tuser;
        assign ua_O_tdata  = mot_O_tdata;
        assign ua_O_tvalid = mot_O_tvalid;
        assign ua_O_tready = O_tready;
    end
    endgenerate

    // Motion detection owns the reference-frame RAM and taps enhanced RGB before
    // any selectable display effect. Its registered passthrough feeds the
    // display algorithm. Low-light enhancement adds one registered stream stage;
    // its data, valid, line-end and aligned frame-start advance together.
    generate
    if (ENABLE_MOTION != 0) begin : gen_motion
    ua_motion_detect #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .IMG_W_GRP (IMG_WIDTH >> 2),
        .IMG_H_GRP (IMG_HEIGHT),
        .Y_DOWNSAMPLE((ENABLE_HAND != 0) ? 4 : 2),
        // Hand localization must inspect the whole frame.  Without the hand
        // feature, retain the cheaper central reference RAM configuration.
        .ROI_ENABLE((ENABLE_HAND != 0) ? 0 : 1),
        .ROI_X0_GRP(MOTION_ROI_X0_GRP),
        .ROI_X1_GRP(MOTION_ROI_X1_GRP),
        .ROI_Y0(MOTION_ROI_Y0),
        .ROI_Y1(MOTION_ROI_Y1),
        .THRESHOLD(8'd24),
        .LOW_LIGHT_LEVEL(8'd96),
        .LOW_LIGHT_THRESHOLD(8'd16),
        .HOLD_BACKGROUND_ON_MOTION(ENABLE_MOTION_OVERLAY ? 0 : 1)
    ) u_ua_motion (
        .I_clk    (axi4s_video_aclk),
        .I_rst_n  (I_rst_n),
        .I_tlast  (ll_O_tlast),
        .I_tuser  (ll_O_tuser),
        .I_tdata  (ll_O_tdata),
        .I_tvalid (ll_O_tvalid),
        .I_tready (ua_O_tready),
        .I_background_restart(background_restart_req),
        .O_tlast  (mot_O_tlast),
        .O_tuser  (mot_O_tuser),
        .O_tdata  (mot_O_tdata),
        .O_tvalid (mot_O_tvalid),
        .O_tready (mot_O_tready),
        .O_motion_sample_valid(mot_O_sample_valid),
        .O_hand_sample_valid(mot_O_hand_sample_valid),
        .O_hand_frame_done(mot_O_hand_frame_done),
        .O_motion_hit(mot_O_hit),
        .O_motion_x_grp(mot_O_x_grp),
        .O_motion_y(mot_O_y),
        .O_motion_valid(mot_O_motion_valid),
        .O_motion_count(mot_O_motion_count)
    );
    if(ENABLE_MOTION_OVERLAY)begin:gen_grid
      ua_motion_grid #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT)) u_grid(
       .clk(axi4s_video_aclk),.rst_n(I_rst_n),
       .sample_valid(mot_O_hand_sample_valid),.hit(mot_O_hit),
       .frame_done(mot_O_hand_frame_done),.camera_step(I_camera_step),
       .x_grp(mot_O_x_grp),.y(mot_O_y),
       .result_valid(O_motion_view_valid),.result(O_motion_view));
    end else begin:gen_no_grid
      assign O_motion_view_valid=1'b0;assign O_motion_view=53'd0;
    end
    end else begin : gen_no_motion
        assign O_motion_view_valid=1'b0;assign O_motion_view=53'd0;
        assign mot_O_tlast  = ll_O_tlast;
        assign mot_O_tuser  = ll_O_tuser;
        assign mot_O_tdata  = ll_O_tdata;
        assign mot_O_tvalid = ll_O_tvalid;
        assign mot_O_tready = ua_O_tready;
        assign mot_O_motion_valid = 1'b0;
        assign mot_O_motion_count = 16'd0;
        assign mot_O_sample_valid = 1'b0;
        assign mot_O_hand_sample_valid = 1'b0;
        assign mot_O_hand_frame_done = 1'b0;
        assign mot_O_hit = 1'b0;
        assign mot_O_x_grp = 10'd0;
        assign mot_O_y = 10'd0;
    end
    endgenerate

    generate
    if ((ENABLE_HAND == 2 || ENABLE_HAND == 3) && ENABLE_MOTION != 0) begin : gen_hand_native
        wire[7:0] native_x,native_w;
        wire[6:0] native_y,native_h;
        wire[8:0] native_right={1'b0,native_x}+{1'b0,native_w};
        wire[7:0] native_bottom={1'b0,native_y}+{1'b0,native_h};
        wire[10:0] source_bottom=({3'd0,native_bottom}<<3)+11'd2;
        if (ENABLE_HAND == 3) begin : gen_binary
        ua_hand_binary_native #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT)) u_hand(
            .I_clk(axi4s_video_aclk),.I_rst_n(I_rst_n),.I_clear(1'b0),
            .I_sample_valid(mot_O_hand_sample_valid),.I_frame_done(mot_O_hand_frame_done),
            .I_x_grp(mot_O_x_grp),.I_y(mot_O_y),.I_rgb(mot_O_tdata),
            .O_result_valid(O_hand_valid),.O_id(O_hand_id),.O_raw(),.O_tips(O_hand_tip_count),.O_box_valid(O_hand_box_valid),
            .O_x(native_x),.O_width(native_w),.O_y(native_y),.O_height(native_h),.O_fault(),.O_drop(),.O_cycles());
        end else begin : gen_three_class
        ua_hand_native_classifier #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT)) u_hand(
            .I_clk(axi4s_video_aclk),.I_rst_n(I_rst_n),.I_clear(1'b0),
            .I_sample_valid(mot_O_hand_sample_valid),.I_frame_done(mot_O_hand_frame_done),
            .I_x_grp(mot_O_x_grp),.I_y(mot_O_y),.I_rgb(mot_O_tdata),
            .O_result_valid(O_hand_valid),.O_id(O_hand_id),.O_raw(),.O_tips(O_hand_tip_count),.O_box_valid(O_hand_box_valid),
            .O_x(native_x),.O_width(native_w),.O_y(native_y),.O_height(native_h),.O_fault(),.O_drop(),.O_cycles());
        end
        // OSD horizontal coordinates are four-pixel groups, vertical pixels.
        assign O_hand_xmin={1'b0,native_x,1'b0};
        assign O_hand_xmax={native_right,1'b0}-10'd1;
        assign O_hand_ymin=({3'd0,native_y}<<3)+10'd3;
        assign O_hand_ymax=source_bottom>719 ? 10'd719 : source_bottom[9:0];
    end else if (ENABLE_HAND != 0 && ENABLE_MOTION != 0) begin : gen_hand
        ua_hand_profile #(.IMG_WIDTH(IMG_WIDTH), .IMG_HEIGHT(IMG_HEIGHT),
                          .DYNAMIC_ROI(1), .SAMPLE_STEP(4),
                          .MIN_AREA(100), .MAX_AREA(10000),
                          .LOC_MIN_AREA(160),
                          .LOC_BAND_HYSTERESIS(1), .FINGER_GAP_SCALE(4),
                          .CLASS_SWITCH_FRAMES(6),
                          .MOTION_GATE_ENABLE(0)) u_hand (
            .I_clk(axi4s_video_aclk), .I_rst_n(I_rst_n),
            // Background-free hand detection must not reset every time AE
            // changes the enhancement tier. Motion RAM still restarts above.
            .I_clear(1'b0),
            .I_sample_valid(mot_O_hand_sample_valid), .I_motion_hit(mot_O_hit),
            .I_x_grp(mot_O_x_grp), .I_y(mot_O_y), .I_rgb(mot_O_tdata),
            .I_frame_done(mot_O_hand_frame_done),
            .O_result_valid(O_hand_valid), .O_id(O_hand_id),
            .O_tip_count(O_hand_tip_count),
            .O_box_valid(O_hand_box_valid),
            .O_box_xmin(O_hand_xmin), .O_box_xmax(O_hand_xmax),
            .O_box_ymin(O_hand_ymin), .O_box_ymax(O_hand_ymax)
        );
    end else begin : gen_no_hand
        assign O_hand_valid = 1'b0;
        assign O_hand_id = 2'd0;
        assign O_hand_tip_count = 3'd0;
        assign O_hand_box_valid = 1'b0;
        assign O_hand_xmin = 10'd0; assign O_hand_xmax = 10'd0;
        assign O_hand_ymin = 10'd0; assign O_hand_ymax = 10'd0;
    end
    endgenerate

    generate
    if (ENABLE_TRACK != 0) begin : gen_track
    ua_track_detect #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .IMG_W_GRP (IMG_WIDTH >> 2),
        .IMG_H_GRP (IMG_HEIGHT),
        // 暗光提升仍保留颜色对比；保留 V/chroma 和主色差门限，避免近灰噪声
        // 被判成颜色目标。填充率和跨帧保持继续抑制稀疏噪点造成的跳框。
        .VALUE_MIN       (8'd40),
        .CHROMA_MIN      (8'd24),
        .DOMINANCE_MIN   (8'd4),
        .MIN_AREA_G      (18'd48),
        .LOSS_HOLD_FRAMES(2'd2),
        .FAST_TRACK_ENABLE(0),.FAST_TRACK_PIXELS(8)
    ) u_ua_track (
        .I_clk    (axi4s_video_aclk),
        .I_rst_n  (I_rst_n),
        .I_tlast  (ll_O_tlast),
        .I_tuser  (ll_O_tuser),
        .I_tdata  (ll_O_tdata),
        .I_tvalid (ll_O_tvalid),
        .I_tready (1'b1),
        .O_tlast  (trk_unused_tlast),
        .O_tuser  (trk_unused_tuser),
        .O_tdata  (trk_unused_tdata),
        .O_tvalid (trk_unused_tvalid),
        .O_tready (trk_unused_tready),
        .O_track_valid(trk_O_track_valid),
        .O_obj_cnt    (trk_O_obj_cnt),
         .O_v0         (trk_O_v0), .O_x0(trk_O_x0), .O_y0(trk_O_y0), .O_shape0(trk_O_shape0),
         .O_xmin0      (trk_O_xmin0), .O_xmax0(trk_O_xmax0), .O_ymin0(trk_O_ymin0), .O_ymax0(trk_O_ymax0),
         .O_v1         (trk_O_v1), .O_x1(trk_O_x1), .O_y1(trk_O_y1), .O_shape1(trk_O_shape1),
         .O_xmin1      (trk_O_xmin1), .O_xmax1(trk_O_xmax1), .O_ymin1(trk_O_ymin1), .O_ymax1(trk_O_ymax1),
         .O_v2         (trk_O_v2), .O_x2(trk_O_x2), .O_y2(trk_O_y2), .O_shape2(trk_O_shape2),
         .O_xmin2      (trk_O_xmin2), .O_xmax2(trk_O_xmax2), .O_ymin2(trk_O_ymin2), .O_ymax2(trk_O_ymax2)
    );
    end else begin : gen_no_track
        assign trk_O_track_valid = 1'b0;
        assign trk_O_obj_cnt = 4'd0;
        assign trk_O_v0 = 1'b0; assign trk_O_x0 = 11'd0; assign trk_O_y0 = 11'd0; assign trk_O_shape0 = 2'd3;
        assign trk_O_xmin0 = 11'd0; assign trk_O_xmax0 = 11'd0; assign trk_O_ymin0 = 11'd0; assign trk_O_ymax0 = 11'd0;
        assign trk_O_v1 = 1'b0; assign trk_O_x1 = 11'd0; assign trk_O_y1 = 11'd0; assign trk_O_shape1 = 2'd3;
        assign trk_O_xmin1 = 11'd0; assign trk_O_xmax1 = 11'd0; assign trk_O_ymin1 = 11'd0; assign trk_O_ymax1 = 11'd0;
        assign trk_O_v2 = 1'b0; assign trk_O_x2 = 11'd0; assign trk_O_y2 = 11'd0; assign trk_O_shape2 = 2'd3;
        assign trk_O_xmin2 = 11'd0; assign trk_O_xmax2 = 11'd0; assign trk_O_ymin2 = 11'd0; assign trk_O_ymax2 = 11'd0;
    end
    endgenerate

    // 数字识别旁路挂在 AWB+Gamma 后的 RGB 流上。它只读取数据、不参与主视频
    // ready 链；tuser 使用与用户算法相同的对齐帧首，避免 AWB 内部流水
    // 造成首拍错位。外框/网格坐标固定为 1280x720 版本的产品位置。
    generate
    if (ENABLE_DIGIT != 0) begin : gen_digit
    ua_digit_recognizer #(
        .AUTO_FIND(1),
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .OUTER_X0  (496), .OUTER_Y0 (168), .OUTER_W (288), .OUTER_H (384),
        .INNER_X0  (520), .INNER_Y0 (192), .INNER_W (240), .INNER_H (336),
        .CELL_W    (48),  .CELL_H   (48),
        .CELL_GROUPS_PER_CELL(12), .CELL_HEIGHT(48),
        .BG_OFFSET (32), .CELL_MIN (72), .MIN_MARGIN (2)
    ) u_ua_digit_recognizer (
        .I_clk             (axi4s_video_aclk),
        .I_rst_n           (I_rst_n),
        .I_tlast           (ll_O_tlast),
        .I_tuser           (ll_O_tuser),
        .I_tdata           (ll_O_tdata),
        .I_tvalid          (ll_O_tvalid),
        .O_digit_valid     (dgt_O_valid),
        .O_digit_id        (dgt_O_id),
        .O_digit_confidence(dgt_O_confidence),
        .O_result_event(O_digit_view_valid),.O_result_view(O_digit_view)
    );
    end else begin : gen_no_digit
        assign O_digit_view_valid=1'b0;assign O_digit_view=57'd0;
        assign dgt_O_valid = 1'b0;
        assign dgt_O_id = 4'hf;
        assign dgt_O_confidence = 8'd0;
    end
    endgenerate

    data_96bit_to_128bit u_data_96bit_to_128bit(
        .I_clk              ( axi4s_video_aclk  ),
        .I_rst_n            ( I_rst_n           ),
	
        // Keep the official early frame marker.  AWB intentionally exposes
        // tuser well before its delayed valid/data path, allowing video_in's
        // stretched FIFO reset to finish before processed pixels arrive.
        .I_96b_frame_start  ( awb_O_tuser	    ),
        .I_96b_valid        ( ua_O_tvalid 		),
        .I_96b_data         ( ua_O_tdata		),
	
        .O_128b_frame_start ( awb_O_tuser_128  	),
        .O_128b_valid       ( awb_O_tvalid_128 	),
        .O_128b_data        ( awb_O_tdata_128  	)
    );



//data96_128 u_data96_128 (
//    .I_tdata(awb_O_tdata),
//    .O_tdata(awb_O_tdata_128)
//);
	
endmodule

// ============================================================================
// TD stale-run compatibility copy of ua_color_balance.
//
// Older TD syn_1 manifests can omit a newly added standalone source file.  The
// active instance above therefore uses this uniquely named copy, which lives
// in the already-maintained isp_top_user.v source.  The standalone
// ua_color_balance.v remains in the project for clean projects and simulation;
// it is not instantiated here, so there is no duplicated hardware.
// ============================================================================
module ua_color_balance_compat #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    parameter ENABLE     = 1
)(
    input             I_clk,
    input             I_rst_n,
    input             I_tlast,
    input             I_tuser,
    input      [95:0] I_tdata,
    input             I_tvalid,
    output            I_tready,
    output            O_tlast,
    output            O_tuser,
    output     [95:0] O_tdata,
    output            O_tvalid,
    input             O_tready
);
    localparam integer SUM_W = 30;
    localparam integer AVG_SHIFT = 20;

    reg signed [SUM_W-1:0] sum_gr;
    reg signed [SUM_W-1:0] sum_gb;
    reg signed [5:0] offset_r;
    reg signed [5:0] offset_b;
    reg frame_seen;

    wire [7:0] r0 = I_tdata[95:88];
    wire [7:0] g0 = I_tdata[87:80];
    wire [7:0] b0 = I_tdata[79:72];
    wire [7:0] r1 = I_tdata[71:64];
    wire [7:0] g1 = I_tdata[63:56];
    wire [7:0] b1 = I_tdata[55:48];
    wire [7:0] r2 = I_tdata[47:40];
    wire [7:0] g2 = I_tdata[39:32];
    wire [7:0] b2 = I_tdata[31:24];
    wire [7:0] r3 = I_tdata[23:16];
    wire [7:0] g3 = I_tdata[15:8];
    wire [7:0] b3 = I_tdata[7:0];

    wire [9:0] beat_r = {2'b00,r0} + {2'b00,r1} +
                        {2'b00,r2} + {2'b00,r3};
    wire [9:0] beat_g = {2'b00,g0} + {2'b00,g1} +
                        {2'b00,g2} + {2'b00,g3};
    wire [9:0] beat_b = {2'b00,b0} + {2'b00,b1} +
                        {2'b00,b2} + {2'b00,b3};
    wire signed [11:0] beat_gr = $signed({2'b00,beat_g}) -
                                  $signed({2'b00,beat_r});
    wire signed [11:0] beat_gb = $signed({2'b00,beat_g}) -
                                  $signed({2'b00,beat_b});

    function [5:0] F_target;
        input signed [SUM_W-1:0] sum_value;
        reg signed [SUM_W-1:0] q;
        begin
            q = sum_value >>> AVG_SHIFT;
            if (q > 8)
                F_target = 6'sd8;
            else if (q < -8)
                F_target = -6'sd8;
            else
                F_target = q[5:0];
        end
    endfunction

    function [5:0] F_step;
        input signed [5:0] current_value;
        input signed [5:0] target_value;
        reg signed [6:0] c;
        reg signed [6:0] t;
        begin
            c = current_value;
            t = target_value;
            if (t > c + 1)
                F_step = current_value + 1'b1;
            else if (t < c - 1)
                F_step = current_value - 1'b1;
            else
                F_step = target_value;
        end
    endfunction

    function [7:0] F_add_offset;
        input [7:0] c;
        input signed [5:0] offset;
        reg signed [9:0] value;
        begin
            value = $signed({2'b00,c}) + $signed({{4{offset[5]}},offset});
            if (value[9])
                F_add_offset = 8'd0;
            else if (value[8])
                F_add_offset = 8'hff;
            else
                F_add_offset = value[7:0];
        end
    endfunction

    function [23:0] F_apply_pixel;
        input [23:0] p;
        input signed [5:0] r_offset;
        input signed [5:0] b_offset;
        begin
            F_apply_pixel = {F_add_offset(p[23:16], r_offset),
                             p[15:8],
                             F_add_offset(p[7:0], b_offset)};
        end
    endfunction

    assign I_tready = O_tready;
    assign O_tlast  = I_tlast;
    assign O_tuser  = I_tuser;
    assign O_tvalid = I_tvalid;
    assign O_tdata  = (ENABLE == 0) ? I_tdata : {
        F_apply_pixel(I_tdata[95:72], offset_r, offset_b),
        F_apply_pixel(I_tdata[71:48], offset_r, offset_b),
        F_apply_pixel(I_tdata[47:24], offset_r, offset_b),
        F_apply_pixel(I_tdata[23:0],  offset_r, offset_b)
    };

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sum_gr     <= {SUM_W{1'b0}};
            sum_gb     <= {SUM_W{1'b0}};
            offset_r   <= 6'sd0;
            offset_b   <= 6'sd0;
            frame_seen <= 1'b0;
        end else if (ENABLE != 0) begin
            if (I_tvalid && I_tuser) begin
                if (frame_seen) begin
                    offset_r <= F_step(offset_r, F_target(sum_gr));
                    offset_b <= F_step(offset_b, F_target(sum_gb));
                end
                frame_seen <= 1'b1;
                sum_gr <= {{(SUM_W-12){beat_gr[11]}}, beat_gr};
                sum_gb <= {{(SUM_W-12){beat_gb[11]}}, beat_gb};
            end else if (I_tvalid) begin
                sum_gr <= sum_gr + {{(SUM_W-12){beat_gr[11]}}, beat_gr};
                sum_gb <= sum_gb + {{(SUM_W-12){beat_gb[11]}}, beat_gb};
            end
        end
    end
endmodule

// Textually include the AWB hierarchy from this already-registered source.
// This avoids a black box when TD regenerates syn_1 from a stale GUI file list.
// The standalone .al entries for these modules stay AutoExcluded to avoid
// duplicate definitions; the included RTL still elaborates as part of this
// translation unit.
`include "blk_mem_gen_awb_delay_signal_compact.v"
`include "signal_delay.v"
`include "ua_awb_frame.v"
`include "ua_photo_finish_96.v"
`include "ua_raw_black_40.v"
`include "ua_demosaic_border.v"
