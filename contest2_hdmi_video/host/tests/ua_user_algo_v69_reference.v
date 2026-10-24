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
module ua_user_algo_v69_reference #(
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

    // 源流、窗口结果和边带统一延迟 8 个时钟。行窗口只在有效样本到达
    // 时更新，运算与输出流水每个时钟推进，因此 valid 气泡不改变延迟。
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

    localparam integer IMG_WIDTH_GRP = IMG_WIDTH >> 2;

    // A single packed RAM stores the previous two rows. Read address/tag and
    // current-row sample enter stage 1 together; write that SAME address in
    // stage 2 using the read lower byte, not the preceding column's register.
    /* fehdl force_ram=1, ram_style="bram" */ reg [15:0] line_mem [0:IMG_WIDTH_GRP-1];
    // Register the read address without a reset. This TD-supported template
    // prevents the data register being absorbed into resettable window muxes.
    reg [10:0] row_address_d1;
    wire [15:0] row_read_d1=line_mem[row_address_d1];
    reg [10:0] x_grp,y_pos;
    wire [10:0] stream_x_in = I_tuser ? 11'd0 : x_grp;
    wire [10:0] stream_y_in = I_tuser ? 11'd0 : y_pos;
    reg [7:0] raw_prev1,raw_prev2,smooth_d1;
    wire [9:0] smooth_sum = {2'd0,grp_gray_in} +
        ((stream_x_in==0) ? ({2'd0,grp_gray_in}<<1) : ({2'd0,raw_prev1}<<1)) +
        ((stream_x_in==0) ? {2'd0,grp_gray_in} :
         (stream_x_in==1) ? {2'd0,raw_prev1} : {2'd0,raw_prev2});
    wire [7:0] top_now = (stream_y_d1==0) ? smooth_d1 :
                        (stream_y_d1==1) ? row_read_d1[7:0] : row_read_d1[15:8];
    wire [7:0] mid_now = (stream_y_d1==0) ? smooth_d1 : row_read_d1[7:0];
    reg [7:0] top_prev2,top_prev1,mid_prev2,mid_prev1,bot_prev2,bot_prev1;
    // Causal 3x3 window ends at the current sample. Replicate missing top/left
    // samples; no row-end clearing or special right-strip algorithm is needed.
    wire [7:0] t0=(stream_x_d1==0)?top_now:(stream_x_d1==1)?top_prev1:top_prev2;
    wire [7:0] t1=(stream_x_d1==0)?top_now:top_prev1;
    wire [7:0] m0=(stream_x_d1==0)?mid_now:(stream_x_d1==1)?mid_prev1:mid_prev2;
    wire [7:0] b0=(stream_x_d1==0)?smooth_d1:(stream_x_d1==1)?bot_prev1:bot_prev2;
    wire [7:0] b1=(stream_x_d1==0)?smooth_d1:bot_prev1;
    wire signed [12:0] top0=$signed({5'd0,t0}),top1=$signed({5'd0,t1}),top2=$signed({5'd0,top_now});
    wire signed [12:0] mid0=$signed({5'd0,m0}),mid2=$signed({5'd0,mid_now});
    wire signed [12:0] bot0=$signed({5'd0,b0}),bot1=$signed({5'd0,b1}),bot2=$signed({5'd0,smooth_d1});
    wire signed [12:0] gx_now=-top0+top2-(mid0<<<1)+(mid2<<<1)-bot0+bot2;
    wire signed [12:0] gy_now=top0+(top1<<<1)+top2-bot0-(bot1<<<1)-bot2;
    wire signed [9:0] emboss_now=$signed({2'd0,smooth_d1})-$signed({2'd0,t0})+10'sd128;
    reg signed [12:0] gx_d2,gy_d2;
    wire [12:0] abs_gx=gx_d2[12]?(~gx_d2+13'd1):gx_d2;
    wire [12:0] abs_gy=gy_d2[12]?(~gy_d2+13'd1):gy_d2;
    reg [13:0] magnitude_d3;
    reg [7:0] sobel_d4,sobel_d5,sobel_d6,sobel_d7,sobel_d8;
    reg [7:0] emboss_d2,emboss_d3,emboss_d4,emboss_d5,emboss_d6,emboss_d7,emboss_d8;
    reg bin_d2,bin_d3,bin_d4,bin_d5,bin_d6,bin_d7,bin_d8;
    reg [7:0] sobel_hist1,sobel_hist2;
    wire [23:0] cart_pix0_q=F_cartoon_color(data_d2[95:72],gray0_d2);
    wire [23:0] cart_pix1_q=F_cartoon_color(data_d2[71:48],gray1_d2);
    wire [23:0] cart_pix2_q=F_cartoon_color(data_d2[47:24],gray2_d2);
    wire [23:0] cart_pix3_q=F_cartoon_color(data_d2[23:0],gray3_d2);
    wire [95:0] gray_data_d2={ {3{gray0_d2}}, {3{gray1_d2}}, {3{gray2_d2}}, {3{gray3_d2}} };
    wire [95:0] shallow_data_d2=(stream_mode_d2==1)?gray_data_d2:
        (stream_mode_d2==6)?{cart_pix0_q,cart_pix1_q,cart_pix2_q,cart_pix3_q}:data_d2;
    wire cartoon_edge=(sobel_d8>=CART_EDGE_STRONG_THRESHOLD) ||
        ((sobel_d8>=CART_EDGE_THRESHOLD) && stream_x_d8!=0 &&
         ((sobel_hist1>=CART_EDGE_THRESHOLD) ||
          (stream_x_d8>1 && sobel_hist2>=CART_EDGE_THRESHOLD)));

    // Synchronous read port has no reset, preserving ERAM inference. The RAM
    // contents need no initialization: row tags select only initialized data.
    always @(posedge I_clk) begin
        if(I_tvalid) row_address_d1<=stream_x_in;
        if(valid_d1) line_mem[stream_x_d1]<={row_read_d1[7:0],smooth_d1};
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            x_grp<=0;y_pos<=0;raw_prev1<=0;raw_prev2<=0;smooth_d1<=0;
            top_prev2<=0;top_prev1<=0;mid_prev2<=0;mid_prev1<=0;bot_prev2<=0;bot_prev1<=0;
            gx_d2<=0;gy_d2<=0;magnitude_d3<=0;
            sobel_d4<=0;sobel_d5<=0;sobel_d6<=0;sobel_d7<=0;sobel_d8<=0;
            emboss_d2<=0;emboss_d3<=0;emboss_d4<=0;emboss_d5<=0;emboss_d6<=0;emboss_d7<=0;emboss_d8<=0;
            bin_d2<=0;bin_d3<=0;bin_d4<=0;bin_d5<=0;bin_d6<=0;bin_d7<=0;bin_d8<=0;
            sobel_hist1<=0;sobel_hist2<=0;
            O_tlast<=0;O_tuser<=0;O_tvalid<=0;O_tdata<=0;
            data_d1<=0;data_d2<=0;
            gray0_d1<=0;gray0_d2<=0;gray1_d1<=0;gray1_d2<=0;gray2_d1<=0;gray2_d2<=0;gray3_d1<=0;gray3_d2<=0;
            valid_d1<=0;valid_d2<=0;valid_d3<=0;valid_d4<=0;valid_d5<=0;valid_d6<=0;valid_d7<=0;valid_d8<=0;
            user_d1<=0;user_d2<=0;user_d3<=0;user_d4<=0;user_d5<=0;user_d6<=0;user_d7<=0;user_d8<=0;
            last_d1<=0;last_d2<=0;last_d3<=0;last_d4<=0;last_d5<=0;last_d6<=0;last_d7<=0;last_d8<=0;
            stream_mode_d1<=0;stream_mode_d2<=0;stream_mode_d3<=0;stream_mode_d4<=0;stream_mode_d5<=0;stream_mode_d6<=0;stream_mode_d7<=0;stream_mode_d8<=0;
            stream_x_d1<=0;stream_x_d2<=0;stream_x_d3<=0;stream_x_d4<=0;stream_x_d5<=0;stream_x_d6<=0;stream_x_d7<=0;stream_x_d8<=0;
            stream_y_d1<=0;stream_y_d2<=0;stream_y_d3<=0;stream_y_d4<=0;stream_y_d5<=0;stream_y_d6<=0;stream_y_d7<=0;stream_y_d8<=0;
            shallow_d3<=0;shallow_d4<=0;shallow_d5<=0;shallow_d6<=0;shallow_d7<=0;shallow_d8<=0;
        end else begin
            if(I_tvalid)begin
                smooth_d1<=smooth_sum[9:2];
                raw_prev1<=grp_gray_in;
                raw_prev2<=(stream_x_in==0)?grp_gray_in:raw_prev1;
                if(I_tlast || stream_x_in==IMG_WIDTH_GRP-1)begin
                    x_grp<=0;
                    y_pos<=(stream_y_in==IMG_HEIGHT-1)?11'd0:stream_y_in+11'd1;
                end else begin x_grp<=stream_x_in+11'd1;y_pos<=stream_y_in;end
            end
            if(valid_d1)begin
                top_prev1<=top_now;top_prev2<=(stream_x_d1==0)?top_now:top_prev1;
                mid_prev1<=mid_now;mid_prev2<=(stream_x_d1==0)?mid_now:mid_prev1;
                bot_prev1<=smooth_d1;bot_prev2<=(stream_x_d1==0)?smooth_d1:bot_prev1;
            end
            // Arithmetic and sidebands advance every clock, including bubbles.
            gx_d2<=gx_now;gy_d2<=gy_now;
            magnitude_d3<={1'b0,abs_gx}+{1'b0,abs_gy};
            sobel_d4<=magnitude_d3[10:3];
            sobel_d5<=sobel_d4;sobel_d6<=sobel_d5;sobel_d7<=sobel_d6;sobel_d8<=sobel_d7;
            emboss_d2<=(emboss_now<10'sd0)?8'd0:(emboss_now>10'sd255)?8'd255:emboss_now[7:0];
            emboss_d3<=emboss_d2;emboss_d4<=emboss_d3;emboss_d5<=emboss_d4;emboss_d6<=emboss_d5;emboss_d7<=emboss_d6;emboss_d8<=emboss_d7;
            bin_d2<=smooth_d1>BIN_THRESHOLD;
            bin_d3<=bin_d2;bin_d4<=bin_d3;bin_d5<=bin_d4;bin_d6<=bin_d5;bin_d7<=bin_d6;bin_d8<=bin_d7;
            if(valid_d8)begin
                sobel_hist1<=sobel_d8;
                sobel_hist2<=(stream_x_d8==0)?8'd0:sobel_hist1;
            end
            O_tlast<=last_d8;O_tuser<=user_d8;O_tvalid<=valid_d8;
            if(valid_d8)begin
                case(stream_mode_d8)
                    3'd1:O_tdata<=shallow_d8;
                    3'd2:O_tdata<={12{sobel_d8}};
                    3'd3:O_tdata<=bin_d8?{96{1'b1}}:96'd0;
                    3'd4:O_tdata<={12{8'd255-sobel_d8}};
                    3'd5:O_tdata<={12{emboss_d8}};
                    3'd6:O_tdata<=cartoon_edge?96'd0:shallow_d8;
                    default:O_tdata<=shallow_d8;
                endcase
            end else O_tdata<=0;
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
        end
    end
endmodule
