// ============================================================================
// hdmi_mixer_user : 显示端的像素混合器和 OSD 字符绘制器。
// I_video_de=1 时，每拍对应一个有效屏幕像素：普通区域透传视频，命中 Logo/
// 字符/标记区域则输出叠加颜色。它不重新计算图像算法。
// 输入统计已由顶层同步到 HDMI 域；本模块在帧边界采样，使一帧内文字保持稳定。
// ============================================================================
module hdmi_mixer_v35_reference #(
    parameter H_OFFSET = 128,
    parameter V_OFFSET = 60,
    parameter IMG_WIDTH = 1280,
    parameter IMG_HEIGHT = 720,
    parameter integer DEBUG_MODE = 0,
    // 3/2 display-only gain.  It leaves sensor timing and all recognition
    // thresholds unchanged; black remains black and each channel saturates.
    parameter integer DISPLAY_BRIGHT_ENABLE = 1,
    // Current PLL clk4_out is 75 MHz.  Used only as the one-second reference
    // for the output FPS counter; video timing and pixel data are unchanged.
    parameter integer PIXEL_CLOCK_HZ = 75000000
)(
    input wire        I_clk,
    input wire        I_rst_n,

    input wire        I_video_vsync,
    input wire        I_video_hsync,
    input wire        I_video_de,
    input wire        I_video_user,
    input wire        I_video_last,

    input wire[3:0]   I_debug_status,
    input wire[2:0]   I_algo_mode,
    input wire[7:0]   I_cam_frame_cnt, // legacy interface, no longer used for latency
    input wire        I_latency_valid,
    input wire[15:0]  I_latency_ms,
    input wire        I_motion_valid,   // 运动检测帧末脉冲 (显示域同步后)
    input wire[15:0]  I_motion_count,   // 运动组数
    input wire        I_motion_enable,  // 拨动开关：运动检测显示/结果
    input wire        I_track_valid,    // 跟踪帧末脉冲 (显示域同步后)
    input wire[3:0]   I_track_cnt,      // 有效目标数
    input wire        I_track_enable,   // 拨动开关：颜色目标显示/结果
    input wire        I_t0_v,           // 红
    input wire[10:0]  I_t0_x, I_t0_y,
    input wire[1:0]   I_t0_shape,
    input wire[10:0]  I_t0_xmin, I_t0_xmax, I_t0_ymin, I_t0_ymax,
    input wire        I_t1_v,           // 绿
    input wire[10:0]  I_t1_x, I_t1_y,
    input wire[1:0]   I_t1_shape,
    input wire[10:0]  I_t1_xmin, I_t1_xmax, I_t1_ymin, I_t1_ymax,
    input wire        I_t2_v,           // 蓝
    input wire[10:0]  I_t2_x, I_t2_y,
    input wire[1:0]   I_t2_shape,
    input wire[10:0]  I_t2_xmin, I_t2_xmax, I_t2_ymin, I_t2_ymax,
    input wire        I_digit_valid,
    input wire[3:0]   I_digit_id,
    input wire[7:0]   I_digit_confidence,
    input wire        I_digit_enable,   // 拨动开关：数字显示/结果
    input wire        I_hand_valid,
    input wire[1:0]  I_hand_id,         // 0无手 1拳 2单指 3张手
    input wire[2:0]  I_hand_tips,
    input wire        I_hand_box_valid,
    input wire[9:0]  I_hand_xmin, I_hand_xmax, I_hand_ymin, I_hand_ymax,
    input wire        I_hand_enable,     // SW3
    input wire        I_aruco_enable,
    input wire        I_aruco_valid,
    input wire[11:0]  I_aruco_id_bcd,    // hundreds,tens,units
    input wire[21:0]  I_aruco_corner0,I_aruco_corner1,I_aruco_corner2,I_aruco_corner3,
    input wire[25:0]  I_aruco_edge0,I_aruco_edge1,I_aruco_edge2,I_aruco_edge3,

    output wire       O_video_rd_en,
    input wire[23:0]  I_video_rd_data,

    output reg        O_hdmi_vsync,
    output reg        O_hdmi_hsync,
    output reg        O_hdmi_de,
    output reg[23:0]  O_hdmi_data,
    output reg[23:0]  O_hdmi_clean_data
);

    reg        S_video_vsync_1d;
    reg        S_video_vsync_2d;
    reg        S_video_hsync_1d;
    reg        S_video_hsync_2d;
    reg        S_video_de_1d;
    reg        S_video_de_2d;
    reg [23:0] S_video_data_1d;
    reg [23:0] S_video_data_2d;
    // OSD 结果寄存边界。复杂字符/Logo 判定在这里结束，下一拍仅保留
    // 一个短的颜色选择器；同步信号和原视频一起延迟，保持像素对齐。
    reg        S_video_vsync_3d;
    reg        S_video_hsync_3d;
    reg        S_video_de_3d;
    reg [23:0] S_video_data_3d;
    reg [23:0] S_video_bright_3d;
    reg        S_osd_hit_3d;
    reg [23:0] S_osd_color_3d;
    // Logo 单独走一条命中/颜色通路，避免把大块 Logo ROM 的颜色总线
    // 串进动态文字颜色选择器；与 OSD 同拍锁存，输出仍保持像素对齐。
    reg        S_logo_hit_3d;
    reg [23:0] S_logo_color_3d;
    reg [11:0] S_x_3d;
    // video_out 的 FIFO 为 NOREG：读请求后下一拍由像素寄存器输出数据。
    // 当前 DE/HS/VS 走到 5d，O_hdmi_data 本身还要再经过一个寄存器；
    // 按这个固定时序，原视频应取 3d。取 4d 会额外晚一拍，导致行尾
    // 像素落入下一行，表现为“最右边跑到最左边”。
    reg        S_video_vsync_4d;
    reg        S_video_hsync_4d;
    reg        S_video_de_4d;
    reg [23:0] S_video_data_4d;
    reg        S_osd_hit_4d;
    reg [23:0] S_osd_color_4d;
    reg        S_logo_hit_4d;
    reg [23:0] S_logo_color_4d;
    reg [11:0] S_x_4d;
    reg        S_video_vsync_5d;
    reg        S_video_hsync_5d;
    reg        S_video_de_5d;
    reg [23:0] S_video_data_5d;
    reg        S_osd_hit_5d;
    reg [23:0] S_osd_color_5d;
    reg        S_logo_hit_5d;
    reg [23:0] S_logo_color_5d;
    reg [11:0] S_x_5d;
    reg [11:0] S_x;
    reg [11:0] S_y;

    function [7:0] F_bright_3_2;
        input [7:0] c;
        reg [8:0] sum;
        begin
            sum = {1'b0, c} + {2'b00, c[7:1]};
            F_bright_3_2 = sum[8] ? 8'hff : sum[7:0];
        end
    endfunction

    function [10:0] F_min4;
        input [10:0] a,b,c,d;
        reg [10:0] ab,cd;
        begin
            ab=(a<b)?a:b;cd=(c<d)?c:d;
            F_min4=(ab<cd)?ab:cd;
        end
    endfunction
    function [10:0] F_max4;
        input [10:0] a,b,c,d;
        reg [10:0] ab,cd;
        begin
            ab=(a>b)?a:b;cd=(c>d)?c:d;
            F_max4=(ab>cd)?ab:cd;
        end
    endfunction

    // The MCU publishes a Q10 line slope, half-pixel intercept and major-axis
    // flag for each refined corner pair. This avoids synthesizing four
    // variable dividers in the 75 MHz pixel path while preserving perspective.
    function F_aruco_line_hit;
        input [11:0] px,py;
        input [10:0] ax,ay,bx,by;
        input [25:0] equation;
        reg major_x;
        reg signed [11:0] slope;
        reg signed [12:0] intercept_q1;
        reg [11:0] major_coord,minor_coord,major_low,major_high;
        reg signed [23:0] product,base,minor_scaled,error;
        reg [23:0] error_abs;
        begin
            major_x=equation[25];
            slope=equation[11:0];
            intercept_q1=equation[24:12];
            if(major_x) begin
                major_coord=px;minor_coord=py;
                major_low=(ax<bx)?{1'b0,ax}:{1'b0,bx};
                major_high=(ax>bx)?{1'b0,ax}:{1'b0,bx};
            end else begin
                major_coord=py;minor_coord=px;
                major_low=(ay<by)?{1'b0,ay}:{1'b0,by};
                major_high=(ay>by)?{1'b0,ay}:{1'b0,by};
            end
            product=$signed({{12{slope[11]}},slope})*
                    $signed({12'd0,major_coord});
            base={{11{intercept_q1[12]}},intercept_q1};
            base=base<<<10;
            minor_scaled=$signed({12'd0,minor_coord});
            minor_scaled=minor_scaled<<<11;
            error=minor_scaled-((product<<<1)+base);
            error_abs=error[23]?(~error+24'd1):error;
            F_aruco_line_hit=(major_coord>=major_low)&&(major_coord<=major_high)&&
                              (error_abs<=24'd2048);
        end
    endfunction

    // 卡通模式已经在用户算法中完成清新色阶映射；再做 3/2 增益会把
    // B8/F8 等高色阶大量截成 FF，破坏色相。因此只对普通视频增亮，
    // 卡通模式保持量化后的原始色阶。
    wire [23:0] S_video_display_3d = (DISPLAY_BRIGHT_ENABLE && (I_algo_mode != 3'd6)) ?
        S_video_bright_3d : S_video_data_3d;
    reg [11:0] S_x_1d;
    reg [11:0] S_x_2d;
    reg [11:0] S_y_1d;
    reg [11:0] S_y_2d;
    reg        S_aruco_edge_hit_2d;

    reg        S_osd_hit;
    reg [23:0] S_osd_color;
    reg        S_logo_hit;
    reg [23:0] S_logo_color;
    reg [11:0] S_logo_x;
    reg [11:0] S_logo_y;
    reg [3:0]  S_char_idx;
    reg [2:0]  S_char_row;
    reg [2:0]  S_char_col;
    reg [4:0]  S_char_bits;
    reg        S_char_on;
    reg        S_logo_blue_on;
    reg        S_logo_red_on;
    reg [11:0] S_logo_tmp_y;
    reg [3:0]  S_logo_red_band;
    reg [11:0] S_logo_red_x_start;
    reg [11:0] S_logo_red_x_end;
    // Logo ROM 地址与 S_x_2d/S_y_2d 同拍。地址在坐标的 1d->2d
    // 流水边界上预先计算并寄存，切断“坐标算术 -> ROM -> OSD 大选择树”
    // 的组合关键路径。
    wire [14:0] S_logo_addr;
    wire[24:0] S_logo_pixel;
    wire S_logo_present;
    reg [31:0] S_frame_cnt;
    reg [11:0] S_dyn_x;
    reg [11:0] S_dyn_y;
    reg [3:0]  S_dyn_char;
    reg [2:0]  S_dyn_col;
    reg [2:0]  S_dyn_row;
    reg [4:0]  S_dyn_bits;
    reg        S_dyn_on;
    reg        S_digit_box_on;
    reg        S_hand_box_on;
    reg        S_aruco_box_on;
    reg        S_track_box_on;
    reg [23:0] S_track_box_color;
    reg [3:0]  S_dyn_digit_idx;
    reg [11:0] S_dyn_digit_x;
    reg [6:0]  S_dyn_seg;
    reg        S_digit_seg_on;
    reg [3:0]  S_cnt_d0;
    reg [3:0]  S_cnt_d1;
    reg [3:0]  S_cnt_d2;
    reg [3:0]  S_cnt_d3;
    reg [3:0]  S_cnt_d4;
    reg [3:0]  S_cnt_d5;
    reg [2:0]  S_lbl_row;
    reg [2:0]  S_lbl_col;
    reg [1:0]  S_lbl_idx;
    reg [4:0]  S_lbl_bits;
    reg [6:0]  S_lbl_local_x;
    reg [3:0]  S_dyn_dec_digit;
    reg [4:0]  S_cn_local_x;
    reg [4:0]  S_cn_local_y;
    reg [3:0]  S_cn_col;
    reg [3:0]  S_cn_row;
    reg [15:0] S_cn_row_bits;
    reg        S_cn_on;
    reg [9:0]  S_cn_scale_x;
    reg [9:0]  S_cn_scale_y;
    reg [7:0]  S_pf_char;
    reg [11:0] S_aruco_label_x,S_aruco_label_y;
    reg [4:0]  S_pf_local_x;
    reg [4:0]  S_pf_local_y;
    reg [3:0]  S_pf_col;
    reg [3:0]  S_pf_row;
    wire [15:0] S_pf_row_bits;
    reg        S_pf_on;
    reg S_font_active;
    reg S_font_active_3d;
    reg [3:0] S_font_col_3d;
    reg [9:0]  S_pf_scale_x;
    reg [9:0]  S_pf_scale_y;
    reg [7:0]  S_disp_frame_lsb;   // 显示帧计数低8位 (本模块已有 S_frame_cnt)
    // [数值转字符] 二进制延迟不能直接显示；帧首后分步得到百/十/个位，
    // 使 OSD 扫到第 152 行前已有可绘制的 ASCII 数字。
    reg [9:0] S_latency_remaining;
    reg [3:0] S_latency_h, S_latency_t, S_latency_u;
    reg S_latency_display_valid, S_latency_start_d;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_latency_start_d <= 0; S_latency_remaining <= 0;
            S_latency_h <= 0; S_latency_t <= 0; S_latency_u <= 0;
            S_latency_display_valid <= 0;
        end else begin
            S_latency_start_d <= I_video_user;
            // Monitor publishes at I_video_user; sample on the next clock.
            if (S_latency_start_d) begin
                S_latency_display_valid <= I_latency_valid && (I_latency_ms <= 16'd999);
                S_latency_remaining <= (I_latency_ms <= 16'd999) ? I_latency_ms[9:0] : 10'd0;
                S_latency_h <= 0; S_latency_t <= 0; S_latency_u <= 0;
            end else if (S_latency_remaining != 0) begin
                S_latency_remaining <= S_latency_remaining - 1'b1;
                if (S_latency_u == 9) begin
                    S_latency_u <= 0;
                    if (S_latency_t == 9) begin
                        S_latency_t <= 0; S_latency_h <= S_latency_h + 1'b1;
                    end else S_latency_t <= S_latency_t + 1'b1;
                end else S_latency_u <= S_latency_u + 1'b1;
            end
        end
    end

    // ---- HDMI output FPS monitor ----
    // Count frame-start pulses over one pixel-clock second.  The frame pulse
    // is already synchronous to I_clk, so no new clock-domain crossing is
    // introduced.  The result is saturated at 99 and held for the next OSD
    // second; it is a display diagnostic only and never gates the video path.
    reg [26:0] S_fps_ref_cnt;
    reg [3:0]  S_fps_window_units, S_fps_window_tens;
    reg [3:0]  S_fps_display_units, S_fps_display_tens;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_fps_ref_cnt       <= 27'd0;
            S_fps_window_units <= 4'd0;
            S_fps_window_tens  <= 4'd0;
            S_fps_display_units<= 4'd0;
            S_fps_display_tens <= 4'd0;
        end else if (S_fps_ref_cnt >= PIXEL_CLOCK_HZ - 1) begin
            // Include a frame whose pulse coincides with the one-second edge.
            if (I_video_user) begin
                if (S_fps_window_units == 4'd9) begin
                    S_fps_display_units <= 4'd0;
                    S_fps_display_tens <= (S_fps_window_tens >= 4'd9) ?
                                           4'd9 : (S_fps_window_tens + 4'd1);
                end else begin
                    S_fps_display_units <= S_fps_window_units + 4'd1;
                    S_fps_display_tens <= S_fps_window_tens;
                end
            end else begin
                S_fps_display_units <= S_fps_window_units;
                S_fps_display_tens <= S_fps_window_tens;
            end
            S_fps_ref_cnt       <= 27'd0;
            S_fps_window_units <= 4'd0;
            S_fps_window_tens  <= 4'd0;
        end else begin
            S_fps_ref_cnt <= S_fps_ref_cnt + 27'd1;
            if (I_video_user) begin
                if (S_fps_window_units == 4'd9) begin
                    S_fps_window_units <= 4'd0;
                    if (S_fps_window_tens < 4'd9)
                        S_fps_window_tens <= S_fps_window_tens + 4'd1;
                end else begin
                    S_fps_window_units <= S_fps_window_units + 4'd1;
                end
            end
        end
    end

    reg [15:0] S_motion_cnt_disp;  // 运动计数 (显示域锁存)
    // MOT 十进制显示转换器：帧末收到新计数后，在显示时钟域逐拍完成
    // 16 轮 double-dabble；S_motion_bcd_disp 只在转换完成时更新。
    reg [19:0] S_motion_bcd_disp;
    reg [19:0] S_motion_bcd_work;
    reg [15:0] S_motion_bin_work;
    reg [4:0]  S_motion_bcd_step_idx;
    reg        S_motion_bcd_busy;
    reg [3:0]  S_track_cnt_disp;   // 目标计数锁存
    reg        S_t0_v_disp;  reg [10:0] S_t0_x_disp; reg [10:0] S_t0_y_disp; reg [1:0] S_t0_sh_disp;
    reg [10:0] S_t0_xmin_disp, S_t0_xmax_disp, S_t0_ymin_disp, S_t0_ymax_disp;
    reg        S_t1_v_disp;  reg [10:0] S_t1_x_disp; reg [10:0] S_t1_y_disp; reg [1:0] S_t1_sh_disp;
    reg [10:0] S_t1_xmin_disp, S_t1_xmax_disp, S_t1_ymin_disp, S_t1_ymax_disp;
    reg        S_t2_v_disp;  reg [10:0] S_t2_x_disp; reg [10:0] S_t2_y_disp; reg [1:0] S_t2_sh_disp;
    reg [10:0] S_t2_xmin_disp, S_t2_xmax_disp, S_t2_ymin_disp, S_t2_ymax_disp;
    reg        S_digit_v_disp; reg [3:0] S_digit_id_disp;
    reg [7:0]  S_digit_confidence_disp;
    reg [1:0]  S_hand_id_disp;
    reg [2:0]  S_hand_tips_disp;
    reg        S_hand_box_valid_disp;
    reg [11:0] S_hand_xmin_disp, S_hand_xmax_disp;
    reg [9:0]  S_hand_ymin_disp, S_hand_ymax_disp;
    reg        S_aruco_valid_disp;
    reg [11:0] S_aruco_id_bcd_disp;
    reg [10:0] S_aruco_xmin_disp,S_aruco_xmax_disp;
    reg [10:0] S_aruco_ymin_disp,S_aruco_ymax_disp;
    reg [21:0] S_aruco_corner0_disp,S_aruco_corner1_disp;
    reg [21:0] S_aruco_corner2_disp,S_aruco_corner3_disp;
    reg [25:0] S_aruco_edge0_disp,S_aruco_edge1_disp;
    reg [25:0] S_aruco_edge2_disp,S_aruco_edge3_disp;
    reg [3:0]  S_md_char;          // 第二行字符索引 (MODE:D 7字符)
    reg [3:0]  S_md_col;
    reg [3:0]  S_md_row;
    reg [4:0]  S_md_bits;

    localparam LOGO_X = 12'd0;
    localparam LOGO_Y = 12'd0;
    localparam LOGO_W = 12'd160;
    localparam LOGO_H = 12'd160;

    localparam COLOR_LOGO_BLUE   = 24'h1f315c;
    localparam COLOR_LOGO_RED    = 24'hec1c2d;
    localparam COLOR_TEXT        = 24'h00e6ff;
    localparam DYN_OSD_X         = 12'd375;
    localparam DYN_OSD_Y         = 12'd120;
    localparam DYN_OSD_W         = 12'd200;
    localparam DYN_OSD_H         = 12'd24;
    localparam DYN2_OSD_Y        = 12'd152;   // 第二行: MODE/DELAY 显示 (在第一行下方)
    localparam DYN3_OSD_Y        = 12'd184;   // 第三行: MOT 运动计数
    localparam DYN4_OSD_Y        = 12'd216;   // 第四行: R 目标
    localparam DYN5_OSD_Y        = 12'd248;   // 第五行: G 目标
    localparam DYN6_OSD_Y        = 12'd280;   // 第六行: B 目标
    localparam DYN8_OSD_Y        = 12'd312;   // 第七行: 数字识别结果
    localparam DYN9_OSD_Y        = 12'd344;   // 第八行: HDMI 输出 FPS
    localparam DYN10_OSD_Y       = 12'd376;   // 第九行: 手势状态
    localparam HAND_OSD_X        = 12'd250;
    localparam DIGIT_BOX_X0      = 12'd472;
    localparam DIGIT_BOX_X1      = 12'd807;
    localparam DIGIT_BOX_Y0      = 12'd136;
    localparam DIGIT_BOX_Y1      = 12'd583;
    localparam CN_Y_OFFSET       = 12'd2;
    localparam COLOR_DYN_TEXT    = 24'hfff200;
    localparam CHAR_AN           = 8'h80;
    localparam CHAR_LU           = 8'h81;
    localparam CHAR_C            = 8'h43;
    localparam CHAR_N            = 8'h4e;
    localparam CHAR_T            = 8'h54;
    localparam CHAR_0            = 8'h30;
    localparam CHAR_COLON        = 8'h3a;

    // hex 数字转 ASCII: 0-9→'0'-'9', 10-15→'A'-'F'
    function [7:0] F_hex_char;
        input [3:0] nibble;
        begin
            case (nibble)
                4'd0: F_hex_char = 8'h30;
                4'd1: F_hex_char = 8'h31;
                4'd2: F_hex_char = 8'h32;
                4'd3: F_hex_char = 8'h33;
                4'd4: F_hex_char = 8'h34;
                4'd5: F_hex_char = 8'h35;
                4'd6: F_hex_char = 8'h36;
                4'd7: F_hex_char = 8'h37;
                4'd8: F_hex_char = 8'h38;
                4'd9: F_hex_char = 8'h39;
                4'd10: F_hex_char = 8'h41;
                4'd11: F_hex_char = 8'h42;
                4'd12: F_hex_char = 8'h43;
                4'd13: F_hex_char = 8'h44;
                4'd14: F_hex_char = 8'h45;
                4'd15: F_hex_char = 8'h46;
                default: F_hex_char = 8'h3F;
            endcase
        end
    endfunction

    // Double-dabble 的单步函数：每拍只处理一个输入 bit，避免把完整
    // 16 轮 BCD 转换串进 HDMI 像素组合路径。连续执行 16 拍即可得到
    // 5 位 BCD（00000..65535）。
    function [19:0] F_bcd_step;
        input [19:0] bcd_in;
        input        bin_msb;
        reg [19:0] bcd_adj;
        begin
            bcd_adj = bcd_in;
            if (bcd_adj[3:0]   >= 4'd5) bcd_adj[3:0]   = bcd_adj[3:0]   + 4'd3;
            if (bcd_adj[7:4]   >= 4'd5) bcd_adj[7:4]   = bcd_adj[7:4]   + 4'd3;
            if (bcd_adj[11:8]  >= 4'd5) bcd_adj[11:8]  = bcd_adj[11:8]  + 4'd3;
            if (bcd_adj[15:12] >= 4'd5) bcd_adj[15:12] = bcd_adj[15:12] + 4'd3;
            if (bcd_adj[19:16] >= 4'd5) bcd_adj[19:16] = bcd_adj[19:16] + 4'd3;
            F_bcd_step = {bcd_adj[18:0], bin_msb};
        end
    endfunction

    wire [19:0] S_motion_bcd_step_next =
        F_bcd_step(S_motion_bcd_work, S_motion_bin_work[15]);

    // BCD 数字转 ASCII。非法 BCD 仅显示 '?', 不显示 A..F，便于板上判断。
    function [7:0] F_dec_char;
        input [3:0] digit;
        begin
            if (digit <= 4'd9)
                F_dec_char = 8'h30 + digit;
            else
                F_dec_char = 8'h3F;
        end
    endfunction


    // 将 24 像素高的 OSD 单元映射到字库的 16 行。
    //
    // 字库本身是 16x16（每个 8x8 原始字形按 2 倍展开），而动态信息
    // 为了留出行间距使用 16x24 单元。原实现对部分行直接取
    // S_dyn_y[3:0]，导致 y=16..23 回卷到字库第 0..7 行；在屏幕上看起来
    // 就像每个字符的下半截被截断/重复。使用同一个 24->16 查表后，所有
    // ASCII/数字行都保持完整且上下比例一致，同时避免综合出除法器。
    function [3:0] F_osd_row24;
        input [4:0] y24;
        begin
            case (y24)
                5'd0:  F_osd_row24 = 4'd0;
                5'd1:  F_osd_row24 = 4'd0;
                5'd2:  F_osd_row24 = 4'd1;
                5'd3:  F_osd_row24 = 4'd2;
                5'd4:  F_osd_row24 = 4'd2;
                5'd5:  F_osd_row24 = 4'd3;
                5'd6:  F_osd_row24 = 4'd4;
                5'd7:  F_osd_row24 = 4'd4;
                5'd8:  F_osd_row24 = 4'd5;
                5'd9:  F_osd_row24 = 4'd6;
                5'd10: F_osd_row24 = 4'd6;
                5'd11: F_osd_row24 = 4'd7;
                5'd12: F_osd_row24 = 4'd8;
                5'd13: F_osd_row24 = 4'd8;
                5'd14: F_osd_row24 = 4'd9;
                5'd15: F_osd_row24 = 4'd10;
                5'd16: F_osd_row24 = 4'd10;
                5'd17: F_osd_row24 = 4'd11;
                5'd18: F_osd_row24 = 4'd12;
                5'd19: F_osd_row24 = 4'd12;
                5'd20: F_osd_row24 = 4'd13;
                5'd21: F_osd_row24 = 4'd14;
                5'd22: F_osd_row24 = 4'd14;
                5'd23: F_osd_row24 = 4'd15;
                default: F_osd_row24 = 4'd0;
            endcase
        end
    endfunction

    function [4:0] F_logo_text_bits;
        input [3:0] I_char;
        input [2:0] I_row;
        begin
            case(I_char)
                4'd0: begin
                    case(I_row) // A
                        3'd0: F_logo_text_bits = 5'b01110;
                        3'd1: F_logo_text_bits = 5'b10001;
                        3'd2: F_logo_text_bits = 5'b10001;
                        3'd3: F_logo_text_bits = 5'b11111;
                        3'd4: F_logo_text_bits = 5'b10001;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b10001;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd1: begin
                    case(I_row) // N
                        3'd0: F_logo_text_bits = 5'b10001;
                        3'd1: F_logo_text_bits = 5'b11001;
                        3'd2: F_logo_text_bits = 5'b10101;
                        3'd3: F_logo_text_bits = 5'b10011;
                        3'd4: F_logo_text_bits = 5'b10001;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b10001;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd2: begin
                    case(I_row) // L
                        3'd0: F_logo_text_bits = 5'b10000;
                        3'd1: F_logo_text_bits = 5'b10000;
                        3'd2: F_logo_text_bits = 5'b10000;
                        3'd3: F_logo_text_bits = 5'b10000;
                        3'd4: F_logo_text_bits = 5'b10000;
                        3'd5: F_logo_text_bits = 5'b10000;
                        3'd6: F_logo_text_bits = 5'b11111;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd3: begin
                    case(I_row) // O
                        3'd0: F_logo_text_bits = 5'b01110;
                        3'd1: F_logo_text_bits = 5'b10001;
                        3'd2: F_logo_text_bits = 5'b10001;
                        3'd3: F_logo_text_bits = 5'b10001;
                        3'd4: F_logo_text_bits = 5'b10001;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b01110;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd4: begin
                    case(I_row) // G
                        3'd0: F_logo_text_bits = 5'b01110;
                        3'd1: F_logo_text_bits = 5'b10001;
                        3'd2: F_logo_text_bits = 5'b10000;
                        3'd3: F_logo_text_bits = 5'b10111;
                        3'd4: F_logo_text_bits = 5'b10001;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b01110;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd5: begin
                    case(I_row) // I
                        3'd0: F_logo_text_bits = 5'b11111;
                        3'd1: F_logo_text_bits = 5'b00100;
                        3'd2: F_logo_text_bits = 5'b00100;
                        3'd3: F_logo_text_bits = 5'b00100;
                        3'd4: F_logo_text_bits = 5'b00100;
                        3'd5: F_logo_text_bits = 5'b00100;
                        3'd6: F_logo_text_bits = 5'b11111;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd6: begin
                    case(I_row) // C
                        3'd0: F_logo_text_bits = 5'b01110;
                        3'd1: F_logo_text_bits = 5'b10001;
                        3'd2: F_logo_text_bits = 5'b10000;
                        3'd3: F_logo_text_bits = 5'b10000;
                        3'd4: F_logo_text_bits = 5'b10000;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b01110;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                default: F_logo_text_bits = 5'b00000;
            endcase
        end
    endfunction

    // 7-seg bit mapping: {a,b,c,d,e,f,g}
    function [6:0] F_hex7seg;
        input [3:0] I_hex;
        begin
            case(I_hex)
                4'h0: F_hex7seg = 7'b1111110;
                4'h1: F_hex7seg = 7'b0110000;
                4'h2: F_hex7seg = 7'b1101101;
                4'h3: F_hex7seg = 7'b1111001;
                4'h4: F_hex7seg = 7'b0110011;
                4'h5: F_hex7seg = 7'b1011011;
                4'h6: F_hex7seg = 7'b1011111;
                4'h7: F_hex7seg = 7'b1110000;
                4'h8: F_hex7seg = 7'b1111111;
                4'h9: F_hex7seg = 7'b1111011;
                4'ha: F_hex7seg = 7'b1110111;
                4'hb: F_hex7seg = 7'b0011111;
                4'hc: F_hex7seg = 7'b1001110;
                4'hd: F_hex7seg = 7'b0111101;
                4'he: F_hex7seg = 7'b1001111;
                4'hf: F_hex7seg = 7'b1000111;
                default: F_hex7seg = 7'b0000000;
            endcase
        end
    endfunction

    function [4:0] F_cnt_label_bits;
        input [1:0] I_idx;
        input [2:0] I_row;
        begin
            case(I_idx)
                2'd0: begin // C
                    case(I_row)
                        3'd0: F_cnt_label_bits = 5'b01110;
                        3'd1: F_cnt_label_bits = 5'b10001;
                        3'd2: F_cnt_label_bits = 5'b10000;
                        3'd3: F_cnt_label_bits = 5'b10000;
                        3'd4: F_cnt_label_bits = 5'b10000;
                        3'd5: F_cnt_label_bits = 5'b10001;
                        3'd6: F_cnt_label_bits = 5'b01110;
                        default: F_cnt_label_bits = 5'b00000;
                    endcase
                end
                2'd1: begin // N
                    case(I_row)
                        3'd0: F_cnt_label_bits = 5'b10001;
                        3'd1: F_cnt_label_bits = 5'b11001;
                        3'd2: F_cnt_label_bits = 5'b10101;
                        3'd3: F_cnt_label_bits = 5'b10011;
                        3'd4: F_cnt_label_bits = 5'b10001;
                        3'd5: F_cnt_label_bits = 5'b10001;
                        3'd6: F_cnt_label_bits = 5'b10001;
                        default: F_cnt_label_bits = 5'b00000;
                    endcase
                end
                2'd2: begin // T
                    case(I_row)
                        3'd0: F_cnt_label_bits = 5'b11111;
                        3'd1: F_cnt_label_bits = 5'b00100;
                        3'd2: F_cnt_label_bits = 5'b00100;
                        3'd3: F_cnt_label_bits = 5'b00100;
                        3'd4: F_cnt_label_bits = 5'b00100;
                        3'd5: F_cnt_label_bits = 5'b00100;
                        3'd6: F_cnt_label_bits = 5'b00100;
                        default: F_cnt_label_bits = 5'b00000;
                    endcase
                end
                default: begin // ':'
                    case(I_row)
                        3'd2: F_cnt_label_bits = 5'b00100;
                        3'd5: F_cnt_label_bits = 5'b00100;
                        default: F_cnt_label_bits = 5'b00000;
                    endcase
                end
            endcase
        end
    endfunction

    // Minimal 16x16 Chinese bitmap rows for "an" and "lu".
    function [15:0] F_cn16_row;
        input I_char; // 0: an, 1: lu
        input [3:0] I_row;
        begin
            if(!I_char) begin
                case(I_row)
                    4'd0:  F_cn16_row = 16'h0200;
                    4'd1:  F_cn16_row = 16'h7ff0;
                    4'd2:  F_cn16_row = 16'h4410;
                    4'd3:  F_cn16_row = 16'h0400;
                    4'd4:  F_cn16_row = 16'h7ff0;
                    4'd5:  F_cn16_row = 16'h0840;
                    4'd6:  F_cn16_row = 16'h1040;
                    4'd7:  F_cn16_row = 16'h1c80;
                    4'd8:  F_cn16_row = 16'h0300;
                    4'd9:  F_cn16_row = 16'h0cc0;
                    4'd10: F_cn16_row = 16'h7020;
                    4'd11: F_cn16_row = 16'h0000;
                    4'd12: F_cn16_row = 16'h0000;
                    4'd13: F_cn16_row = 16'h0000;
                    4'd14: F_cn16_row = 16'h0000;
                    4'd15: F_cn16_row = 16'h0000;
                    default: F_cn16_row = 16'h0000;
                endcase
            end
            else begin
                case(I_row)
                    4'd0:  F_cn16_row = 16'h79e0;
                    4'd1:  F_cn16_row = 16'h4a20;
                    4'd2:  F_cn16_row = 16'h4d40;
                    4'd3:  F_cn16_row = 16'h7880;
                    4'd4:  F_cn16_row = 16'h1140;
                    4'd5:  F_cn16_row = 16'h1630;
                    4'd6:  F_cn16_row = 16'h5be0;
                    4'd7:  F_cn16_row = 16'h5220;
                    4'd8:  F_cn16_row = 16'h5220;
                    4'd9:  F_cn16_row = 16'h5be0;
                    4'd10: F_cn16_row = 16'h6220;
                    4'd11: F_cn16_row = 16'h0000;
                    4'd12: F_cn16_row = 16'h0000;
                    4'd13: F_cn16_row = 16'h0000;
                    4'd14: F_cn16_row = 16'h0000;
                    4'd15: F_cn16_row = 16'h0000;
                    default: F_cn16_row = 16'h0000;
                endcase
            end
        end
    endfunction

    function [4:0] F_dyn_char_bits;
        input [3:0] I_char;
        input [2:0] I_row;
        begin
            case(I_char)
                4'h0: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10011; 3'd3:F_dyn_char_bits=5'b10101; 3'd4:F_dyn_char_bits=5'b11001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h1: begin case(I_row) 3'd0:F_dyn_char_bits=5'b00100; 3'd1:F_dyn_char_bits=5'b01100; 3'd2:F_dyn_char_bits=5'b00100; 3'd3:F_dyn_char_bits=5'b00100; 3'd4:F_dyn_char_bits=5'b00100; 3'd5:F_dyn_char_bits=5'b00100; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h2: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b00001; 3'd3:F_dyn_char_bits=5'b00110; 3'd4:F_dyn_char_bits=5'b01000; 3'd5:F_dyn_char_bits=5'b10000; 3'd6:F_dyn_char_bits=5'b11111; default:F_dyn_char_bits=5'b00000; endcase end
                4'h3: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11110; 3'd1:F_dyn_char_bits=5'b00001; 3'd2:F_dyn_char_bits=5'b00001; 3'd3:F_dyn_char_bits=5'b01110; 3'd4:F_dyn_char_bits=5'b00001; 3'd5:F_dyn_char_bits=5'b00001; 3'd6:F_dyn_char_bits=5'b11110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h4: begin case(I_row) 3'd0:F_dyn_char_bits=5'b00010; 3'd1:F_dyn_char_bits=5'b00110; 3'd2:F_dyn_char_bits=5'b01010; 3'd3:F_dyn_char_bits=5'b10010; 3'd4:F_dyn_char_bits=5'b11111; 3'd5:F_dyn_char_bits=5'b00010; 3'd6:F_dyn_char_bits=5'b00010; default:F_dyn_char_bits=5'b00000; endcase end
                4'h5: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11111; 3'd1:F_dyn_char_bits=5'b10000; 3'd2:F_dyn_char_bits=5'b11110; 3'd3:F_dyn_char_bits=5'b00001; 3'd4:F_dyn_char_bits=5'b00001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h6: begin case(I_row) 3'd0:F_dyn_char_bits=5'b00110; 3'd1:F_dyn_char_bits=5'b01000; 3'd2:F_dyn_char_bits=5'b10000; 3'd3:F_dyn_char_bits=5'b11110; 3'd4:F_dyn_char_bits=5'b10001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h7: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11111; 3'd1:F_dyn_char_bits=5'b00001; 3'd2:F_dyn_char_bits=5'b00010; 3'd3:F_dyn_char_bits=5'b00100; 3'd4:F_dyn_char_bits=5'b01000; 3'd5:F_dyn_char_bits=5'b01000; 3'd6:F_dyn_char_bits=5'b01000; default:F_dyn_char_bits=5'b00000; endcase end
                4'h8: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10001; 3'd3:F_dyn_char_bits=5'b01110; 3'd4:F_dyn_char_bits=5'b10001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h9: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10001; 3'd3:F_dyn_char_bits=5'b01111; 3'd4:F_dyn_char_bits=5'b00001; 3'd5:F_dyn_char_bits=5'b00010; 3'd6:F_dyn_char_bits=5'b11100; default:F_dyn_char_bits=5'b00000; endcase end
                4'ha: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10001; 3'd3:F_dyn_char_bits=5'b11111; 3'd4:F_dyn_char_bits=5'b10001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b10001; default:F_dyn_char_bits=5'b00000; endcase end
                4'hb: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10001; 3'd3:F_dyn_char_bits=5'b11110; 3'd4:F_dyn_char_bits=5'b10001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b11110; default:F_dyn_char_bits=5'b00000; endcase end
                4'hc: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10000; 3'd3:F_dyn_char_bits=5'b10000; 3'd4:F_dyn_char_bits=5'b10000; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'hd: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10001; 3'd3:F_dyn_char_bits=5'b10001; 3'd4:F_dyn_char_bits=5'b10001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b11110; default:F_dyn_char_bits=5'b00000; endcase end
                4'he: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11111; 3'd1:F_dyn_char_bits=5'b10000; 3'd2:F_dyn_char_bits=5'b10000; 3'd3:F_dyn_char_bits=5'b11110; 3'd4:F_dyn_char_bits=5'b10000; 3'd5:F_dyn_char_bits=5'b10000; 3'd6:F_dyn_char_bits=5'b11111; default:F_dyn_char_bits=5'b00000; endcase end
                4'hf: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11111; 3'd1:F_dyn_char_bits=5'b10000; 3'd2:F_dyn_char_bits=5'b10000; 3'd3:F_dyn_char_bits=5'b11110; 3'd4:F_dyn_char_bits=5'b10000; 3'd5:F_dyn_char_bits=5'b10000; 3'd6:F_dyn_char_bits=5'b10000; default:F_dyn_char_bits=5'b00000; endcase end
                default: F_dyn_char_bits = 5'b00000;
            endcase
        end
    endfunction

    // Unified prefix character library (16x16 rows): an/lu/C/N/T/:
    function [15:0] F_osd_char16_row;
        input [7:0] I_char;
        input [3:0] I_row;
        begin
            case(I_char)
                CHAR_AN: begin
                    case(I_row)
                        4'd0:  F_osd_char16_row = 16'h0200;
                        4'd1:  F_osd_char16_row = 16'h7ff0;
                        4'd2:  F_osd_char16_row = 16'h4410;
                        4'd3:  F_osd_char16_row = 16'h0400;
                        4'd4:  F_osd_char16_row = 16'h7ff0;
                        4'd5:  F_osd_char16_row = 16'h0840;
                        4'd6:  F_osd_char16_row = 16'h1040;
                        4'd7:  F_osd_char16_row = 16'h1c80;
                        4'd8:  F_osd_char16_row = 16'h0300;
                        4'd9:  F_osd_char16_row = 16'h0cc0;
                        4'd10: F_osd_char16_row = 16'h7020;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_LU: begin
                    case(I_row)
                        4'd0:  F_osd_char16_row = 16'h79e0;
                        4'd1:  F_osd_char16_row = 16'h4a20;
                        4'd2:  F_osd_char16_row = 16'h4d40;
                        4'd3:  F_osd_char16_row = 16'h7880;
                        4'd4:  F_osd_char16_row = 16'h1140;
                        4'd5:  F_osd_char16_row = 16'h1630;
                        4'd6:  F_osd_char16_row = 16'h5be0;
                        4'd7:  F_osd_char16_row = 16'h5220;
                        4'd8:  F_osd_char16_row = 16'h5220;
                        4'd9:  F_osd_char16_row = 16'h5be0;
                        4'd10: F_osd_char16_row = 16'h6220;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_C: begin
                    case(I_row)
                        4'd2:  F_osd_char16_row = 16'h03f0;
                        4'd3:  F_osd_char16_row = 16'h0c0c;
                        4'd4:  F_osd_char16_row = 16'h1800;
                        4'd5:  F_osd_char16_row = 16'h3000;
                        4'd6:  F_osd_char16_row = 16'h3000;
                        4'd7:  F_osd_char16_row = 16'h3000;
                        4'd8:  F_osd_char16_row = 16'h3000;
                        4'd9:  F_osd_char16_row = 16'h3000;
                        4'd10: F_osd_char16_row = 16'h1800;
                        4'd11: F_osd_char16_row = 16'h0c0c;
                        4'd12: F_osd_char16_row = 16'h03f0;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_N: begin
                    case(I_row)
                        4'd2:  F_osd_char16_row = 16'h300c;
                        4'd3:  F_osd_char16_row = 16'h380c;
                        4'd4:  F_osd_char16_row = 16'h3c0c;
                        4'd5:  F_osd_char16_row = 16'h360c;
                        4'd6:  F_osd_char16_row = 16'h330c;
                        4'd7:  F_osd_char16_row = 16'h318c;
                        4'd8:  F_osd_char16_row = 16'h30cc;
                        4'd9:  F_osd_char16_row = 16'h306c;
                        4'd10: F_osd_char16_row = 16'h303c;
                        4'd11: F_osd_char16_row = 16'h301c;
                        4'd12: F_osd_char16_row = 16'h300c;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_T: begin
                    case(I_row)
                        4'd2:  F_osd_char16_row = 16'h3ffc;
                        4'd3:  F_osd_char16_row = 16'h03c0;
                        4'd4:  F_osd_char16_row = 16'h03c0;
                        4'd5:  F_osd_char16_row = 16'h03c0;
                        4'd6:  F_osd_char16_row = 16'h03c0;
                        4'd7:  F_osd_char16_row = 16'h03c0;
                        4'd8:  F_osd_char16_row = 16'h03c0;
                        4'd9:  F_osd_char16_row = 16'h03c0;
                        4'd10: F_osd_char16_row = 16'h03c0;
                        4'd11: F_osd_char16_row = 16'h03c0;
                        4'd12: F_osd_char16_row = 16'h03c0;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_COLON: begin
                    case(I_row)
                        4'd6:  F_osd_char16_row = 16'h0180;
                        4'd7:  F_osd_char16_row = 16'h0180;
                        4'd10: F_osd_char16_row = 16'h0180;
                        4'd11: F_osd_char16_row = 16'h0180;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                default: F_osd_char16_row = 16'h0000;
            endcase
        end
    endfunction

    assign O_video_rd_en = I_video_de;

    logo_v35_reference u_anlogic_logo_rom(
        .I_clk (I_clk),
        .I_addr  ( S_logo_addr  ),
        .O_pixel ( S_logo_pixel ),
        .O_present ( S_logo_present )
    );

    osd_char_lib #(.SYNC_READ(1)) u_osd_char_lib(
        .I_clk (I_clk),
        .I_char     ( S_pf_char     ),
        .I_row      ( S_pf_row      ),
        .O_row_bits ( S_pf_row_bits )
    );

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_x <= 12'd0;
            S_y <= 12'd0;
        end
        else if(I_video_user) begin
            S_x <= 12'd0;
            S_y <= 12'd0;
        end
        else if(I_video_de) begin
            if(I_video_last) begin
                S_x <= 12'd0;
                S_y <= S_y + 12'd1;
            end
            else begin
                S_x <= S_x + 12'd1;
            end
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_frame_cnt <= 32'd0;
            S_cnt_d0 <= 4'd0;
            S_cnt_d1 <= 4'd0;
            S_cnt_d2 <= 4'd0;
            S_cnt_d3 <= 4'd0;
            S_cnt_d4 <= 4'd0;
            S_cnt_d5 <= 4'd0;
        end
        else if(I_video_user) begin
                    S_frame_cnt <= S_frame_cnt + 32'd1;
            // (修复) motion/track 锁存移出 vuser 门控: I_*_valid 是跨域恢复的
            // 单拍上升沿脉冲, 与 vuser 拍无相位关系, 原写法几乎永远采不到
            if(S_cnt_d0 == 4'd9) begin
                S_cnt_d0 <= 4'd0;
                if(S_cnt_d1 == 4'd9) begin
                    S_cnt_d1 <= 4'd0;
                    if(S_cnt_d2 == 4'd9) begin
                        S_cnt_d2 <= 4'd0;
                        if(S_cnt_d3 == 4'd9) begin
                            S_cnt_d3 <= 4'd0;
                            if(S_cnt_d4 == 4'd9) begin
                                S_cnt_d4 <= 4'd0;
                                if(S_cnt_d5 == 4'd9)
                                    S_cnt_d5 <= 4'd0;
                                else
                                    S_cnt_d5 <= S_cnt_d5 + 4'd1;
                            end
                            else
                                S_cnt_d4 <= S_cnt_d4 + 4'd1;
                        end
                        else
                            S_cnt_d3 <= S_cnt_d3 + 4'd1;
                    end
                    else
                        S_cnt_d2 <= S_cnt_d2 + 4'd1;
                end
                else
                    S_cnt_d1 <= S_cnt_d1 + 4'd1;
            end
            else
                S_cnt_d0 <= S_cnt_d0 + 4'd1;
        end
    end

    // (修复) motion/track 结果锁存: 独立 always, 直接响应跨域恢复的单拍脉冲
    // 数据 (I_t0_x 等) 与 valid 电平同源同 2FF 延迟, 脉冲到达时数据必稳定
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_motion_cnt_disp <= 16'd0;
            S_motion_bcd_disp <= 20'd0;
            S_motion_bcd_work <= 20'd0;
            S_motion_bin_work <= 16'd0;
            S_motion_bcd_step_idx <= 5'd0;
            S_motion_bcd_busy <= 1'b0;
            S_track_cnt_disp  <= 4'd0;
            S_t0_v_disp <= 1'b0;  S_t0_x_disp <= 11'd0; S_t0_y_disp <= 11'd0; S_t0_sh_disp <= 2'd3;
            S_t0_xmin_disp <= 11'd0; S_t0_xmax_disp <= 11'd0; S_t0_ymin_disp <= 11'd0; S_t0_ymax_disp <= 11'd0;
            S_t1_v_disp <= 1'b0;  S_t1_x_disp <= 11'd0; S_t1_y_disp <= 11'd0; S_t1_sh_disp <= 2'd3;
            S_t1_xmin_disp <= 11'd0; S_t1_xmax_disp <= 11'd0; S_t1_ymin_disp <= 11'd0; S_t1_ymax_disp <= 11'd0;
            S_t2_v_disp <= 1'b0;  S_t2_x_disp <= 11'd0; S_t2_y_disp <= 11'd0; S_t2_sh_disp <= 2'd3;
            S_t2_xmin_disp <= 11'd0; S_t2_xmax_disp <= 11'd0; S_t2_ymin_disp <= 11'd0; S_t2_ymax_disp <= 11'd0;
            S_digit_v_disp <= 1'b0; S_digit_id_disp <= 4'hf;
            S_digit_confidence_disp <= 8'd0;
            S_hand_id_disp <= 2'd0;
            S_hand_tips_disp <= 3'd0;
            S_hand_box_valid_disp <= 1'b0;
            S_hand_xmin_disp <= 12'd0; S_hand_xmax_disp <= 12'd0;
            S_hand_ymin_disp <= 10'd0; S_hand_ymax_disp <= 10'd0;
            S_aruco_valid_disp <= 1'b0; S_aruco_id_bcd_disp <= 12'd0;
            S_aruco_xmin_disp <= 11'd0; S_aruco_xmax_disp <= 11'd0;
            S_aruco_ymin_disp <= 11'd0; S_aruco_ymax_disp <= 11'd0;
            S_aruco_corner0_disp<=22'd0;S_aruco_corner1_disp<=22'd0;
            S_aruco_corner2_disp<=22'd0;S_aruco_corner3_disp<=22'd0;
            S_aruco_edge0_disp<=26'd0;S_aruco_edge1_disp<=26'd0;
            S_aruco_edge2_disp<=26'd0;S_aruco_edge3_disp<=26'd0;
        end
        else begin
            if (!I_motion_enable) begin
                S_motion_cnt_disp <= 16'd0;
                S_motion_bcd_disp <= 20'd0;
                S_motion_bcd_work <= 20'd0;
                S_motion_bin_work <= 16'd0;
                S_motion_bcd_step_idx <= 5'd0;
                S_motion_bcd_busy <= 1'b0;
            end else if (I_motion_valid) begin
                S_motion_cnt_disp <= I_motion_count;
                S_motion_bcd_work <= 20'd0;
                S_motion_bin_work <= I_motion_count;
                S_motion_bcd_step_idx <= 5'd0;
                S_motion_bcd_busy <= 1'b1;
            end else if (S_motion_bcd_busy) begin
                S_motion_bcd_work <= S_motion_bcd_step_next;
                S_motion_bin_work <= {S_motion_bin_work[14:0],1'b0};
                if (S_motion_bcd_step_idx == 5'd15) begin
                    S_motion_bcd_disp <= S_motion_bcd_step_next;
                    S_motion_bcd_busy <= 1'b0;
                end else begin
                    S_motion_bcd_step_idx <= S_motion_bcd_step_idx + 5'd1;
                end
            end
            if (!I_track_enable) begin
                S_track_cnt_disp <= 4'd0;
                S_t0_v_disp <= 1'b0; S_t0_x_disp <= 11'd0; S_t0_y_disp <= 11'd0; S_t0_sh_disp <= 2'd3;
                S_t0_xmin_disp <= 11'd0; S_t0_xmax_disp <= 11'd0; S_t0_ymin_disp <= 11'd0; S_t0_ymax_disp <= 11'd0;
                S_t1_v_disp <= 1'b0; S_t1_x_disp <= 11'd0; S_t1_y_disp <= 11'd0; S_t1_sh_disp <= 2'd3;
                S_t1_xmin_disp <= 11'd0; S_t1_xmax_disp <= 11'd0; S_t1_ymin_disp <= 11'd0; S_t1_ymax_disp <= 11'd0;
                S_t2_v_disp <= 1'b0; S_t2_x_disp <= 11'd0; S_t2_y_disp <= 11'd0; S_t2_sh_disp <= 2'd3;
                S_t2_xmin_disp <= 11'd0; S_t2_xmax_disp <= 11'd0; S_t2_ymin_disp <= 11'd0; S_t2_ymax_disp <= 11'd0;
            end else if (I_track_valid) begin
                S_track_cnt_disp <= I_track_cnt;
                S_t0_v_disp <= I_t0_v;  S_t0_x_disp <= I_t0_x; S_t0_y_disp <= I_t0_y; S_t0_sh_disp <= I_t0_shape;
                S_t0_xmin_disp <= I_t0_xmin; S_t0_xmax_disp <= I_t0_xmax; S_t0_ymin_disp <= I_t0_ymin; S_t0_ymax_disp <= I_t0_ymax;
                S_t1_v_disp <= I_t1_v;  S_t1_x_disp <= I_t1_x; S_t1_y_disp <= I_t1_y; S_t1_sh_disp <= I_t1_shape;
                S_t1_xmin_disp <= I_t1_xmin; S_t1_xmax_disp <= I_t1_xmax; S_t1_ymin_disp <= I_t1_ymin; S_t1_ymax_disp <= I_t1_ymax;
                S_t2_v_disp <= I_t2_v;  S_t2_x_disp <= I_t2_x; S_t2_y_disp <= I_t2_y; S_t2_sh_disp <= I_t2_shape;
                S_t2_xmin_disp <= I_t2_xmin; S_t2_xmax_disp <= I_t2_xmax; S_t2_ymin_disp <= I_t2_ymin; S_t2_ymax_disp <= I_t2_ymax;
            end
            if (!I_digit_enable) begin
                S_digit_v_disp <= 1'b0;
                S_digit_id_disp <= 4'hf;
                S_digit_confidence_disp <= 8'd0;
            end else if (I_digit_valid) begin
                S_digit_v_disp <= 1'b1;
                S_digit_id_disp <= I_digit_id;
                S_digit_confidence_disp <= I_digit_confidence;
            end
            if (!I_hand_enable) begin
                S_hand_id_disp <= 2'd0;
                S_hand_tips_disp <= 3'd0;
                S_hand_box_valid_disp <= 1'b0;
            end else if (I_hand_valid) begin
                S_hand_id_disp <= I_hand_id;
                S_hand_tips_disp <= I_hand_tips;
                S_hand_box_valid_disp <= I_hand_box_valid && (I_hand_id != 2'd0);
                S_hand_xmin_disp <= {I_hand_xmin,2'b00};
                S_hand_xmax_disp <= {I_hand_xmax,2'b11};
                S_hand_ymin_disp <= I_hand_ymin;
                S_hand_ymax_disp <= I_hand_ymax;
            end
            if (!I_aruco_enable) begin
                S_aruco_valid_disp <= 1'b0;
                S_aruco_id_bcd_disp <= 12'd0;
                S_aruco_xmin_disp <= 11'd0; S_aruco_xmax_disp <= 11'd0;
                S_aruco_ymin_disp <= 11'd0; S_aruco_ymax_disp <= 11'd0;
                S_aruco_corner0_disp<=22'd0;S_aruco_corner1_disp<=22'd0;
                S_aruco_corner2_disp<=22'd0;S_aruco_corner3_disp<=22'd0;
                S_aruco_edge0_disp<=26'd0;S_aruco_edge1_disp<=26'd0;
                S_aruco_edge2_disp<=26'd0;S_aruco_edge3_disp<=26'd0;
            end else if (I_video_user) begin
                S_aruco_valid_disp <= I_aruco_valid &&
                    (F_max4(I_aruco_corner0[10:0],I_aruco_corner1[10:0],I_aruco_corner2[10:0],I_aruco_corner3[10:0]) >
                     F_min4(I_aruco_corner0[10:0],I_aruco_corner1[10:0],I_aruco_corner2[10:0],I_aruco_corner3[10:0])) &&
                    (F_max4(I_aruco_corner0[21:11],I_aruco_corner1[21:11],I_aruco_corner2[21:11],I_aruco_corner3[21:11]) >
                     F_min4(I_aruco_corner0[21:11],I_aruco_corner1[21:11],I_aruco_corner2[21:11],I_aruco_corner3[21:11]));
                S_aruco_id_bcd_disp <= I_aruco_id_bcd;
                S_aruco_xmin_disp <= F_min4(I_aruco_corner0[10:0],I_aruco_corner1[10:0],I_aruco_corner2[10:0],I_aruco_corner3[10:0]);
                S_aruco_xmax_disp <= F_max4(I_aruco_corner0[10:0],I_aruco_corner1[10:0],I_aruco_corner2[10:0],I_aruco_corner3[10:0]);
                S_aruco_ymin_disp <= F_min4(I_aruco_corner0[21:11],I_aruco_corner1[21:11],I_aruco_corner2[21:11],I_aruco_corner3[21:11]);
                S_aruco_ymax_disp <= F_max4(I_aruco_corner0[21:11],I_aruco_corner1[21:11],I_aruco_corner2[21:11],I_aruco_corner3[21:11]);
                S_aruco_corner0_disp<=I_aruco_corner0;S_aruco_corner1_disp<=I_aruco_corner1;
                S_aruco_corner2_disp<=I_aruco_corner2;S_aruco_corner3_disp<=I_aruco_corner3;
                S_aruco_edge0_disp<=I_aruco_edge0;S_aruco_edge1_disp<=I_aruco_edge1;
                S_aruco_edge2_disp<=I_aruco_edge2;S_aruco_edge3_disp<=I_aruco_edge3;
            end
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_x_1d <= 12'd0;
            S_x_2d <= 12'd0;
            S_y_1d <= 12'd0;
            S_y_2d <= 12'd0;
            S_aruco_edge_hit_2d <= 1'b0;
        end
        else begin
            S_x_1d <= S_x;
            S_x_2d <= S_x_1d;
            S_y_1d <= S_y;
            S_y_2d <= S_y_1d;
            S_aruco_edge_hit_2d <= I_aruco_enable && S_aruco_valid_disp &&
                (F_aruco_line_hit(S_x_1d,S_y_1d,
                    S_aruco_corner0_disp[10:0],S_aruco_corner0_disp[21:11],
                    S_aruco_corner1_disp[10:0],S_aruco_corner1_disp[21:11],S_aruco_edge0_disp) ||
                 F_aruco_line_hit(S_x_1d,S_y_1d,
                    S_aruco_corner1_disp[10:0],S_aruco_corner1_disp[21:11],
                    S_aruco_corner2_disp[10:0],S_aruco_corner2_disp[21:11],S_aruco_edge1_disp) ||
                 F_aruco_line_hit(S_x_1d,S_y_1d,
                    S_aruco_corner2_disp[10:0],S_aruco_corner2_disp[21:11],
                    S_aruco_corner3_disp[10:0],S_aruco_corner3_disp[21:11],S_aruco_edge2_disp) ||
                 F_aruco_line_hit(S_x_1d,S_y_1d,
                    S_aruco_corner3_disp[10:0],S_aruco_corner3_disp[21:11],
                    S_aruco_corner0_disp[10:0],S_aruco_corner0_disp[21:11],S_aruco_edge3_disp));

        end
    end

    // The index-ROM read occupies the former address-register cycle.
    assign S_logo_addr =
        ((S_x_1d >= LOGO_X) && (S_x_1d < LOGO_X+LOGO_W) &&
         (S_y_1d >= LOGO_Y) && (S_y_1d < LOGO_Y+LOGO_H)) ?
        (({3'b000,(S_y_1d-LOGO_Y)} << 7) +
         ({3'b000,(S_y_1d-LOGO_Y)} << 5) +
         {3'b000,(S_x_1d-LOGO_X)}) : 15'd0;

    always @(*) begin
        S_osd_hit   = 1'b0;
        S_osd_color = 24'd0;
        S_logo_hit  = 1'b0;
        S_logo_color = 24'd0;

        S_logo_x = 12'd0;
        S_logo_y = 12'd0;
        S_char_idx = 4'd0;
        S_char_row = 3'd0;
        S_char_col = 3'd0;
        S_char_bits = 5'd0;
        S_char_on = 1'b0;
        S_logo_blue_on = 1'b0;
        S_logo_red_on = 1'b0;
        S_logo_tmp_y = 12'd0;
        S_logo_red_band = 4'd0;
        S_logo_red_x_start = 12'd0;
        S_logo_red_x_end = 12'd0;
        S_dyn_x = 12'd0;
        S_dyn_y = 12'd0;
        S_dyn_char = 4'd0;
        S_dyn_col = 3'd0;
        S_dyn_row = 3'd0;
        S_dyn_bits = 5'd0;
        S_dyn_on = 1'b0;
        S_digit_box_on = 1'b0;
        S_hand_box_on = 1'b0;
        S_aruco_box_on = 1'b0;
        S_track_box_on = 1'b0;
        S_track_box_color = 24'd0;
        S_dyn_digit_idx = 4'd0;
        S_dyn_digit_x = 12'd0;
        S_dyn_seg = 7'd0;
        S_digit_seg_on = 1'b0;
        S_lbl_row = 3'd0;
        S_lbl_col = 3'd0;
        S_lbl_idx = 2'd0;
        S_lbl_bits = 5'd0;
        S_lbl_local_x = 7'd0;
        S_dyn_dec_digit = 4'd0;
        S_cn_local_x = 5'd0;
        S_cn_local_y = 5'd0;
        S_cn_col = 4'd0;
        S_cn_row = 4'd0;
        S_cn_row_bits = 16'd0;
        S_cn_on = 1'b0;
        S_cn_scale_x = 10'd0;
        S_cn_scale_y = 10'd0;
        S_pf_char = 8'd0;
        S_aruco_label_x = 12'd0;
        S_aruco_label_y = 12'd0;
        S_pf_local_x = 5'd0;
        S_pf_local_y = 5'd0;
        S_pf_col = 4'd0;
        S_pf_row = 4'd0;
        S_pf_on = 1'b0;
        S_font_active = 1'b0;
        S_pf_scale_x = 10'd0;
        S_pf_scale_y = 10'd0;

        if(S_video_de_2d) begin
            if((S_x_2d >= LOGO_X) && (S_x_2d < (LOGO_X + LOGO_W)) &&
               (S_y_2d >= LOGO_Y) && (S_y_2d < (LOGO_Y + LOGO_H))) begin
                S_logo_x = S_x_2d - LOGO_X;
                S_logo_y = S_y_2d - LOGO_Y;
                if(S_logo_present) begin
                    S_logo_hit   = 1'b1;
                    S_logo_color = S_logo_pixel[23:0];
                end
            end

            // 三色目标框：检测器输出的是每色最大候选的像素 min/max，
            // 这里仅做当前像素的边界比较，不读帧缓存、不改变视频数据。
            // 每条边画两像素，低分辨率下仍清晰；框颜色与 R/G/B 目标一致。
            if(I_track_enable && S_t0_v_disp && !S_logo_hit &&
               (S_x_2d >= {1'b0,S_t0_xmin_disp}) &&
               (S_x_2d <= {1'b0,S_t0_xmax_disp}) &&
               (S_y_2d >= {1'b0,S_t0_ymin_disp}) &&
               (S_y_2d <= {1'b0,S_t0_ymax_disp}) &&
               ((S_x_2d <= ({1'b0,S_t0_xmin_disp} + 12'd1)) ||
                (S_x_2d >= ({1'b0,S_t0_xmax_disp} - 12'd1)) ||
                (S_y_2d <= ({1'b0,S_t0_ymin_disp} + 12'd1)) ||
                (S_y_2d >= ({1'b0,S_t0_ymax_disp} - 12'd1)))) begin
                S_track_box_on = 1'b1;
                S_track_box_color = 24'hff3040;
            end
            if(I_track_enable && S_t1_v_disp && !S_logo_hit && !S_track_box_on &&
               (S_x_2d >= {1'b0,S_t1_xmin_disp}) &&
               (S_x_2d <= {1'b0,S_t1_xmax_disp}) &&
               (S_y_2d >= {1'b0,S_t1_ymin_disp}) &&
               (S_y_2d <= {1'b0,S_t1_ymax_disp}) &&
               ((S_x_2d <= ({1'b0,S_t1_xmin_disp} + 12'd1)) ||
                (S_x_2d >= ({1'b0,S_t1_xmax_disp} - 12'd1)) ||
                (S_y_2d <= ({1'b0,S_t1_ymin_disp} + 12'd1)) ||
                (S_y_2d >= ({1'b0,S_t1_ymax_disp} - 12'd1)))) begin
                S_track_box_on = 1'b1;
                S_track_box_color = 24'h30ff70;
            end
            if(I_track_enable && S_t2_v_disp && !S_logo_hit && !S_track_box_on &&
               (S_x_2d >= {1'b0,S_t2_xmin_disp}) &&
               (S_x_2d <= {1'b0,S_t2_xmax_disp}) &&
               (S_y_2d >= {1'b0,S_t2_ymin_disp}) &&
               (S_y_2d <= {1'b0,S_t2_ymax_disp}) &&
               ((S_x_2d <= ({1'b0,S_t2_xmin_disp} + 12'd1)) ||
                (S_x_2d >= ({1'b0,S_t2_xmax_disp} - 12'd1)) ||
                (S_y_2d <= ({1'b0,S_t2_ymin_disp} + 12'd1)) ||
                (S_y_2d >= ({1'b0,S_t2_ymax_disp} - 12'd1)))) begin
                S_track_box_on = 1'b1;
                S_track_box_color = 24'h4080ff;
            end

            if((!S_logo_hit) &&
               (S_x_2d >= DYN_OSD_X) && (S_x_2d < (DYN_OSD_X + DYN_OSD_W)) &&
               (S_y_2d >= DYN_OSD_Y) && (S_y_2d < (DYN_OSD_Y + DYN_OSD_H))) begin
                S_dyn_x = S_x_2d - DYN_OSD_X;
                S_dyn_y = S_y_2d - DYN_OSD_Y;

                // Unified prefix render using one character library.
                // an:[0..23], lu:[24..47], C:[52..67], N:[68..83], T:[84..99], :[100..107]
                if((S_dyn_x < 12'd108) && (S_dyn_y < 12'd24)) begin
                    if((S_dyn_x < 12'd24) || ((S_dyn_x >= 12'd24) && (S_dyn_x < 12'd48))) begin
                        if(S_dyn_y >= CN_Y_OFFSET)
                            S_pf_local_y = S_dyn_y - CN_Y_OFFSET;
                        else
                            S_pf_local_y = 5'd31;

                        if(S_dyn_x < 12'd24) begin
                            S_pf_char = CHAR_AN;
                            S_pf_local_x = S_dyn_x;
                        end
                        else begin
                            S_pf_char = CHAR_LU;
                            S_pf_local_x = S_dyn_x - 12'd24;
                        end

                        if((S_pf_local_x < 5'd24) && (S_pf_local_y < 5'd24)) begin
                            // 24px 区画 16 列字库: x*16/24 映射 → 常数表 (TD 无除法器)
                            case(S_pf_local_x)
                                5'd0:  S_pf_col = 4'd0;   5'd1:  S_pf_col = 4'd1;
                                5'd2:  S_pf_col = 4'd1;   5'd3:  S_pf_col = 4'd2;
                                5'd4:  S_pf_col = 4'd2;   5'd5:  S_pf_col = 4'd3;
                                5'd6:  S_pf_col = 4'd4;   5'd7:  S_pf_col = 4'd4;
                                5'd8:  S_pf_col = 4'd5;   5'd9:  S_pf_col = 4'd6;
                                5'd10: S_pf_col = 4'd6;  5'd11: S_pf_col = 4'd7;
                                5'd12: S_pf_col = 4'd8;  5'd13: S_pf_col = 4'd8;
                                5'd14: S_pf_col = 4'd9;  5'd15: S_pf_col = 4'd10;
                                5'd16: S_pf_col = 4'd10; 5'd17: S_pf_col = 4'd11;
                                5'd18: S_pf_col = 4'd12; 5'd19: S_pf_col = 4'd12;
                                5'd20: S_pf_col = 4'd13; 5'd21: S_pf_col = 4'd14;
                                5'd22: S_pf_col = 4'd14; 5'd23: S_pf_col = 4'd15;
                                default: S_pf_col = 4'd0;
                            endcase
                            S_pf_row = F_osd_row24(S_pf_local_y);
                            S_font_active = 1'b1;
                        end
                    end
                    else if((S_dyn_x >= 12'd52) && (S_dyn_x < 12'd100) && (S_dyn_y >= 12'd4) && (S_dyn_y < 12'd20)) begin
                        if(S_dyn_x < 12'd68) begin
                            S_pf_char = CHAR_C;
                            S_pf_local_x = S_dyn_x - 12'd52;
                        end
                        else if(S_dyn_x < 12'd84) begin
                            S_pf_char = CHAR_N;
                            S_pf_local_x = S_dyn_x - 12'd68;
                        end
                        else begin
                            S_pf_char = CHAR_T;
                            S_pf_local_x = S_dyn_x - 12'd84;
                        end
                        S_pf_local_y = S_dyn_y - 12'd4;
                        S_pf_col = S_pf_local_x[3:0];
                        S_pf_row = S_pf_local_y[3:0];
                        S_font_active = 1'b1;
                    end
                    else if((S_dyn_x >= 12'd100) && (S_dyn_x < 12'd108) && (S_dyn_y >= 12'd4) && (S_dyn_y < 12'd20)) begin
                        S_pf_char = CHAR_COLON;
                        S_pf_local_x = S_dyn_x - 12'd100;
                        S_pf_local_y = S_dyn_y - 12'd4;
                        S_pf_scale_x = S_pf_local_x * 10'd16;
                        S_pf_col = S_pf_scale_x[6:3];   // /8 = >>3 (16/8=2px/列)
                        S_pf_row = S_pf_local_y[3:0];
                        S_font_active = 1'b1;
                    end

                    // Font hit is resolved after the synchronous ROM read.
                end

                // Decimal 6 digits starts at x=110. Each digit is 15x24.
                if((S_dyn_x >= 12'd110) && (S_dyn_x < 12'd200)) begin
                    if(S_dyn_x < 12'd125) begin
                        S_dyn_digit_idx = 4'd0;
                        S_dyn_digit_x = S_dyn_x - 12'd110;
                        S_dyn_dec_digit = S_cnt_d5;
                    end
                    else if(S_dyn_x < 12'd140) begin
                        S_dyn_digit_idx = 4'd1;
                        S_dyn_digit_x = S_dyn_x - 12'd125;
                        S_dyn_dec_digit = S_cnt_d4;
                    end
                    else if(S_dyn_x < 12'd155) begin
                        S_dyn_digit_idx = 4'd2;
                        S_dyn_digit_x = S_dyn_x - 12'd140;
                        S_dyn_dec_digit = S_cnt_d3;
                    end
                    else if(S_dyn_x < 12'd170) begin
                        S_dyn_digit_idx = 4'd3;
                        S_dyn_digit_x = S_dyn_x - 12'd155;
                        S_dyn_dec_digit = S_cnt_d2;
                    end
                    else if(S_dyn_x < 12'd185) begin
                        S_dyn_digit_idx = 4'd4;
                        S_dyn_digit_x = S_dyn_x - 12'd170;
                        S_dyn_dec_digit = S_cnt_d1;
                    end
                    else begin
                        S_dyn_digit_idx = 4'd5;
                        S_dyn_digit_x = S_dyn_x - 12'd185;
                        S_dyn_dec_digit = S_cnt_d0;
                    end

                    // Render decimal digits through unified 16x16 character library.
                    // Keep enlarged 15x24 box for readability.
                    if((S_dyn_digit_x < 12'd15) && (S_dyn_y < 12'd24)) begin
                        S_pf_char = CHAR_0 + {4'd0, S_dyn_dec_digit};
                        S_pf_local_x = S_dyn_digit_x[4:0];
                        S_pf_local_y = S_dyn_y[4:0];
                        // x*16/15: x=0..14 时 floor 恰为 x (16x<15x+15 恒成立) → col=x 精确等价
                        S_pf_col = S_pf_local_x[3:0];
                        // y*16/24 → 常数表 (TD 无除法器)
                        S_pf_row = F_osd_row24(S_pf_local_y);
                        S_font_active = 1'b1;
                        // Font hit is resolved after the synchronous ROM read.
                    end
                end
            end
                // ← 行1 块在此闭合 (修复: 原 begin 直到 L1122 才关, 行2-6 被包进行1 的 y 门控)

                // MODE:N D:123MS: fourteen complete 16-pixel character cells.
                // Missing, stale, or >999 ms measurements render D:---MS.
                if((S_x_2d >= DYN_OSD_X) && (S_x_2d < (DYN_OSD_X + 12'd224)) &&
                   (S_y_2d >= DYN2_OSD_Y) && (S_y_2d < (DYN2_OSD_Y + 12'd24))) begin
                    S_dyn_x = S_x_2d - DYN_OSD_X;
                    S_dyn_y = S_y_2d - DYN2_OSD_Y;
                    S_pf_local_y = F_osd_row24(S_dyn_y[4:0]);
                    // 字符选择 (每字符 16 宽)
                    if (S_dyn_x < 12'd16)       S_pf_char = 8'h4D; // M
                    else if (S_dyn_x < 12'd32)  S_pf_char = 8'h4F; // O
                    else if (S_dyn_x < 12'd48)  S_pf_char = 8'h44; // D
                    else if (S_dyn_x < 12'd64)  S_pf_char = 8'h45; // E
                    else if (S_dyn_x < 12'd80)  S_pf_char = 8'h3A; // :
                    else if (S_dyn_x < 12'd96)  S_pf_char = F_hex_char(I_algo_mode); // 0-5
                    else if (S_dyn_x < 12'd112) S_pf_char = 8'h20; // space
                    else if (S_dyn_x < 12'd128) S_pf_char = 8'h44; // D
                    else if (S_dyn_x < 12'd144) S_pf_char = 8'h3A; // :
                    else if (S_dyn_x < 12'd160) S_pf_char = S_latency_display_valid ? F_hex_char(S_latency_h) : 8'h2D;
                    else if (S_dyn_x < 12'd176) S_pf_char = S_latency_display_valid ? F_hex_char(S_latency_t) : 8'h2D;
                    else if (S_dyn_x < 12'd192) S_pf_char = S_latency_display_valid ? F_hex_char(S_latency_u) : 8'h2D;
                    else if (S_dyn_x < 12'd208) S_pf_char = 8'h4D; // M
                    else                       S_pf_char = 8'h53; // S
                    S_pf_col = S_dyn_x[3:0];
                    S_pf_row = S_pf_local_y;
                    // 查字库行位图 (osd_char_lib 已在文件下方函数 F_osd_char16_row)
                    S_font_active = 1'b1;
                    if(S_pf_on) begin
                        S_dyn_on = 1'b1;
                    end
                end
                // ---- 运动检测 OSD: "MOT:NNNNN" 第三行 ----
                // 位置: DYN_OSD_X..+144, DYN3_OSD_Y..+24。统一使用 9 个 16px 字符槽：
                // M O T : N N N N N。计数先转 BCD，保证板上显示为十进制 00000..65535。
                if(I_motion_enable &&
                   (S_x_2d >= DYN_OSD_X) && (S_x_2d < (DYN_OSD_X + 12'd144)) &&
                   (S_y_2d >= DYN3_OSD_Y) && (S_y_2d < (DYN3_OSD_Y + 12'd24))) begin
                    S_dyn_x = S_x_2d - DYN_OSD_X;
                    S_dyn_y = S_y_2d - DYN3_OSD_Y;
                    S_pf_local_y = F_osd_row24(S_dyn_y[4:0]);
                    if (S_dyn_x < 12'd16)       S_pf_char = 8'h4D; // M
                    else if (S_dyn_x < 12'd32)  S_pf_char = 8'h4F; // O
                    else if (S_dyn_x < 12'd48)  S_pf_char = 8'h54; // T
                    else if (S_dyn_x < 12'd64)  S_pf_char = 8'h3A; // :
                    else if (S_dyn_x < 12'd80)  S_pf_char = F_dec_char(S_motion_bcd_disp[19:16]); // 万位
                    else if (S_dyn_x < 12'd96)  S_pf_char = F_dec_char(S_motion_bcd_disp[15:12]); // 千位
                    else if (S_dyn_x < 12'd112) S_pf_char = F_dec_char(S_motion_bcd_disp[11:8]);  // 百位
                    else if (S_dyn_x < 12'd128) S_pf_char = F_dec_char(S_motion_bcd_disp[7:4]);   // 十位
                    else                        S_pf_char = F_dec_char(S_motion_bcd_disp[3:0]);    // 个位
                    S_pf_col = S_dyn_x[3:0];
                    S_pf_row = S_pf_local_y;
                    S_font_active = 1'b1;
                    if(S_pf_on) begin
                        S_dyn_on = 1'b1;
                    end
                end
                
                // ---- 跟踪 OSD 行: R 目标 (x,y hex + 形状) ----
                if(I_track_enable &&
                   (S_x_2d >= DYN_OSD_X) && (S_x_2d < (DYN_OSD_X + 12'd192)) &&
                   (S_y_2d >= DYN4_OSD_Y) && (S_y_2d < (DYN4_OSD_Y + 12'd24))) begin
                    S_dyn_x = S_x_2d - DYN_OSD_X;
                    S_dyn_y = S_y_2d - DYN4_OSD_Y;
                    S_pf_local_y = F_osd_row24(S_dyn_y[4:0]);
                    if (S_dyn_x < 12'd16)       S_pf_char = 8'h52; // R
                    else if (S_dyn_x < 12'd32)  S_pf_char = 8'h3A; // :
                    else if (S_dyn_x < 12'd48)  S_pf_char = S_t0_v_disp ? F_hex_char({1'b0,S_t0_x_disp[10:8]}) : 8'h2D;
                    else if (S_dyn_x < 12'd64)  S_pf_char = S_t0_v_disp ? F_hex_char(S_t0_x_disp[7:4]) : 8'h2D;
                    else if (S_dyn_x < 12'd80)  S_pf_char = S_t0_v_disp ? F_hex_char(S_t0_x_disp[3:0]) : 8'h2D;
                    else if (S_dyn_x < 12'd96) S_pf_char = 8'h2C; // ,
                    else if (S_dyn_x < 12'd112) S_pf_char = S_t0_v_disp ? F_hex_char(S_t0_y_disp[9:8]) : 8'h2D;
                    else if (S_dyn_x < 12'd128) S_pf_char = S_t0_v_disp ? F_hex_char(S_t0_y_disp[7:4]) : 8'h2D;
                    else if (S_dyn_x < 12'd144) S_pf_char = S_t0_v_disp ? F_hex_char(S_t0_y_disp[3:0]) : 8'h2D;
                    else if (S_dyn_x < 12'd160) S_pf_char = 8'h20; // sp
                    else if (S_dyn_x < 12'd176) S_pf_char = S_t0_v_disp ? ((S_t0_sh_disp==2'd0)?8'h43:(S_t0_sh_disp==2'd1)?8'h53:(S_t0_sh_disp==2'd2)?8'h42:8'h54) : 8'h2D; // C/S/B/T
                    else                        S_pf_char = S_t0_v_disp ? ((S_t0_sh_disp==2'd0)?8'h49:(S_t0_sh_disp==2'd1)?8'h51:(S_t0_sh_disp==2'd2)?8'h41:8'h52) : 8'h2D; // I/Q/A/R
                    S_pf_col = S_dyn_x[3:0];
                    S_pf_row = S_pf_local_y;
                    S_font_active = 1'b1;
                    if(S_pf_on) begin
                        S_dyn_on = 1'b1;
                    end
                end
                // ---- 跟踪 OSD 行: G 目标 (x,y hex + 形状) ----
                if(I_track_enable &&
                   (S_x_2d >= DYN_OSD_X) && (S_x_2d < (DYN_OSD_X + 12'd192)) &&
                   (S_y_2d >= DYN5_OSD_Y) && (S_y_2d < (DYN5_OSD_Y + 12'd24))) begin
                    S_dyn_x = S_x_2d - DYN_OSD_X;
                    S_dyn_y = S_y_2d - DYN5_OSD_Y;
                    S_pf_local_y = F_osd_row24(S_dyn_y[4:0]);
                    if (S_dyn_x < 12'd16)       S_pf_char = 8'h47; // G
                    else if (S_dyn_x < 12'd32)  S_pf_char = 8'h3A; // :
                    else if (S_dyn_x < 12'd48)  S_pf_char = S_t1_v_disp ? F_hex_char({1'b0,S_t1_x_disp[10:8]}) : 8'h2D;
                    else if (S_dyn_x < 12'd64)  S_pf_char = S_t1_v_disp ? F_hex_char(S_t1_x_disp[7:4]) : 8'h2D;
                    else if (S_dyn_x < 12'd80)  S_pf_char = S_t1_v_disp ? F_hex_char(S_t1_x_disp[3:0]) : 8'h2D;
                    else if (S_dyn_x < 12'd96) S_pf_char = 8'h2C; // ,
                    else if (S_dyn_x < 12'd112) S_pf_char = S_t1_v_disp ? F_hex_char(S_t1_y_disp[9:8]) : 8'h2D;
                    else if (S_dyn_x < 12'd128) S_pf_char = S_t1_v_disp ? F_hex_char(S_t1_y_disp[7:4]) : 8'h2D;
                    else if (S_dyn_x < 12'd144) S_pf_char = S_t1_v_disp ? F_hex_char(S_t1_y_disp[3:0]) : 8'h2D;
                    else if (S_dyn_x < 12'd160) S_pf_char = 8'h20; // sp
                    else if (S_dyn_x < 12'd176) S_pf_char = S_t1_v_disp ? ((S_t1_sh_disp==2'd0)?8'h43:(S_t1_sh_disp==2'd1)?8'h53:(S_t1_sh_disp==2'd2)?8'h42:8'h54) : 8'h2D; // C/S/B/T
                    else                        S_pf_char = S_t1_v_disp ? ((S_t1_sh_disp==2'd0)?8'h49:(S_t1_sh_disp==2'd1)?8'h51:(S_t1_sh_disp==2'd2)?8'h41:8'h52) : 8'h2D; // I/Q/A/R
                    S_pf_col = S_dyn_x[3:0];
                    S_pf_row = S_pf_local_y;
                    S_font_active = 1'b1;
                    if(S_pf_on) begin
                        S_dyn_on = 1'b1;
                    end
                end
                // ---- 跟踪 OSD 行: B 目标 (x,y hex + 形状) ----
                if(I_track_enable &&
                   (S_x_2d >= DYN_OSD_X) && (S_x_2d < (DYN_OSD_X + 12'd192)) &&
                   (S_y_2d >= DYN6_OSD_Y) && (S_y_2d < (DYN6_OSD_Y + 12'd24))) begin
                    S_dyn_x = S_x_2d - DYN_OSD_X;
                    S_dyn_y = S_y_2d - DYN6_OSD_Y;
                    S_pf_local_y = F_osd_row24(S_dyn_y[4:0]);
                    if (S_dyn_x < 12'd16)       S_pf_char = 8'h42; // B
                    else if (S_dyn_x < 12'd32)  S_pf_char = 8'h3A; // :
                    else if (S_dyn_x < 12'd48)  S_pf_char = S_t2_v_disp ? F_hex_char({1'b0,S_t2_x_disp[10:8]}) : 8'h2D;
                    else if (S_dyn_x < 12'd64)  S_pf_char = S_t2_v_disp ? F_hex_char(S_t2_x_disp[7:4]) : 8'h2D;
                    else if (S_dyn_x < 12'd80)  S_pf_char = S_t2_v_disp ? F_hex_char(S_t2_x_disp[3:0]) : 8'h2D;
                    else if (S_dyn_x < 12'd96) S_pf_char = 8'h2C; // ,
                    else if (S_dyn_x < 12'd112) S_pf_char = S_t2_v_disp ? F_hex_char(S_t2_y_disp[9:8]) : 8'h2D;
                    else if (S_dyn_x < 12'd128) S_pf_char = S_t2_v_disp ? F_hex_char(S_t2_y_disp[7:4]) : 8'h2D;
                    else if (S_dyn_x < 12'd144) S_pf_char = S_t2_v_disp ? F_hex_char(S_t2_y_disp[3:0]) : 8'h2D;
                    else if (S_dyn_x < 12'd160) S_pf_char = 8'h20; // sp
                    else if (S_dyn_x < 12'd176) S_pf_char = S_t2_v_disp ? ((S_t2_sh_disp==2'd0)?8'h43:(S_t2_sh_disp==2'd1)?8'h53:(S_t2_sh_disp==2'd2)?8'h42:8'h54) : 8'h2D; // C/S/B/T
                    else                        S_pf_char = S_t2_v_disp ? ((S_t2_sh_disp==2'd0)?8'h49:(S_t2_sh_disp==2'd1)?8'h51:(S_t2_sh_disp==2'd2)?8'h41:8'h52) : 8'h2D; // I/Q/A/R
                    S_pf_col = S_dyn_x[3:0];
                    S_pf_row = S_pf_local_y;
                    S_font_active = 1'b1;
                    if(S_pf_on) begin
                        S_dyn_on = 1'b1;
                    end
                end
                // ---- 数字识别引导框与结果: NUM:d C:confidence ----
                // 算法在相机域完成，显示域只锁存结果和绘制固定框，不重新读取
                // 识别统计。引导框四边使用亮绿色细线，便于上板摆放数字卡。
                if(I_digit_enable &&
                   (S_x_2d == DIGIT_BOX_X0 || S_x_2d == DIGIT_BOX_X1) &&
                   (S_y_2d >= DIGIT_BOX_Y0) && (S_y_2d <= DIGIT_BOX_Y1)) begin
                    S_digit_box_on = 1'b1;
                end else if(I_digit_enable &&
                            (S_y_2d == DIGIT_BOX_Y0 || S_y_2d == DIGIT_BOX_Y1) &&
                            (S_x_2d >= DIGIT_BOX_X0) && (S_x_2d <= DIGIT_BOX_X1)) begin
                    S_digit_box_on = 1'b1;
                end

                // Draw only a confirmed hand's measured silhouette extent;
                // the old central guide box no longer describes the detector.
                if (I_hand_enable && S_hand_box_valid_disp &&
                    (((S_x_2d == S_hand_xmin_disp || S_x_2d == S_hand_xmax_disp) &&
                      S_y_2d >= S_hand_ymin_disp && S_y_2d <= S_hand_ymax_disp) ||
                     ((S_y_2d == S_hand_ymin_disp || S_y_2d == S_hand_ymax_disp) &&
                      S_x_2d >= S_hand_xmin_disp && S_x_2d <= S_hand_xmax_disp)))
                    S_hand_box_on = 1'b1;

                // Edge hit is precomputed one pipeline stage earlier, aligned
                // with S_x_2d/S_y_2d, to keep the OSD color mux shallow.
                if (I_aruco_enable && S_aruco_valid_disp && !S_logo_hit && S_aruco_edge_hit_2d)
                    S_aruco_box_on = 1'b1;

                // The result row uses a small independent 7-segment renderer.
                // Keeping it out of the shared 16x16 font mux avoids a long
                // combinational path (and TD's false comb-loop warning) while
                // still making the ID and confidence visible on the board.
                if(I_digit_enable &&
                   (S_x_2d >= DYN_OSD_X) && (S_x_2d < (DYN_OSD_X + 12'd176)) &&
                   (S_y_2d >= DYN8_OSD_Y) && (S_y_2d < (DYN8_OSD_Y + 12'd24))) begin
                    S_dyn_x = S_x_2d - DYN_OSD_X;
                    S_dyn_y = S_y_2d - DYN8_OSD_Y;
                    // Three 16x24 cells: ID, confidence high nibble, low nibble.
                    if      (S_dyn_x < 12'd16)  S_dyn_seg = S_digit_v_disp ? F_hex7seg(S_digit_id_disp) : 7'd0;
                    else if (S_dyn_x < 12'd32)  S_dyn_seg = 7'd0;
                    else if (S_dyn_x < 12'd48)  S_dyn_seg = S_digit_v_disp ? F_hex7seg(S_digit_confidence_disp[7:4]) : 7'd0;
                    else if (S_dyn_x < 12'd64)  S_dyn_seg = 7'd0;
                    else if (S_dyn_x < 12'd80)  S_dyn_seg = S_digit_v_disp ? F_hex7seg(S_digit_confidence_disp[3:0]) : 7'd0;
                    else                         S_dyn_seg = 7'd0;

                    // Segment geometry in the 16x24 cell.  Bit order is
                    // {a,b,c,d,e,f,g}, matching F_hex7seg above.
                    if      ((S_dyn_y >= 12'd2)  && (S_dyn_y < 12'd5)  && (S_dyn_x[3:0] >= 4'd3)  && (S_dyn_x[3:0] < 4'd13)) S_digit_seg_on = S_dyn_seg[6];
                    else if ((S_dyn_y >= 12'd10) && (S_dyn_y < 12'd13) && (S_dyn_x[3:0] >= 4'd3)  && (S_dyn_x[3:0] < 4'd13)) S_digit_seg_on = S_dyn_seg[0];
                    else if ((S_dyn_y >= 12'd20) && (S_dyn_y < 12'd23) && (S_dyn_x[3:0] >= 4'd3)  && (S_dyn_x[3:0] < 4'd13)) S_digit_seg_on = S_dyn_seg[3];
                    else if ((S_dyn_x[3:0] >= 4'd2)  && (S_dyn_x[3:0] < 4'd5)  && (S_dyn_y >= 12'd3)  && (S_dyn_y < 12'd11)) S_digit_seg_on = S_dyn_seg[1];
                    else if ((S_dyn_x[3:0] >= 4'd11) && (S_dyn_x[3:0] < 4'd14) && (S_dyn_y >= 12'd3)  && (S_dyn_y < 12'd11)) S_digit_seg_on = S_dyn_seg[5];
                    else if ((S_dyn_x[3:0] >= 4'd2)  && (S_dyn_x[3:0] < 4'd5)  && (S_dyn_y >= 12'd12) && (S_dyn_y < 12'd21)) S_digit_seg_on = S_dyn_seg[2];
                    else if ((S_dyn_x[3:0] >= 4'd11) && (S_dyn_x[3:0] < 4'd14) && (S_dyn_y >= 12'd12) && (S_dyn_y < 12'd21)) S_digit_seg_on = S_dyn_seg[4];

                    if(S_digit_seg_on) begin
                        S_dyn_on = 1'b1;
                    end
                end

                // ---- HDMI 输出帧率 OSD: "FPS:xx" 第九行 ----
                // FPS 使用独立的两位 BCD 寄存器；字符槽保持 16px 对齐，
                // 不把除法或长组合计数逻辑放入视频数据通路。
                if((S_x_2d >= DYN_OSD_X) && (S_x_2d < (DYN_OSD_X + 12'd96)) &&
                   (S_y_2d >= DYN9_OSD_Y) && (S_y_2d < (DYN9_OSD_Y + 12'd24))) begin
                    S_dyn_x = S_x_2d - DYN_OSD_X;
                    S_dyn_y = S_y_2d - DYN9_OSD_Y;
                    S_pf_local_y = F_osd_row24(S_dyn_y[4:0]);
                    if (S_dyn_x < 12'd16)       S_pf_char = 8'h46; // F
                    else if (S_dyn_x < 12'd32)  S_pf_char = 8'h50; // P
                    else if (S_dyn_x < 12'd48)  S_pf_char = 8'h53; // S
                    else if (S_dyn_x < 12'd64)  S_pf_char = 8'h3A; // :
                    else if (S_dyn_x < 12'd80)  S_pf_char = F_dec_char(S_fps_display_tens);
                    else                        S_pf_char = F_dec_char(S_fps_display_units);
                    S_pf_col = S_dyn_x[3:0];
                    S_pf_row = S_pf_local_y;
                    S_font_active = 1'b1;
                    if(S_pf_on) begin
                        S_dyn_on = 1'b1;
                    end
                end
                // H:F / H:P / H:O / H:-, followed by the detected tip count.
                // A newly seen class needs two matching frames; ambiguous
                // two-tip masks and no-hand frames display '-'.
                if (I_hand_enable &&
                    S_x_2d >= HAND_OSD_X && S_x_2d < HAND_OSD_X + 12'd112 &&
                    S_y_2d >= DYN10_OSD_Y && S_y_2d < DYN10_OSD_Y + 12'd24) begin
                    S_dyn_x = S_x_2d - HAND_OSD_X;
                    S_dyn_y = S_y_2d - DYN10_OSD_Y;
                    S_pf_local_y = F_osd_row24(S_dyn_y[4:0]);
                    if (S_dyn_x < 12'd16) S_pf_char = 8'h48; // H
                    else if (S_dyn_x < 12'd32) S_pf_char = 8'h3A; // :
                    else if (S_dyn_x < 12'd48)
                        S_pf_char = (S_hand_id_disp == 2'd1) ? 8'h46 :
                                    (S_hand_id_disp == 2'd2) ? 8'h50 :
                                    (S_hand_id_disp == 2'd3) ? 8'h4F : 8'h2D;
                    else if (S_dyn_x < 12'd64) S_pf_char = 8'h20;
                    else if (S_dyn_x < 12'd80) S_pf_char = 8'h54; // T
                    else if (S_dyn_x < 12'd96) S_pf_char = 8'h3A;
                    else S_pf_char = F_hex_char({1'b0,S_hand_tips_disp});
                    S_pf_col = S_dyn_x[3:0];
                    S_pf_row = S_pf_local_y;
                    S_font_active = 1'b1;
                    // Font hit is resolved after the synchronous ROM read.
                end
                // Attach "ID:nnn" to the detected rectangle. It is placed just
                // above the box, falling inside the top edge only for markers
                // in the first 24 image rows; x is clamped to the active frame.
                if (I_aruco_enable && S_aruco_valid_disp && !S_logo_hit) begin
                    S_aruco_label_x = (S_aruco_xmin_disp <= (IMG_WIDTH-96)) ?
                                      {1'b0,S_aruco_xmin_disp} : (IMG_WIDTH-96);
                    S_aruco_label_y = (S_aruco_ymin_disp >= 11'd24) ?
                                      ({1'b0,S_aruco_ymin_disp}-12'd24) :
                                      ({1'b0,S_aruco_ymin_disp}+12'd2);
                    if ((S_x_2d >= S_aruco_label_x) &&
                        (S_x_2d < (S_aruco_label_x + 12'd96)) &&
                        (S_y_2d >= S_aruco_label_y) &&
                        (S_y_2d < (S_aruco_label_y + 12'd24))) begin
                        S_dyn_x = S_x_2d - S_aruco_label_x;
                        S_dyn_y = S_y_2d - S_aruco_label_y;
                        S_pf_local_y = F_osd_row24(S_dyn_y[4:0]);
                        if      (S_dyn_x < 12'd16) S_pf_char = 8'h49; // I
                        else if (S_dyn_x < 12'd32) S_pf_char = 8'h44; // D
                        else if (S_dyn_x < 12'd48) S_pf_char = 8'h3A; // :
                        else if (S_dyn_x < 12'd64) S_pf_char = F_dec_char(S_aruco_id_bcd_disp[11:8]);
                        else if (S_dyn_x < 12'd80) S_pf_char = F_dec_char(S_aruco_id_bcd_disp[7:4]);
                        else                       S_pf_char = F_dec_char(S_aruco_id_bcd_disp[3:0]);
                        S_pf_col = S_dyn_x[3:0];
                        S_pf_row = S_pf_local_y;
                        S_font_active = 1'b1;
                    end
                end
                // ---- 扩展结束 ----

                // 各文字区域只产生命中位，最后统一选择颜色，避免对同一个
                // 24 位颜色总线形成串行优先级链。覆盖顺序：
                // 文字/数字结果 > 数字引导框 > 三色目标框 > Logo。
                if(S_track_box_on) begin
                    S_osd_hit = 1'b1;
                    S_osd_color = S_track_box_color;
                end
                if(S_digit_box_on) begin
                    S_osd_hit = 1'b1;
                    S_osd_color = 24'h20ff40;
                end
                if (S_hand_box_on) begin
                    S_osd_hit = 1'b1;
                    S_osd_color = 24'hff9a20;
                end
                if (S_aruco_box_on) begin
                    S_osd_hit = 1'b1;
                    S_osd_color = 24'h00ffff;
                end
                if(S_dyn_on) begin
                    S_osd_hit = 1'b1;
                    S_osd_color = COLOR_DYN_TEXT;
                end
            end
        end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_video_vsync_1d <= 1'b0;
            S_video_vsync_2d <= 1'b0;
            S_video_hsync_1d <= 1'b0;
            S_video_hsync_2d <= 1'b0;
            S_video_de_1d    <= 1'b0;
            S_video_de_2d    <= 1'b0;
            S_video_vsync_3d <= 1'b0;
            S_video_hsync_3d <= 1'b0;
            S_video_de_3d    <= 1'b0;
            S_video_data_3d  <= 24'd0;
            S_video_bright_3d<= 24'd0;
            S_font_active_3d <= 1'b0;
            S_font_col_3d <= 4'd0;
            S_osd_hit_3d     <= 1'b0;
            S_osd_color_3d   <= 24'd0;
            S_logo_hit_3d    <= 1'b0;
            S_logo_color_3d  <= 24'd0;
            S_x_3d           <= 12'd0;
            S_video_vsync_4d <= 1'b0;
            S_video_hsync_4d <= 1'b0;
            S_video_de_4d    <= 1'b0;
            S_video_data_4d  <= 24'd0;
            S_osd_hit_4d     <= 1'b0;
            S_osd_color_4d   <= 24'd0;
            S_logo_hit_4d    <= 1'b0;
            S_logo_color_4d  <= 24'd0;
            S_x_4d           <= 12'd0;
            S_video_vsync_5d <= 1'b0;
            S_video_hsync_5d <= 1'b0;
            S_video_de_5d    <= 1'b0;
            S_video_data_5d  <= 24'd0;
            S_osd_hit_5d     <= 1'b0;
            S_osd_color_5d   <= 24'd0;
            S_logo_hit_5d    <= 1'b0;
            S_logo_color_5d  <= 24'd0;
            S_x_5d           <= 12'd0;
            O_hdmi_vsync     <= 1'b0;
            O_hdmi_hsync     <= 1'b0;
            O_hdmi_de        <= 1'b0;
            O_hdmi_data      <= 24'd0;
            O_hdmi_clean_data<= 24'd0;
        end
        else begin
            S_video_vsync_1d <= I_video_vsync;
            S_video_vsync_2d <= S_video_vsync_1d;
            S_video_vsync_3d <= S_video_vsync_2d;
            S_video_vsync_4d <= S_video_vsync_3d;
            S_video_vsync_5d <= S_video_vsync_4d;
            O_hdmi_vsync     <= S_video_vsync_5d;

            S_video_hsync_1d <= I_video_hsync;
            S_video_hsync_2d <= S_video_hsync_1d;
            S_video_hsync_3d <= S_video_hsync_2d;
            S_video_hsync_4d <= S_video_hsync_3d;
            S_video_hsync_5d <= S_video_hsync_4d;
            O_hdmi_hsync     <= S_video_hsync_5d;

            S_video_de_1d    <= I_video_de;
            S_video_de_2d    <= S_video_de_1d;
            S_video_de_3d    <= S_video_de_2d;
            S_video_de_4d    <= S_video_de_3d;
            S_video_de_5d    <= S_video_de_4d;
            O_hdmi_de        <= S_video_de_5d;
            // Camera/ISP RGB aligned with the HDMI output, before diagnostic
            // boxes, logos, or glyphs are composited over the picture.
            O_hdmi_clean_data<= S_video_display_3d;
            S_video_data_1d  <= I_video_rd_data;
            S_video_data_2d  <= S_video_data_1d;
            S_video_data_3d  <= S_video_data_2d;
            S_video_bright_3d<= {F_bright_3_2(S_video_data_2d[23:16]),
                                  F_bright_3_2(S_video_data_2d[15:8]),
                                  F_bright_3_2(S_video_data_2d[7:0])};
            S_video_data_4d  <= S_video_data_3d;
            S_video_data_5d  <= S_video_data_4d;
            S_font_active_3d <= S_font_active;
            S_font_col_3d <= S_pf_col;
            S_osd_hit_3d     <= S_osd_hit;
            S_osd_color_3d   <= S_osd_color;
            S_logo_hit_3d    <= S_logo_hit;
            S_logo_color_3d  <= S_logo_color;
            S_x_3d           <= S_x_2d;
            // ROM uses stage 3; text composition uses stage 4: no added latency.
            S_osd_hit_4d <= S_osd_hit_3d ||
                (S_font_active_3d && S_pf_row_bits[15-S_font_col_3d]);
            S_osd_color_4d <=
                (S_font_active_3d && S_pf_row_bits[15-S_font_col_3d]) ?
                COLOR_DYN_TEXT : S_osd_color_3d;
            S_logo_hit_4d    <= S_logo_hit_3d;
            // Palette ROM's registered RGB is already aligned to stage 3.
            S_logo_color_4d  <= S_logo_pixel[23:0];
            S_x_4d           <= S_x_3d;
            S_osd_hit_5d     <= S_osd_hit_4d;
            S_osd_color_5d   <= S_osd_color_4d;
            S_logo_hit_5d    <= S_logo_hit_4d;
            S_logo_color_5d  <= S_logo_color_4d;
            S_x_5d           <= S_x_4d;

            if(DEBUG_MODE == 1) begin
                if(S_video_de_5d) begin
                    if(S_x_5d < 12'd128)
                        O_hdmi_data <= 24'hff0000;
                    else if(S_x_5d < 12'd256)
                        O_hdmi_data <= 24'h00ff00;
                    else if(S_x_5d < 12'd384)
                        O_hdmi_data <= 24'h0000ff;
                    else if(S_x_5d < 12'd512)
                        O_hdmi_data <= 24'hffff00;
                    else if(S_x_5d < 12'd640)
                        O_hdmi_data <= 24'h00ffff;
                    else if(S_x_5d < 12'd768)
                        O_hdmi_data <= 24'hff00ff;
                    else if(S_x_5d < 12'd896)
                        O_hdmi_data <= 24'hffffff;
                    else
                        O_hdmi_data <= 24'h202020;
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end
            else if(DEBUG_MODE == 2) begin
                if(S_video_de_5d) begin
                    case (I_debug_status)
                        4'b0000: O_hdmi_data <= 24'h000000;
                        4'b0001: O_hdmi_data <= 24'hff0000;
                        4'b0011: O_hdmi_data <= 24'hffff00;
                        4'b0111: O_hdmi_data <= 24'h00ff00;
                        4'b1111: O_hdmi_data <= S_video_data_3d;
                        default: O_hdmi_data <= 24'h0000ff;
                    endcase
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end
            else if(DEBUG_MODE == 3) begin
                if(S_video_de_5d) begin
                    if(S_x_5d < 12'd256)
                        O_hdmi_data <= I_debug_status[0] ? 24'hff8000 : 24'h201000;
                    else if(S_x_5d < 12'd512)
                        O_hdmi_data <= I_debug_status[1] ? 24'hffff00 : 24'h202000;
                    else if(S_x_5d < 12'd768)
                        O_hdmi_data <= I_debug_status[2] ? 24'hff0000 : 24'h200000;
                    else
                        O_hdmi_data <= I_debug_status[3] ? 24'h00ffff : 24'h002020;
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end
            else begin
                if(S_logo_hit_5d)
                    O_hdmi_data <= S_logo_color_5d;
                else if(S_osd_hit_5d)
                    O_hdmi_data <= S_osd_color_5d;
                else
                    O_hdmi_data <= S_video_display_3d;
            end
        end
    end

endmodule
