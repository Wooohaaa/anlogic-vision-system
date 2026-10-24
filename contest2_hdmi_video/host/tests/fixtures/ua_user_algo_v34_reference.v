// ua_user_algo_96.v — B2: 用户算法模块 (七模式)
// 接口与时序约定完全对齐官方 edge_detect_96 (见架构笔记 §9):
//   - 96bit AXI-Stream, 4 像素/拍, tuser 帧首/tlast 行尾
//   - O_* = I_* 固定延迟 8 拍, 帧内流水无气泡, O_tready = I_tready 直通
// 模式 (I_mode, 帧边界生效: tuser 拍锁存):
//   0 = 直通 (等价 lab1 无算法)
//   1 = 灰度 (每像素 (R+2G+B)>>2 回写 RGB)
//   2 = Sobel (边缘强度图, 4px 组均值域 3x3, 输出 |gx|+|gy| 缩放)
//   3 = 二值化 (组均值 > 阈值 → 白, 否则黑)
//   4 = 素描 (255 - sobel_v, 白底黑线)
//   5 = 浮雕 (对角差分 + 128)
//   6 = 卡通化 (保色相亮度量化 + 饱和度增强 + Sobel 黑色描边)
// 全零 DSP (移位加实现)。灰度 Sobel 行缓存推断为 block ram。
// 阅读入口：先看 mode_r 的帧首锁存，再看 x_grp/y_pos 和行缓存，最后看
// stream_mode_d8 的 case 输出选择；不要一开始就钻进 Sobel 算式。
`timescale 1ns/1ps
module ua_user_algo_v34_reference #(
    parameter IMG_WIDTH   = 1280,
    parameter IMG_HEIGHT  = 720,
    parameter BIN_THRESHOLD = 8'd128,
    // The Sobel magnitude is scaled by 8 (sobel_v = |gx|+|gy| >> 3).
    // A 16 threshold retains low-contrast contours that were lost at 28/40,
    // while the stronger threshold still suppresses isolated dark noise.
    parameter CART_EDGE_THRESHOLD = 8'd16,
    // Low-threshold cartoon edges are kept when they persist across adjacent
    // 4-pixel groups; this stronger level always passes as a true contour.
    parameter CART_EDGE_STRONG_THRESHOLD = 8'd24,
    // Color path keeps the original hue and uses a tone curve plus a
    // piecewise saturation gain; Sobel/edge parameters above are independent.
    parameter integer CART_COLOR_SAT_MID_SHIFT = 2,
    parameter integer CART_COLOR_SAT_HI_SHIFT  = 3
)(
    input               I_clk,
    input               I_rst_n,
    input               I_tlast,
    input               I_tuser,
    input      [95:0]   I_tdata,
    input               I_tvalid,
    input      [2:0]    I_mode,        // 模式选择 (帧边界锁存)
    input               I_tready,
    output reg          O_tlast,
    output reg          O_tuser,
    output reg [95:0]   O_tdata,
    output reg          O_tvalid,
    output              O_tready
);
    assign O_tready = I_tready;

    // ---- 模式锁存: 帧边界生效 ----
    // I_mode 来自按键域 (已 2FF 同步到本时钟域), 在 tuser 拍锁存
    // mode_d1 = 锁存前预看 (供流水对齐), mode_r = 当前帧工作模式
    reg [2:0] mode_r, mode_d1, mode_d2, mode_d3;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            mode_r <= 3'd0; mode_d1 <= 3'd0; mode_d2 <= 3'd0; mode_d3 <= 3'd0;
        end else begin
            mode_d1 <= I_mode;
            mode_d2 <= mode_d1;
            mode_d3 <= mode_d2;
            if (I_tvalid && I_tuser)
                mode_r <= mode_d1;    // 帧首锁存 (2 拍同步余量)

        end
    end

    // ---- 源流/Sobel 固定延迟对齐 ----
    // 实测 Sobel 数据路径比原两拍源流再深 6 个 96-bit 数据拍。边带、模式
    // 及浅流水模式数据统一补齐到 8 拍，避免边缘相对彩色底图右移 24 像素。
    reg [95:0] data_d1, data_d2;
    reg [7:0]  gray0_d1, gray0_d2, gray1_d1, gray1_d2;
    reg [7:0]  gray2_d1, gray2_d2, gray3_d1, gray3_d2;
    reg        valid_d1, valid_d2, user_d1, user_d2, last_d1, last_d2;
    reg [2:0]  stream_mode_d1, stream_mode_d2;
    reg [10:0] stream_x_d1, stream_x_d2, stream_y_d1, stream_y_d2;
    reg [95:0] shallow_d3, shallow_d4, shallow_d5, shallow_d6, shallow_d7, shallow_d8;
    reg        valid_d3, valid_d4, valid_d5, valid_d6, valid_d7, valid_d8;
    reg        user_d3, user_d4, user_d5, user_d6, user_d7, user_d8;
    reg        last_d3, last_d4, last_d5, last_d6, last_d7, last_d8;
    reg [2:0]  stream_mode_d3, stream_mode_d4, stream_mode_d5, stream_mode_d6, stream_mode_d7, stream_mode_d8;
    reg [10:0] stream_x_d3, stream_x_d4, stream_x_d5, stream_x_d6, stream_x_d7, stream_x_d8;
    reg [10:0] stream_y_d3, stream_y_d4, stream_y_d5, stream_y_d6, stream_y_d7, stream_y_d8;
    wire [2:0] stream_mode_in = I_tuser ? mode_d1 : mode_r;

    // ---- 4 像素拆包 + 灰度 (R+2G+B)>>2 ----
    wire [23:0] pix0 = I_tdata[95:72];
    wire [23:0] pix1 = I_tdata[71:48];
    wire [23:0] pix2 = I_tdata[47:24];
    wire [23:0] pix3 = I_tdata[23:0];

    wire [9:0] g0_sum = {2'b00, pix0[23:16]} + {1'b0, pix0[15:8], 1'b0} + {2'b00, pix0[7:0]};
    wire [9:0] g1_sum = {2'b00, pix1[23:16]} + {1'b0, pix1[15:8], 1'b0} + {2'b00, pix1[7:0]};
    wire [9:0] g2_sum = {2'b00, pix2[23:16]} + {1'b0, pix2[15:8], 1'b0} + {2'b00, pix2[7:0]};
    wire [9:0] g3_sum = {2'b00, pix3[23:16]} + {1'b0, pix3[15:8], 1'b0} + {2'b00, pix3[7:0]};

    wire [7:0] gray0 = g0_sum[9:2];
    wire [7:0] gray1 = g1_sum[9:2];
    wire [7:0] gray2 = g2_sum[9:2];
    wire [7:0] gray3 = g3_sum[9:2];

    // ---- Anime 风格颜色塑形 ----
    // 目标颜色风格：不改变色相，只做亮度塑形、非均匀量化和中间调
    // 饱和度增强。该函数只作用于 mode 6 的底色，Sobel 描边支路完全独立。
    function [23:0] F_cartoon_color;
        input [23:0] p;
        input [7:0]  y;
        reg [7:0] r, g, b;
        reg [7:0] y_curve, y_quant;
        reg signed [9:0] dr, dg, db;
        reg signed [10:0] yq_s, dr_s, dg_s, db_s;
        reg signed [10:0] r_adj, g_adj, b_adj;
        reg [7:0] rr, gg, bb;
        begin
            r = p[23:16];
            g = p[15:8];
            b = p[7:0];

            // 16 段 S 曲线：保留深色层次，提亮中间调，压住高光。
            case (y[7:4])
                4'h0: y_curve = 8'd0;
                4'h1: y_curve = 8'd12;
                4'h2: y_curve = 8'd24;
                4'h3: y_curve = 8'd40;
                4'h4: y_curve = 8'd58;
                4'h5: y_curve = 8'd78;
                4'h6: y_curve = 8'd99;
                4'h7: y_curve = 8'd120;
                4'h8: y_curve = 8'd141;
                4'h9: y_curve = 8'd161;
                4'hA: y_curve = 8'd180;
                4'hB: y_curve = 8'd198;
                4'hC: y_curve = 8'd215;
                4'hD: y_curve = 8'd231;
                4'hE: y_curve = 8'd244;
                default: y_curve = 8'd255;
            endcase

            // 10 个亮度中心：比等距量化更适合天空、道路和暗部层次。
            if      (y_curve < 8'd8)   y_quant = 8'd4;
            else if (y_curve < 8'd24)  y_quant = 8'd16;
            else if (y_curve < 8'd44)  y_quant = 8'd32;
            else if (y_curve < 8'd68)  y_quant = 8'd56;
            else if (y_curve < 8'd96)  y_quant = 8'd82;
            else if (y_curve < 8'd128) y_quant = 8'd112;
            else if (y_curve < 8'd164) y_quant = 8'd146;
            else if (y_curve < 8'd204) y_quant = 8'd184;
            else if (y_curve < 8'd236) y_quant = 8'd220;
            else                      y_quant = 8'd248;

            // 围绕量化亮度保留原 RGB 色差，避免独立 RGB 查表造成色相跳变。
            dr = $signed({1'b0,r}) - $signed({1'b0,y});
            dg = $signed({1'b0,g}) - $signed({1'b0,y});
            db = $signed({1'b0,b}) - $signed({1'b0,y});
            // 先扩展到 11 位，避免 y_quant + 色差 + 增益项在 10 位表达式中回绕。
            yq_s = $signed({1'b0,y_quant});
            dr_s = dr;
            dg_s = dg;
            db_s = db;
            if (y < 8'd40) begin
                // 暗部不放大色度，降低高增益摄像头彩噪。
                r_adj = yq_s + dr_s;
                g_adj = yq_s + dg_s;
                b_adj = yq_s + db_s;
            end else if (y < 8'd200) begin
                // 中间调 ×1.25，移位加法替代乘法器。
                r_adj = yq_s + dr_s + (dr_s >>> CART_COLOR_SAT_MID_SHIFT);
                g_adj = yq_s + dg_s + (dg_s >>> CART_COLOR_SAT_MID_SHIFT);
                b_adj = yq_s + db_s + (db_s >>> CART_COLOR_SAT_MID_SHIFT);
            end else begin
                // 高光只做温和增强，避免天空和白色物体溢出。
                r_adj = yq_s + dr_s + (dr_s >>> CART_COLOR_SAT_HI_SHIFT);
                g_adj = yq_s + dg_s + (dg_s >>> CART_COLOR_SAT_HI_SHIFT);
                b_adj = yq_s + db_s + (db_s >>> CART_COLOR_SAT_HI_SHIFT);
            end

            // 每通道饱和到 0..255；纯黑仍只留给边缘覆盖。
            rr = (r_adj < 11'sd0) ? 8'd0 : (r_adj > 11'sd255) ? 8'hFF : r_adj[7:0];
            gg = (g_adj < 11'sd0) ? 8'd0 : (g_adj > 11'sd255) ? 8'hFF : g_adj[7:0];
            bb = (b_adj < 11'sd0) ? 8'd0 : (b_adj > 11'sd255) ? 8'hFF : b_adj[7:0];
            F_cartoon_color = {rr, gg, bb};
        end
    endfunction

    // 组均值 (Sobel/二值化工作域: 空间 1/4 分辨率, 行缓存省 4 倍)
    wire [9:0] grp_sum = {2'b00, gray0} + {2'b00, gray1} + {2'b00, gray2} + {2'b00, gray3};
    wire [7:0] grp_gray_in = grp_sum[9:2];

    localparam IMG_WIDTH_GRP = (IMG_WIDTH >> 2);   // 1280×720 时为 320 组
    localparam integer RIGHT_STRIP_GROUPS = (IMG_WIDTH_GRP < 4) ? IMG_WIDTH_GRP : 4;
    localparam integer RIGHT_STRIP_X0 = IMG_WIDTH_GRP - RIGHT_STRIP_GROUPS;
    localparam integer RIGHT_TAIL_GROUPS = (IMG_WIDTH_GRP < 6) ? IMG_WIDTH_GRP : 6;
    localparam integer RIGHT_TAIL_X0 = IMG_WIDTH_GRP - RIGHT_TAIL_GROUPS;

    // ---- 窗口/行缓存骨架 ----
    // 两条灰度行缓存打包为 256×16：低字节=上一行，高字节=上两行。
    // TD 识别 fehdl force_ram/bram_fast 为逻辑 ERAM。此存储器不逐项复位，
    // 否则会退化成 4096 个触发器；同步读写和窗口流水还需一行建立期，
    // 因此窗口只从第 4 行、第 3 组起有效，未初始化内容不会进入有效输出。
    /* fehdl force_ram=1, ram_style="bram" */ reg [15:0] line_mem [0:IMG_WIDTH_GRP-1];

    reg [10:0] x_grp;
    reg [10:0] y_pos;
    wire [10:0] stream_x_in = I_tuser ? 11'd0 : x_grp;
    wire [10:0] stream_y_in = I_tuser ? 11'd0 : y_pos;

    reg [7:0] r0c0, r0c1, r0c2;
    reg [7:0] r1c0, r1c1, r1c2;
    reg [7:0] r2c0, r2c1, r2c2;

    reg [7:0] grp_gray;
    reg [7:0] prev_grp_gray_d1;
    reg [7:0] prev_grp_gray_d2;
    reg [7:0] smooth_gray;
    reg [7:0] top_v;
    reg [7:0] mid_v;

    reg signed [12:0] gx;
    reg signed [12:0] gy;
    reg [13:0] mag;
    reg [7:0]  sobel_v;
    reg [7:0]  emboss_v;
    reg        bin_flag;
    reg        win_d1, win_d2;
    reg [7:0]  sobel_hist1, sobel_hist2;
    // 行尾主窗口会在 tlast 清空，不能把那几拍的 sobel_v 当成右边缘。
    // 只缓存每行最后 6 组、前两行的灰度，在第 3 组起用同一 Sobel
    // 3x3 核计算最后 4 组。这样尾部不再退化为一阶差分或空白竖条。
    reg [7:0] border_prev_row [0:5];
    reg [7:0] border_prev2_row [0:5];
    reg [7:0] border_top_c0, border_top_c1;
    reg [7:0] border_mid_c0, border_mid_c1;
    reg [7:0] border_bot_c0, border_bot_c1;
    reg [1:0] border_rows_seen;
    reg signed [12:0] border_gx_d1, border_gy_d1;
    reg [13:0] border_mag_d2;
    reg [7:0] border_v_d3, border_v_d4;
    reg [7:0] border_v_d5, border_v_d6, border_v_d7, border_v_d8;
    integer border_i;
    wire border_group_in = (stream_x_in >= RIGHT_TAIL_X0);
    wire [2:0] border_idx = stream_x_in - RIGHT_TAIL_X0;
    wire signed [12:0] bt0 = $signed({5'd0,border_top_c0});
    wire signed [12:0] bt1 = $signed({5'd0,border_top_c1});
    wire signed [12:0] bt2 = $signed({5'd0,border_prev2_row[border_idx]});
    wire signed [12:0] bm0 = $signed({5'd0,border_mid_c0});
    wire signed [12:0] bm2 = $signed({5'd0,border_prev_row[border_idx]});
    wire signed [12:0] bb0 = $signed({5'd0,border_bot_c0});
    wire signed [12:0] bb1 = $signed({5'd0,border_bot_c1});
    wire signed [12:0] bb2 = $signed({5'd0,grp_gray_in});
    wire signed [12:0] border_gx = -bt0 + bt2 - (bm0 <<< 1) + (bm2 <<< 1) - bb0 + bb2;
    wire signed [12:0] border_gy = bt0 + (bt1 <<< 1) + bt2 - bb0 - (bb1 <<< 1) - bb2;
    wire [12:0] border_abs_gx = border_gx_d1[12] ? (~border_gx_d1 + 13'd1) : border_gx_d1;
    wire [12:0] border_abs_gy = border_gy_d1[12] ? (~border_gy_d1 + 13'd1) : border_gy_d1;
    reg [2:0]  frame_blank;   // 帧首 3 拍消隐 (门控链残留覆盖)

    wire win_valid = (x_grp >= 11'd2) && (y_pos >= 11'd3);

    // Shift width equals its left operand width. Extend samples before x2,
    // otherwise bright pixels overflow a 9-bit signed shift into negatives.
    wire signed [12:0] p_r0c0 = $signed({5'b0, r0c0});
    wire signed [12:0] p_r0c1 = $signed({5'b0, r0c1});
    wire signed [12:0] p_r0c2 = $signed({5'b0, r0c2});
    wire signed [12:0] p_r1c0 = $signed({5'b0, r1c0});
    wire signed [12:0] p_r1c2 = $signed({5'b0, r1c2});
    wire signed [12:0] p_r2c0 = $signed({5'b0, r2c0});
    wire signed [12:0] p_r2c1 = $signed({5'b0, r2c1});
    wire signed [12:0] p_r2c2 = $signed({5'b0, r2c2});

    wire signed [12:0] gx_w = -p_r0c0 + p_r0c2
                            - (p_r1c0 <<< 1) + (p_r1c2 <<< 1)
                            - p_r2c0 + p_r2c2;

    wire signed [12:0] gy_w =  p_r0c0 + (p_r0c1 <<< 1) + p_r0c2
                            - p_r2c0 - (p_r2c1 <<< 1) - p_r2c2;

    wire [12:0] abs_gx_w = gx_w[12] ? (~gx_w + 1'b1) : gx_w;
    wire [12:0] abs_gy_w = gy_w[12] ? (~gy_w + 1'b1) : gy_w;
    wire [13:0] mag_w = abs_gx_w + abs_gy_w;

    // mode 6 只做颜色风格化：直接使用与 data_d2 同拍的原始像素，
    // 不新增彩色邻域流水；这样 Sobel 描边路径和原有 8 拍对齐保持不变。
    wire [23:0] cart_pix0_q = F_cartoon_color(data_d2[95:72], gray0_d2);
    wire [23:0] cart_pix1_q = F_cartoon_color(data_d2[71:48], gray1_d2);
    wire [23:0] cart_pix2_q = F_cartoon_color(data_d2[47:24], gray2_d2);
    wire [23:0] cart_pix3_q = F_cartoon_color(data_d2[23:0],  gray3_d2);
    wire [95:0] gray_data_d2 = {gray0_d2,gray0_d2,gray0_d2, gray1_d2,gray1_d2,gray1_d2,
                                 gray2_d2,gray2_d2,gray2_d2, gray3_d2,gray3_d2,gray3_d2};
    wire [95:0] quant_data_d2 = {cart_pix0_q, cart_pix1_q, cart_pix2_q, cart_pix3_q};
    wire [95:0] shallow_data_d2 = (stream_mode_d2 == 3'd1) ? gray_data_d2 :
                                  (stream_mode_d2 == 3'd6) ? quant_data_d2 : data_d2;
    // 无有效 3x3 窗时保留量化颜色，避免帧首与边界出现非内容黑框。
    // 每行开头的移位寄存器仍在建立，额外屏蔽源流第 3 个组，防止平坦图像
    // 在行首产生一条伪轮廓。坐标与 data_d2 同拍延迟。
    // Binary outline mask: pure black is reserved for thresholded Sobel
    // edges. Non-edge pixels use quantization centers whose minimum is 0x20,
    // so dark image content remains distinguishable from the outline.
    wire right_strip_d8 = (stream_x_d8 >= RIGHT_STRIP_X0);
    wire legacy_last_group_ok = (stream_x_d8 < IMG_WIDTH_GRP-1) && !last_d8;
    wire [7:0] edge_v = right_strip_d8 ? border_v_d8 : sobel_v;
    wire edge_win = right_strip_d8 ? (stream_y_d8 >= 11'd3) : win_d2;
    // 连续性门控：强边缘直接保留；低阈值边缘需在最近两个组中至少
    // 再出现一次，消除暗光增益造成的单组随机黑点，同时不改变 Sobel
    // 强度输出（mode 2）和二值/浮雕算法。暗部色彩问题由调色板处理，
    // 不在这里用亮度门控，否则会把真正的暗色细节错误地当成黑边。
    wire cartoon_edge_keep = right_strip_d8 ?
                             (edge_v >= CART_EDGE_THRESHOLD) :
                             ((edge_v >= CART_EDGE_STRONG_THRESHOLD) ||
                              ((edge_v >= CART_EDGE_THRESHOLD) &&
                               ((sobel_hist1 >= CART_EDGE_THRESHOLD) ||
                                (sobel_hist2 >= CART_EDGE_THRESHOLD))));
    wire cartoon_edge = edge_win && (frame_blank == 3'd0) &&
                        (stream_y_d8 >= 11'd3) &&
                        cartoon_edge_keep;
    wire [95:0] cartoon_data = cartoon_edge ? 96'd0 : shallow_d8;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tlast  <= 1'b0;
            O_tuser  <= 1'b0;
            O_tdata  <= 96'd0;
            O_tvalid <= 1'b0;
            x_grp <= 11'd0;
            y_pos <= 11'd0;
            prev_grp_gray_d1 <= 8'd0;
            prev_grp_gray_d2 <= 8'd0;
            smooth_gray <= 8'd0;
            grp_gray <= 8'd0;
            top_v <= 8'd0;
            mid_v <= 8'd0;
            r0c0 <= 8'd0; r0c1 <= 8'd0; r0c2 <= 8'd0;
            r1c0 <= 8'd0; r1c1 <= 8'd0; r1c2 <= 8'd0;
            r2c0 <= 8'd0; r2c1 <= 8'd0; r2c2 <= 8'd0;
            gx <= 13'sd0;
            gy <= 13'sd0;
            mag <= 14'd0;
            bin_flag <= 1'b0;
            win_d1 <= 1'b0;
            win_d2 <= 1'b0;
            sobel_hist1 <= 8'd0;
            sobel_hist2 <= 8'd0;
            border_top_c0 <= 8'd0; border_top_c1 <= 8'd0;
            border_mid_c0 <= 8'd0; border_mid_c1 <= 8'd0;
            border_bot_c0 <= 8'd0; border_bot_c1 <= 8'd0;
            border_rows_seen <= 2'd0;
            border_gx_d1 <= 13'sd0; border_gy_d1 <= 13'sd0;
            border_mag_d2 <= 14'd0;
            border_v_d3 <= 8'd0; border_v_d4 <= 8'd0;
            border_v_d5 <= 8'd0; border_v_d6 <= 8'd0;
            border_v_d7 <= 8'd0; border_v_d8 <= 8'd0;
            for (border_i = 0; border_i < 6; border_i = border_i + 1) begin
                border_prev_row[border_i] <= 8'd0;
                border_prev2_row[border_i] <= 8'd0;
            end
            frame_blank <= 3'd0;
            data_d1 <= 96'd0; data_d2 <= 96'd0;
            gray0_d1 <= 8'd0; gray0_d2 <= 8'd0;
            gray1_d1 <= 8'd0; gray1_d2 <= 8'd0;
            gray2_d1 <= 8'd0; gray2_d2 <= 8'd0;
            gray3_d1 <= 8'd0; gray3_d2 <= 8'd0;
            valid_d1 <= 1'b0; valid_d2 <= 1'b0;
            user_d1 <= 1'b0; user_d2 <= 1'b0;
            last_d1 <= 1'b0; last_d2 <= 1'b0;
            stream_mode_d1 <= 3'd0; stream_mode_d2 <= 3'd0;
            stream_x_d1 <= 11'd0; stream_x_d2 <= 11'd0;
            stream_y_d1 <= 11'd0; stream_y_d2 <= 11'd0;
            shallow_d3 <= 96'd0; shallow_d4 <= 96'd0; shallow_d5 <= 96'd0;
            shallow_d6 <= 96'd0; shallow_d7 <= 96'd0; shallow_d8 <= 96'd0;
            valid_d3 <= 1'b0; valid_d4 <= 1'b0; valid_d5 <= 1'b0; valid_d6 <= 1'b0; valid_d7 <= 1'b0; valid_d8 <= 1'b0;
            user_d3 <= 1'b0; user_d4 <= 1'b0; user_d5 <= 1'b0; user_d6 <= 1'b0; user_d7 <= 1'b0; user_d8 <= 1'b0;
            last_d3 <= 1'b0; last_d4 <= 1'b0; last_d5 <= 1'b0; last_d6 <= 1'b0; last_d7 <= 1'b0; last_d8 <= 1'b0;
            stream_mode_d3 <= 3'd0; stream_mode_d4 <= 3'd0; stream_mode_d5 <= 3'd0; stream_mode_d6 <= 3'd0; stream_mode_d7 <= 3'd0; stream_mode_d8 <= 3'd0;
            stream_x_d3 <= 11'd0; stream_x_d4 <= 11'd0; stream_x_d5 <= 11'd0; stream_x_d6 <= 11'd0; stream_x_d7 <= 11'd0; stream_x_d8 <= 11'd0;
            stream_y_d3 <= 11'd0; stream_y_d4 <= 11'd0; stream_y_d5 <= 11'd0; stream_y_d6 <= 11'd0; stream_y_d7 <= 11'd0; stream_y_d8 <= 11'd0;
        end
        else begin
            border_mag_d2 <= {1'b0,border_abs_gx} + {1'b0,border_abs_gy};
            border_v_d3 <= border_mag_d2[10:3];
            border_v_d4 <= border_v_d3; border_v_d5 <= border_v_d4;
            border_v_d6 <= border_v_d5; border_v_d7 <= border_v_d6;
            border_v_d8 <= border_v_d7;
            border_gx_d1 <= (I_tvalid && border_group_in &&
                              (stream_x_in >= RIGHT_STRIP_X0) &&
                              (border_rows_seen == 2'd2)) ?
                             border_gx : 13'sd0;
            border_gy_d1 <= (I_tvalid && border_group_in &&
                              (stream_x_in >= RIGHT_STRIP_X0) &&
                              (border_rows_seen == 2'd2)) ?
                             border_gy : 13'sd0;
            if (I_tvalid) begin
                if (border_group_in) begin
                    border_prev2_row[border_idx] <= border_prev_row[border_idx];
                    border_prev_row[border_idx] <= grp_gray_in;
                    border_top_c0 <= border_top_c1;
                    border_top_c1 <= border_prev2_row[border_idx];
                    border_mid_c0 <= border_mid_c1;
                    border_mid_c1 <= border_prev_row[border_idx];
                    border_bot_c0 <= border_bot_c1;
                    border_bot_c1 <= grp_gray_in;
                end
                if (I_tuser)
                    border_rows_seen <= 2'd0;
                else if (I_tlast && border_rows_seen != 2'd2)
                    border_rows_seen <= border_rows_seen + 2'd1;
            end
            // 输出使用延迟后的源流。即使 I_tvalid 已撤销，也会将末尾两拍
            // 正确冲出，避免行尾/帧尾丢失。
            O_tlast  <= last_d8;
            O_tuser  <= user_d8;
            O_tvalid <= valid_d8;
            if (valid_d8) begin
                case (stream_mode_d8)
                    3'd1: O_tdata <= shallow_d8;
                    3'd2: O_tdata <= (edge_win && frame_blank==3'd0) ? {edge_v,edge_v,edge_v, edge_v,edge_v,edge_v,
                                        edge_v,edge_v,edge_v, edge_v,edge_v,edge_v} : 96'd0;
                    3'd3: O_tdata <= (win_d2 && bin_flag && frame_blank==3'd0 && legacy_last_group_ok) ? {24'hFFFFFF,24'hFFFFFF,24'hFFFFFF,24'hFFFFFF} : 96'd0;
                    3'd4: O_tdata <= (edge_win && frame_blank==3'd0) ? {(8'd255 - edge_v),(8'd255 - edge_v),(8'd255 - edge_v),
                                        (8'd255 - edge_v),(8'd255 - edge_v),(8'd255 - edge_v),
                                        (8'd255 - edge_v),(8'd255 - edge_v),(8'd255 - edge_v),
                                        (8'd255 - edge_v),(8'd255 - edge_v),(8'd255 - edge_v)} : 96'd0;
                    3'd5: O_tdata <= (win_d2 && frame_blank==3'd0 && legacy_last_group_ok) ? {emboss_v,emboss_v,emboss_v, emboss_v,emboss_v,emboss_v,
                                        emboss_v,emboss_v,emboss_v, emboss_v,emboss_v,emboss_v} : 96'd0;
                    3'd6: O_tdata <= cartoon_data;
                    default: O_tdata <= shallow_d8;
                endcase
            end else begin
                O_tdata <= 96'd0;
            end

            data_d1 <= I_tdata;          data_d2 <= data_d1;
            gray0_d1 <= gray0;           gray0_d2 <= gray0_d1;
            gray1_d1 <= gray1;           gray1_d2 <= gray1_d1;
            gray2_d1 <= gray2;           gray2_d2 <= gray2_d1;
            gray3_d1 <= gray3;           gray3_d2 <= gray3_d1;
            valid_d1 <= I_tvalid;        valid_d2 <= valid_d1;
            user_d1 <= I_tuser;          user_d2 <= user_d1;
            last_d1 <= I_tlast;          last_d2 <= last_d1;
            stream_mode_d1 <= stream_mode_in;
            stream_mode_d2 <= stream_mode_d1;
            stream_x_d1 <= stream_x_in;  stream_x_d2 <= stream_x_d1;
            stream_y_d1 <= stream_y_in;  stream_y_d2 <= stream_y_d1;
            shallow_d3 <= shallow_data_d2; shallow_d4 <= shallow_d3; shallow_d5 <= shallow_d4;
            shallow_d6 <= shallow_d5; shallow_d7 <= shallow_d6; shallow_d8 <= shallow_d7;
            valid_d3 <= valid_d2; valid_d4 <= valid_d3; valid_d5 <= valid_d4; valid_d6 <= valid_d5; valid_d7 <= valid_d6; valid_d8 <= valid_d7;
            user_d3 <= user_d2; user_d4 <= user_d3; user_d5 <= user_d4; user_d6 <= user_d5; user_d7 <= user_d6; user_d8 <= user_d7;
            last_d3 <= last_d2; last_d4 <= last_d3; last_d5 <= last_d4; last_d6 <= last_d5; last_d7 <= last_d6; last_d8 <= last_d7;
            stream_mode_d3 <= stream_mode_d2; stream_mode_d4 <= stream_mode_d3; stream_mode_d5 <= stream_mode_d4;
            stream_mode_d6 <= stream_mode_d5; stream_mode_d7 <= stream_mode_d6; stream_mode_d8 <= stream_mode_d7;
            stream_x_d3 <= stream_x_d2; stream_x_d4 <= stream_x_d3; stream_x_d5 <= stream_x_d4;
            stream_x_d6 <= stream_x_d5; stream_x_d7 <= stream_x_d6; stream_x_d8 <= stream_x_d7;
            stream_y_d3 <= stream_y_d2; stream_y_d4 <= stream_y_d3; stream_y_d5 <= stream_y_d4;
            stream_y_d6 <= stream_y_d5; stream_y_d7 <= stream_y_d6; stream_y_d8 <= stream_y_d7;
            if (I_tvalid) begin
                if (I_tuser) begin
                    // tuser belongs to the first data group, so the next beat
                    // must use address 1 (not address 0 a second time).
                    x_grp <= 11'd1;
                    y_pos <= 11'd0;
                    prev_grp_gray_d1 <= 8'd0;
                    prev_grp_gray_d2 <= 8'd0;
                    r0c0 <= 8'd0; r0c1 <= 8'd0; r0c2 <= 8'd0;
                    r1c0 <= 8'd0; r1c1 <= 8'd0; r1c2 <= 8'd0;
                    r2c0 <= 8'd0; r2c1 <= 8'd0; r2c2 <= 8'd0;
                    win_d1 <= 1'b0;
                    win_d2 <= 1'b0;
                    mag <= 14'd0;
                    sobel_v <= 8'd0;
                    emboss_v <= 8'd0;
                end

                grp_gray <= grp_gray_in;
                if (x_grp == 11'd0)
                    smooth_gray <= grp_gray;
                else if (x_grp == 11'd1)
                    smooth_gray <= (grp_gray + prev_grp_gray_d1) >> 1;
                else
                    smooth_gray <= ({2'b00, grp_gray} + ({2'b00, prev_grp_gray_d1} << 1) + {2'b00, prev_grp_gray_d2}) >> 2;
                prev_grp_gray_d2 <= prev_grp_gray_d1;
                prev_grp_gray_d1 <= grp_gray;

                top_v <= line_mem[x_grp][15:8];
                mid_v <= line_mem[x_grp][7:0];

                r0c0 <= r0c1; r0c1 <= r0c2; r0c2 <= top_v;
                r1c0 <= r1c1; r1c1 <= r1c2; r1c2 <= mid_v;
                r2c0 <= r2c1; r2c1 <= r2c2; r2c2 <= smooth_gray;
                win_d2 <= win_d1;

                gx <= gx_w;
                gy <= gy_w;
                mag <= mag_w;
                win_d1 <= win_valid;
                // 窗口中心值 (r2c2 = smooth 落窗值) 判二值 — 与窗位置对齐
                bin_flag <= (r2c2 > BIN_THRESHOLD);
                // 8-bit 3x3 Sobel 的 |gx|+|gy| 最大值为 2040。
                // 除以 8 后单调映射到 0..255，不截断回绕。
                sobel_v <= mag[10:3];
                if (I_tuser) begin
                    sobel_hist1 <= 8'd0;
                    sobel_hist2 <= 8'd0;
                end
                else begin
                    sobel_hist2 <= sobel_hist1;
                    sobel_hist1 <= sobel_v;
                end
                // 浮雕: 主对角差分 + 128 偏移 (凸起感), 饱和 [0,255]
                // emboss = clamp(r2c2 - r0c0 + 128, 0, 255), 10bit 有符号中间量
                emboss_v <= (($signed({2'b00, r2c2}) - $signed({2'b00, r0c0}) + 10'sd128) > 10'sd255) ? 8'hFF :
                            (($signed({2'b00, r2c2}) - $signed({2'b00, r0c0}) + 10'sd128) < 10'sd0) ? 8'd0 :
                            ($signed({2'b00, r2c2}) - $signed({2'b00, r0c0}) + 10'sd128);

                if (I_tuser)
                    frame_blank <= 3'd5;
                else if (frame_blank != 3'd0)
                    frame_blank <= frame_blank - 1'b1;
                line_mem[x_grp] <= {mid_v, smooth_gray};

                // 以 tlast 为主、固定宽度为后备：即使上游当前模式的有效
                // 组数与参数暂时不一致，也不会把本行末拍继续当作下一行数据。
                if (!I_tuser && (I_tlast || (x_grp == IMG_WIDTH_GRP - 1))) begin
                    x_grp <= 11'd0;
                    if (y_pos == IMG_HEIGHT - 1)
                        y_pos <= 11'd0;
                    else
                        y_pos <= y_pos + 1'b1;
                    r0c0 <= 8'd0; r0c1 <= 8'd0; r0c2 <= 8'd0;
                    r1c0 <= 8'd0; r1c1 <= 8'd0; r1c2 <= 8'd0;
                    r2c0 <= 8'd0; r2c1 <= 8'd0; r2c2 <= 8'd0;
                    // 行尾之后窗口无效，禁止最后一组的状态跨行传播；
                    // 当前行末输出由 last_d8/edge_group_ok 屏蔽，下一行从全零窗口重新建立。
                    win_d1 <= 1'b0;
                    win_d2 <= 1'b0;
                    mag <= 14'd0;
                    sobel_v <= 8'd0;
                    emboss_v <= 8'd0;
                    bin_flag <= 1'b0;
                    sobel_hist1 <= 8'd0;
                    sobel_hist2 <= 8'd0;
                end
                else if (!I_tuser) begin
                    x_grp <= x_grp + 1'b1;
                end
            end
        end
    end

endmodule
