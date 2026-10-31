// ua_track_detect.v — 扩展②: 多目标检测与识别 (三色并行 + 尺寸过滤 + 形状分类)
//
// 观察模式: 与 ua_user_algo_96 并行挂接在 AWB/暗光增强彩色流, 不参与背压
// 算法 (全部组均值域, 4 像素/拍 → 组平均 R/G/B):
//   检测: HSV-like 色相扇区 + 饱和度/亮度门限 (移位比较, 无除法)
//   分离: 每色两个限量连通候选槽；按相邻行/包围盒连续性归属，帧末选最大槽
//   过滤: 包围盒尺寸 + 命中面积 + 填充率，抑制低饱和背景与稀疏噪点
//   识别: 水平/垂直、约22.5°、45°三组投影框 (全移位加法，无除法):
//           先选择最小归一化投影框，再用长宽比/填充率分类，
//           避免斜放长条被水平框误判为方形；形状 3 保留给三角形。
//           实验性的边界密度特征已从默认路径移除，避免额外位图/宽乘法造成切片超限。
//   稳定: 坐标 3/4 IIR 低通 + 形状连续两帧确认，允许短暂丢失后再撤销目标
// 输出: 每通道 {O_v, O_x, O_y, O_shape} 及最大候选的像素包围盒，
//       帧末更新并稳定到下一帧。包围盒是该颜色全帧最大候选的 min/max。
//       shape: 0=圆 1=方 2=条 3=三角形；无目标由 O_v=0 表示
// 判色/候选分离/稳定部分无除法、无新增 ERAM；投影极值随候选槽流式累计，
// 形状分类沿用帧末流水乘法。组域中心 → 像素坐标。
// 阅读入口：先理解 HSV-like 三色掩码，再看每色两个候选槽；最后看 EOF 后
// 九级分类流水复用每色一个面积乘法器及三色共用的形状比较器。
// 它是资源受控的近似连通域，不是全帧像素标号。
`timescale 1ns/1ps
module ua_track_detect #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    parameter IMG_W_GRP  = (IMG_WIDTH >> 2), // x 组数
    parameter IMG_H_GRP  = IMG_HEIGHT,   // y 行数 (组域 y = 像素 y)
    parameter MIN_W_G    = 10'd3,        // 最小宽 (组) 过滤
    parameter MIN_H_G    = 10'd3,        // 最小高 (组) 过滤
    parameter MIN_AREA_G = 18'd12,       // 最少命中组数
    parameter VALUE_MIN  = 8'd48,        // HSV V 近似: max(R,G,B)
    parameter CHROMA_MIN = 8'd32,        // HSV chroma 近似: max-min
    parameter DOMINANCE_MIN = 8'd8,      // 主色至少领先次色的差值
    parameter [1:0] LOSS_HOLD_FRAMES = 2'd1, // 短暂漏检保持帧数 (0..3)
    parameter integer FAST_TRACK_ENABLE = 0,
    parameter integer FAST_TRACK_PIXELS = 8
)(
    input               I_clk,
    input               I_rst_n,
    input               I_tlast,
    input               I_tuser,
    input      [95:0]   I_tdata,
    input               I_tvalid,
    input               I_tready,
    output reg          O_tlast,
    output reg          O_tuser,
    output reg  [95:0]  O_tdata,
    output reg          O_tvalid,
    output              O_tready,
    output reg          O_track_valid,   // 帧末输出锁存脉冲
    output reg  [3:0]   O_obj_cnt,
    output reg          O_v0,
    output reg  [10:0]  O_x0, O_y0,
    output reg  [1:0]   O_shape0,
    output reg  [10:0]  O_xmin0, O_xmax0, O_ymin0, O_ymax0,
    output reg          O_v1,
    output reg  [10:0]  O_x1, O_y1,
    output reg  [1:0]   O_shape1,
    output reg  [10:0]  O_xmin1, O_xmax1, O_ymin1, O_ymax1,
    output reg          O_v2,
    output reg  [10:0]  O_x2, O_y2,
    output reg  [1:0]   O_shape2,
    output reg  [10:0]  O_xmin2, O_xmax2, O_ymin2, O_ymax2
);
    assign O_tready = I_tready;

    // ---- 像素拆包 → 组平均 R/G/B ----
    wire [23:0] p0 = I_tdata[95:72];
    wire [23:0] p1 = I_tdata[71:48];
    wire [23:0] p2 = I_tdata[47:24];
    wire [23:0] p3 = I_tdata[23:0];
    wire [9:0] r_sum = {2'b00,p0[23:16]} + {2'b00,p1[23:16]} + {2'b00,p2[23:16]} + {2'b00,p3[23:16]};
    wire [9:0] g_sum = {2'b00,p0[15:8]}  + {2'b00,p1[15:8]}  + {2'b00,p2[15:8]}  + {2'b00,p3[15:8]};
    wire [9:0] b_sum = {2'b00,p0[7:0]}   + {2'b00,p1[7:0]}   + {2'b00,p2[7:0]}   + {2'b00,p3[7:0]};
    wire [7:0] r_avg = r_sum[9:2];
    wire [7:0] g_avg = g_sum[9:2];
    wire [7:0] b_avg = b_sum[9:2];

    // HSV-like 无除法判色。max/min 对应 V/chroma；2*chroma>=max 对应 S>=0.5；
    // 主色通道两侧分量差不超过 chroma/2，限制在该主色附近的 hue 扇区，排除黄/青/紫。
    reg [7:0] r_avg_d, g_avg_d, b_avg_d;
    wire signed [8:0] diff_rg=$signed({1'b0,r_avg_d})-$signed({1'b0,g_avg_d});
    wire signed [8:0] diff_gb=$signed({1'b0,g_avg_d})-$signed({1'b0,b_avg_d});
    wire signed [8:0] diff_br=$signed({1'b0,b_avg_d})-$signed({1'b0,r_avg_d});
    wire r_ge_g=!diff_rg[8],g_ge_b=!diff_gb[8],b_ge_r=!diff_br[8];
    wire [7:0] max_rgb=r_ge_g ? (b_ge_r?b_avg_d:r_avg_d) : (g_ge_b?g_avg_d:b_avg_d);
    wire [7:0] min_rgb=r_ge_g ? (g_ge_b?b_avg_d:g_avg_d) : (b_ge_r?r_avg_d:b_avg_d);
    wire [8:0] chroma = {1'b0,max_rgb} - {1'b0,min_rgb};
    wire [8:0] rg_delta=diff_rg[8]?-diff_rg:diff_rg;
    wire [8:0] gb_delta=diff_gb[8]?-diff_gb:diff_gb;
    wire [8:0] br_delta=diff_br[8]?-diff_br:diff_br;
    wire [8:0] r9 = {1'b0,r_avg_d};
    wire [8:0] g9 = {1'b0,g_avg_d};
    wire [8:0] b9 = {1'b0,b_avg_d};
    localparam signed [8:0] POS_DOM=$signed({1'b0,DOMINANCE_MIN});
    localparam signed [8:0] NEG_DOM=-POS_DOM;
    wire red_dom=(diff_rg>=POS_DOM) && (diff_br<=NEG_DOM);
    wire green_dom=(diff_rg<=NEG_DOM) && (diff_gb>=POS_DOM);
    wire blue_dom=(diff_br>=POS_DOM) && (diff_gb<=NEG_DOM);
    // 暗光 Gamma 会同时抬高三个通道，固定 chroma 虽不变但 max 会增加；
    // 仍用 S>=0.5 的 2*chroma 判据会把肤色/低饱和实物全部过滤掉。
    // 放宽为 S>=1/3（3*chroma>=V），主色领先、最小 chroma 与区域填充率
    // 继续负责抑制近灰噪声。
    wire color_ok = (max_rgb >= VALUE_MIN) && (chroma >= CHROMA_MIN) &&
                    (({chroma,1'b0} + {1'b0,chroma}) >= {2'b00,max_rgb});
    // v99: red objects need S>=1/2. Keep the original hue sector so
    // dark red print is retained; warm low-saturation skin loses red eligibility.
    wire red_saturated = ({chroma,1'b0} > {2'b00,max_rgb});
    // Blue print is desaturated by the ISP; relax S only for blue, retaining
    // chroma and both dominant-channel tests (not a global noise relaxation).
    wire blue_ok = (max_rgb >= VALUE_MIN) && (chroma >= CHROMA_MIN) &&
                   ({chroma,2'b00} >= {3'b000,max_rgb});
    wire is_t0 = color_ok && red_saturated && red_dom && r_ge_g && !b_ge_r &&
                 (({gb_delta,1'b0}+{1'b0,gb_delta}) <= {1'b0,chroma});
    wire is_t1 = blue_ok && green_dom && !r_ge_g && g_ge_b &&
                 (({br_delta,1'b0}+{1'b0,br_delta}) <= {chroma,1'b0});
    wire is_t2 = blue_ok && blue_dom && (diff_br>9'sd0) && !g_ge_b &&
                 ({rg_delta,1'b0} <= {1'b0,chroma});

    // ---- 坐标 + 每通道双色候选区域 ----
    reg [9:0] x_grp, y_pos;
    // 组坐标范围是 x=0..319、y=0..719；10 位已覆盖整个 720p 组域。
    // 仅最终像素坐标输出使用 11 位，避免把内部比较/候选连通逻辑无谓扩宽。
    reg [9:0]  avg_x_d, avg_y_d;
    reg        avg_valid_d, avg_tuser_d;
    reg [9:0]  x_d, y_d;
    reg       valid_d, tuser_d;
    reg       is_t0_d, is_t1_d, is_t2_d;
    // 帧末流水隔开跨度、外接框面积和分类比较；旋转特征不进入视频主路径。
    reg [9:0]  c_w0, c_w1, c_w2, c_h0, c_h1, c_h2;   // w/h (含 +1)
    reg [19:0] c_ba0, c_ba1, c_ba2;                  // bbox_area = w*h
    reg [11:0] c_wp0, c_wp1, c_wp2;                  // w<<2
    reg [21:0] c_a80, c_a81, c_a82;
    wire [21:0] c_ba38_0 = {2'b00,c_ba0} + {1'b0,c_ba0,1'b0};
    wire [21:0] c_ba38_1 = {2'b00,c_ba1} + {1'b0,c_ba1,1'b0};
    wire [21:0] c_ba38_2 = {2'b00,c_ba2} + {1'b0,c_ba2,1'b0};
    // 三组旋转投影跨度。u/v 为 45°；p/q=(5x+2y,-2x+5y) 约为 22.5°。
    // 公共比例 58：axis*58、diag45*29、rot22*2，避免 /2 和 /29。
    // Exact bounds for the 10-bit coordinate / 18-bit area datapath.

    // ---- 帧末快照寄存器 (拍1: 帧末拍快照) ----
    reg [9:0]  s_x0, s_xm0, s_y0, s_ym0;
    reg [9:0]  s_x1, s_xm1, s_y1, s_ym1;
    reg [9:0]  s_x2, s_xm2, s_y2, s_ym2;
    reg [17:0] s_a0, s_a1, s_a2;
    reg        s_hit0, s_hit1, s_hit2;
    reg        s_v0, s_v1, s_v2;

    // 区域有效性：至少达到最小面积，且命中面积 / bbox 面积 >= 3/8。
    // 使用 a*8 >= bbox*3，复用已流水寄存的 a8，仅增加移位加法，过滤稀疏噪点。
    // v100: a rotated bar occupies little of its axis-aligned box. Only a
    // geometrically elongated candidate may use the rotated density gate.
    // Stored per colour in the existing EOF slots; no extra frame latency.
    reg bar_dense0, bar_dense1, bar_dense2;
    wire filt_v0 = s_v0 && (s_a0 >= MIN_AREA_G) &&
                   ((c_a80 >= c_ba38_0) || bar_dense0);
    wire filt_v1 = s_v1 && (s_a1 >= MIN_AREA_G) &&
                   ((c_a81 >= c_ba38_1) || bar_dense1);
    wire filt_v2 = s_v2 && (s_a2 >= MIN_AREA_G) &&
                   ((c_a82 >= c_ba38_2) || bar_dense2);

    wire [10:0] center_xg0 = ({1'b0,s_x0} + {1'b0,s_xm0} + 11'd1) >> 1;
    wire [10:0] center_xg1 = ({1'b0,s_x1} + {1'b0,s_xm1} + 11'd1) >> 1;
    wire [10:0] center_xg2 = ({1'b0,s_x2} + {1'b0,s_xm2} + 11'd1) >> 1;
    wire [10:0] raw_x0 = center_xg0 << 2;
    wire [10:0] raw_x1 = center_xg1 << 2;
    wire [10:0] raw_x2 = center_xg2 << 2;
    // 11 位求和避免 y=512..599 时 10 位加法溢出。
    wire [10:0] center_y0 = ({1'b0,s_y0} + {1'b0,s_ym0} + 11'd1) >> 1;
    wire [10:0] center_y1 = ({1'b0,s_y1} + {1'b0,s_ym1} + 11'd1) >> 1;
    wire [10:0] center_y2 = ({1'b0,s_y2} + {1'b0,s_ym2} + 11'd1) >> 1;

    // 候选坐标在组域统计。导出到 HDMI 前转换成像素域：x 组覆盖 4 个像素，
    // 因而 xmax 使用“下一组起点 - 1”，确保框完整覆盖最后一组。
    wire [10:0] raw_xmin0 = {s_x0, 2'b00};
    wire [10:0] raw_xmin1 = {s_x1, 2'b00};
    wire [10:0] raw_xmin2 = {s_x2, 2'b00};
    wire [11:0] raw_xmax0_w = (({2'b00,s_xm0} + 12'd1) << 2) - 12'd1;
    wire [11:0] raw_xmax1_w = (({2'b00,s_xm1} + 12'd1) << 2) - 12'd1;
    wire [11:0] raw_xmax2_w = (({2'b00,s_xm2} + 12'd1) << 2) - 12'd1;
    wire [10:0] raw_xmax0 = raw_xmax0_w[10:0];
    wire [10:0] raw_xmax1 = raw_xmax1_w[10:0];
    wire [10:0] raw_xmax2 = raw_xmax2_w[10:0];
    wire [10:0] raw_ymin0 = {1'b0,s_y0};
    wire [10:0] raw_ymin1 = {1'b0,s_y1};
    wire [10:0] raw_ymin2 = {1'b0,s_y2};
    wire [10:0] raw_ymax0 = {1'b0,s_ym0};
    wire [10:0] raw_ymax1 = {1'b0,s_ym1};
    wire [10:0] raw_ymax2 = {1'b0,s_ym2};

    reg [1:0] miss0, miss1, miss2;
    // 形状识别的跨帧滞回：候选形状必须连续出现两帧才切换，
    // 避免投影面积刚好落在圆/方或方/条分界线时来回跳变。
    reg [1:0] shape_pending0, shape_pending1, shape_pending2;
    reg       shape_wait0, shape_wait1, shape_wait2;
    wire motion_conflict0=filt_v0 && class_label_seen[0] && shape_cand0!=O_shape0 && F_class_motion(O_x0,O_y0,raw_x0,center_y0);
    wire keep_v0 = !motion_conflict0 && (filt_v0 || (O_v0 && (miss0 < LOSS_HOLD_FRAMES)));
    wire motion_conflict1=filt_v1 && class_label_seen[1] && shape_cand1!=O_shape1 && F_class_motion(O_x1,O_y1,raw_x1,center_y1);
    wire keep_v1 = !motion_conflict1 && (filt_v1 || (O_v1 && (miss1 < LOSS_HOLD_FRAMES)));
    wire motion_conflict2=filt_v2 && class_label_seen[2] && shape_cand2!=O_shape2 && F_class_motion(O_x2,O_y2,raw_x2,center_y2);
    wire keep_v2 = !motion_conflict2 && (filt_v2 || (O_v2 && (miss2 < LOSS_HOLD_FRAMES)));

    // 在最小旋转框上判断长条，避免“任一投影方向”把旋转方形误报为 BA。
    function F_elongated(input [13:0] a, input [13:0] b);
        // "small" is a Verilog-2000 keyword in the TD parser; use neutral
        // names here so the RTL remains accepted by both TD and simulators.
        reg [13:0] big_v, low_v;
        reg [16:0] big2;
        begin
            if (a >= b) begin big_v = a; low_v = b; end
            else begin big_v = b; low_v = a; end
            big2   = {2'b00, big_v, 1'b0};
            // Only 0/22.5/45-degree frames are stored. In the missing
            // 67.5-degree sector, a true 4:1 bar can project as about 1.66:1.
            // Use 3:2 projected aspect, not the physical object's 2:1 limit.
            F_elongated = (low_v == 0) ||
                (big2 > {2'b00,low_v,1'b0,1'b0});
        end
    endfunction

    function F_fast_move;
        input [10:0] ox,oy,nx,ny;
        reg signed [11:0] dx,dy;
        begin
            dx=$signed({1'b0,nx})-$signed({1'b0,ox});
            dy=$signed({1'b0,ny})-$signed({1'b0,oy});
            F_fast_move=(FAST_TRACK_ENABLE!=0) &&
                (dx>=FAST_TRACK_PIXELS || dx<=-FAST_TRACK_PIXELS ||
                 dy>=FAST_TRACK_PIXELS || dy<=-FAST_TRACK_PIXELS);
        end
    endfunction

    // 跨帧坐标一阶低通：new = (3*old + new)/4。比简单平均更能抑制
    // 阈值边缘造成的包围框抖动，同时只增加移位、加法和 2 位截断。
    function F_class_motion;
      input[10:0]ox,oy,nx,ny;reg signed[11:0]dx,dy;
      begin
       dx=$signed({1'b0,nx})-$signed({1'b0,ox});dy=$signed({1'b0,ny})-$signed({1'b0,oy});
       F_class_motion=(dx>=12'sd16 || dx<=-12'sd16 || dy>=12'sd16 || dy<=-12'sd16);
      end
    endfunction
    reg[2:0] class_label_seen;
    function [10:0] F_smooth4;
        input [10:0] old_v;
        input [10:0] new_v;
        reg signed [11:0] difference;
        reg signed [10:0] correction;
        reg signed [12:0] result;
        begin
            difference=$signed({1'b0,new_v})-$signed({1'b0,old_v});
            // old + floor((new-old+2)/4), without 3*old or wide carry chains.
            // Bit 1 is exactly the carry from adding 2 to the discarded bits.
            correction=$signed(difference[11:2])+$signed({10'b0,difference[1]});
            result=$signed({1'b0,old_v})+correction;
            F_smooth4=result[10:0];
        end
    endfunction

    function [1:0] classify_rot(input [30:0] box0, box45, box22, box67,
                                input [11:0] wp, du, dv,
                                input [9:0] h,
                                input [13:0] dp, dq, dr, ds,
                                input [17:0] area,
                                input [27:0] area232,
                                input [33:0] minimum5,
                                input v);
        reg [30:0] bmin, bmax;
        reg [13:0] sel_a, sel_b;
        reg [33:0] max4;
        reg [33:0] min5;
        reg [38:0] fill8, box5;
        reg [27:0] area_scaled;
        begin
            bmin = box0; bmax = box0; sel_a = {2'b00,wp}; sel_b = {4'b0000,h};
            if (box45 < bmin) begin bmin = box45; sel_a = du; sel_b = dv; end
            if (box22 < bmin) begin bmin = box22; sel_a = dp; sel_b = dq; end
            if (box67 < bmin) begin bmin = box67; sel_a = dr; sel_b = ds; end
            if (box67 > bmax) bmax = box67;
            if (box45 > bmax) bmax = box45;
            if (box22 > bmax) bmax = box22;

            // area_scaled 与 bmin 都以像素面积的同一比例表示：
            // area*232，其中 232=256-16-8；这样可直接比较填充率。
            area_scaled = area232;
            fill8 = {11'd0,area_scaled} << 3;
            min5 = minimum5;
            box5 = {5'd0,min5};
            max4 = {1'b0,bmax,2'b00};

            if (!v || (bmin == 0))
                classify_rot = 2'd3;
            else if (F_elongated(sel_a, sel_b))
                classify_rot = 2'd2;
            // 方案1：最小旋转框填充率低于 5/8 时判三角形；
            // 其余用三方向归一化外接框面积变化区分圆/方。去掉约
            // 67.5 度投影可省下三组候选乘法和寄存器，避免 Slice 超限；
            // 0/22.5/45 度已覆盖常见斜放目标。
            else if (fill8 < box5)
                classify_rot = 2'd3;
            else if(max4>=min5)
                classify_rot=2'd1;
            else classify_rot=2'd0;
        end
    endfunction

    // 分类仅在帧末使用。三个颜色分三拍选通到同一个比较器，避免
    // bmin/bmax、填充率、长宽比比较在像素主路径外复制三份。
    reg [1:0] shape_cand0, shape_cand1, shape_cand2;
    // Normalize one color per slot, one cycle before its existing classifier.
    // Source products are already stable by fe_d[4]. No publication delay.
    localparam SHARED_FRAME=(IMG_W_GRP*IMG_H_GRP>=32);
    wire serial_c0=|fe_d[4:1],serial_c1=|fe_d[8:5];
    wire serial_axis=fe_d[1] || fe_d[5] || fe_d[9];
    wire serial_diag=fe_d[2] || fe_d[6] || fe_d[10];
    wire serial_rot22=fe_d[3] || fe_d[7] || fe_d[11];
    wire serial_active=|fe_d[12:1];
    wire[9:0]serial_w=serial_c0?c_w0:serial_c1?c_w1:c_w2;
    wire[9:0]serial_h=serial_c0?c_h0:serial_c1?c_h1:c_h2;
    wire[11:0]serial_u=serial_c0?blob_du0:serial_c1?blob_du1:blob_du2;
    wire[11:0]serial_v=serial_c0?blob_dv0:serial_c1?blob_dv1:blob_dv2;
    wire[13:0]serial_p=serial_c0?blob_dp0:serial_c1?blob_dp1:blob_dp2;
    wire[13:0]serial_q=serial_c0?blob_dq0:serial_c1?blob_dq1:blob_dq2;
    wire[13:0]serial_r=serial_c0?blob_dr0:serial_c1?blob_dr1:blob_dr2;
    wire[13:0]serial_s=serial_c0?blob_ds0:serial_c1?blob_ds1:blob_ds2;
    wire[13:0]serial_l=serial_axis?{4'd0,serial_w}:serial_diag?{2'd0,serial_u}:serial_rot22?serial_p:serial_r;
    wire[13:0]serial_b=serial_axis?{4'd0,serial_h}:serial_diag?{2'd0,serial_v}:serial_rot22?serial_q:serial_s;
    (* dsp_style="yes" *) wire[27:0]serial_product=serial_l*serial_b;
    wire[7:0]serial_factor=serial_axis?8'd232:serial_diag?8'd29:8'd2;
    (* dsp_style="yes" *) wire[30:0]serial_normalized=serial_product*serial_factor;
    wire[13:0]serial_width=serial_axis?{serial_w,2'd0}:serial_l;
    reg[30:0]serial_min,serial_max;reg[13:0]serial_sel_a,serial_sel_b;
    always @(posedge I_clk or negedge I_rst_n)begin
     if(!I_rst_n)begin serial_min<=0;serial_max<=0;serial_sel_a<=0;serial_sel_b<=0;end
     else if(serial_active)begin
      if(serial_axis || serial_normalized<serial_min)begin
       serial_min<=serial_normalized;serial_sel_a<=serial_width;serial_sel_b<=serial_b;
      end
      if(serial_axis || serial_normalized>serial_max)serial_max<=serial_normalized;
     end
    end
    wire[17:0]class_area=fe_d[5]?s_a0:fe_d[9]?s_a1:s_a2;
    (* dsp_style="yes" *)wire[27:0]class_area232=class_area*8'd232;
    (* dsp_style="yes" *)wire[33:0]class_minimum5=serial_min*3'd5;
    wire[30:0]class_minimum=serial_min;
    wire[1:0]class_result=(serial_min==0)?2'd3:
      F_elongated(serial_sel_a,serial_sel_b)?2'd2:
      ({11'd0,class_area232,3'd0}<{5'd0,class_minimum5})?2'd3:
      ({1'd0,serial_max,2'd0}>=class_minimum5)?2'd1:2'd0;
    wire class_bar_dense=(class_result==2'd2) && ({1'd0,class_area232,2'd0}>=class_minimum);
    // For the red classifier only, recover a filled ellipse whose projected
    // extent is mildly wider than tall. Keep bars and low-fill fragments out.
    (* dsp_style="yes" *) wire [19:0] red_box_area = c_w0 * c_h0;
    wire [22:0] red_box_x7 = ({3'd0,red_box_area} << 3) - {3'd0,red_box_area};
    wire [20:0] red_area_x2 = {class_area,1'b0};
    wire [16:0] red_width_x5 = {3'd0,serial_sel_a} +
                                ({3'd0,serial_sel_a} << 2);
    wire [16:0] red_height_x7 = ({3'd0,serial_sel_b} << 3) -
                                 {3'd0,serial_sel_b};
    wire red_ellipse_aspect =
        (red_width_x5 >= red_height_x7) &&
        ({2'd0,serial_sel_a} <= ({2'd0,serial_sel_b} << 1));
    // Limit only the square-to-ellipse correction for small screen/skin
    // fragments. Keep small already-classified shapes and all tracking intact.
    wire red_ellipse_edge = (s_x0 == 0) || (s_xm0 == IMG_W_GRP-1) ||
                            (s_y0 == 0) || (s_ym0 == IMG_H_GRP-1);
    wire red_ellipse_scale_ok = (class_area >= 18'd1800) || red_ellipse_edge;
    wire red_filled_ellipse = (class_result == 2'd1) && red_ellipse_scale_ok &&
        red_ellipse_aspect &&
        ({3'd0,red_area_x2} >= {3'd0,red_box_area}) &&
        ({2'd0,class_area,3'b000} <= red_box_x7);


    // RGB 求均值/阈值判定先打一拍，避免它与候选区域更新、帧末过滤形成
    // 一条超长组合路径。x_d/y_d 与判定结果严格同拍。
    wire frame_end_stat = valid_d &&
                          (x_d == IMG_W_GRP-1) &&
                          (y_d == IMG_H_GRP-1);
    wire blob_done0, blob_done1, blob_done2;
    wire blob_v0, blob_v1, blob_v2;
    wire [9:0] blob_x0, blob_xm0, blob_y0, blob_ym0;
    wire [9:0] blob_x1, blob_xm1, blob_y1, blob_ym1;
    wire [9:0] blob_x2, blob_xm2, blob_y2, blob_ym2;
    wire [17:0] blob_a0, blob_a1, blob_a2;
    wire [11:0] blob_du0, blob_dv0, blob_du1, blob_dv1, blob_du2, blob_dv2;
    wire [13:0] blob_dp0, blob_dq0, blob_dp1, blob_dq1, blob_dp2, blob_dq2;
    // All three color trackers see the same delayed group coordinate. Compute
    // the four shape projections once here instead of replicating them inside
    // each color's candidate accumulator.
    wire [11:0] shared_x_pix = {x_d, 2'b00};
    wire [11:0] shared_proj_u = shared_x_pix + {2'b00,y_d};
    wire [11:0] shared_proj_v = 12'd2048 + shared_x_pix - {2'b00,y_d};
    wire [13:0] shared_proj_p = ({2'b00,shared_x_pix} << 2) +
                                 {2'b00,shared_x_pix} + ({4'b0000,y_d} << 1);
    wire [13:0] shared_proj_q = 14'd8192 + ({4'b0000,y_d} << 2) +
                                 {4'b0000,y_d} - ({2'b00,shared_x_pix} << 1);

    // 限量候选区域：同色的两个分离物体分别保留；每色只向外输出面积较大的候选。
    // 三个实例共享前级 HSV 掩码和像素坐标，不使用全帧标签 RAM。
    // RGB masks are mutually exclusive by their strict dominant-channel
    // tie rules. All six slots are retained; only the update ALU is shared.
    wire [416:0] blob_shared_result;
    wire[13:0]blob_dr0,blob_ds0,blob_dr1,blob_ds1,blob_dr2,blob_ds2;
    wire[13:0]shared_proj_r=({2'd0,shared_x_pix}<<1)+({4'd0,y_d}<<2)+{4'd0,y_d};
    wire[13:0]shared_proj_s=14'd8192+({4'd0,y_d}<<1)-({2'd0,shared_x_pix}<<2)-{2'd0,shared_x_pix};
    ua_blob_fouraxis_round2 #(.PROJECTION_SUPPORT(1)) u_blob_shared(
      .I_clk(I_clk),.I_rst_n(I_rst_n),.I_valid(valid_d),.I_sof(tuser_d),
      .I_eof(frame_end_stat),.I_hit({is_t2_d,is_t1_d,is_t0_d}),
      .I_x(x_d),.I_y(y_d),.I_proj_u(shared_proj_u),.I_proj_v(shared_proj_v),
      .I_proj_p(shared_proj_p),.I_proj_q(shared_proj_q),.I_proj_r(shared_proj_r),.I_proj_s(shared_proj_s),
      .O_frame_done(blob_done0),.O_result(blob_shared_result));
    assign blob_done1=blob_done0;
    assign blob_done2=blob_done0;
    assign {blob_v0,blob_x0,blob_xm0,blob_y0,blob_ym0,blob_a0,
            blob_du0,blob_dv0,blob_dp0,blob_dq0}=blob_shared_result[0+:111];
    assign {blob_dr0,blob_ds0}=blob_shared_result[111+:28];
    assign {blob_v1,blob_x1,blob_xm1,blob_y1,blob_ym1,blob_a1,
            blob_du1,blob_dv1,blob_dp1,blob_dq1}=blob_shared_result[139+:111];
    assign {blob_dr1,blob_ds1}=blob_shared_result[250+:28];
    assign {blob_v2,blob_x2,blob_xm2,blob_y2,blob_ym2,blob_a2,
            blob_du2,blob_dv2,blob_dp2,blob_dq2}=blob_shared_result[278+:111];
    assign {blob_dr2,blob_ds2}=blob_shared_result[389+:28];
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tlast <= 0; O_tuser <= 0; O_tdata <= 96'd0; O_tvalid <= 0;
            x_grp <= 0; y_pos <= 0;
            r_avg_d <= 0; g_avg_d <= 0; b_avg_d <= 0;
            avg_x_d <= 0; avg_y_d <= 0;
            avg_valid_d <= 0; avg_tuser_d <= 0;
            x_d <= 0; y_d <= 0;
            valid_d <= 0; tuser_d <= 0;
            is_t0_d <= 0; is_t1_d <= 0; is_t2_d <= 0;
            s_x0 <= 0; s_xm0 <= 0; s_y0 <= 0; s_ym0 <= 0;
            s_x1 <= 0; s_xm1 <= 0; s_y1 <= 0; s_ym1 <= 0;
            s_x2 <= 0; s_xm2 <= 0; s_y2 <= 0; s_ym2 <= 0;
            s_a0 <= 0; s_a1 <= 0; s_a2 <= 0;
            s_hit0 <= 0; s_hit1 <= 0; s_hit2 <= 0;
        end else begin
            O_tlast <= I_tlast; O_tuser <= I_tuser; O_tvalid <= I_tvalid; O_tdata <= I_tdata;

            // 第二级判色寄存：把 RGB 求和/均值与 max/min/chroma/hue 比较拆开。
            valid_d <= avg_valid_d;
            tuser_d <= avg_tuser_d;
            if (avg_valid_d) begin
                x_d <= avg_x_d;
                y_d <= avg_y_d;
                is_t0_d <= is_t0;
                is_t1_d <= is_t1;
                is_t2_d <= is_t2;
            end

            avg_valid_d <= I_tvalid;
            avg_tuser_d <= I_tuser;
            if (I_tvalid) begin
                // I_tuser 是本帧首个有效组的边界，而不是一个可选提示。
                // 显式把首组坐标钉在 (0,0)，避免上游存在气泡或上一帧
                // 未以固定宽度结束时，y_pos 残留造成整框向下漂移。
                avg_x_d <= I_tuser ? 10'd0 : x_grp;
                avg_y_d <= I_tuser ? 10'd0 : y_pos;
                r_avg_d <= r_avg;
                g_avg_d <= g_avg;
                b_avg_d <= b_avg;

                if (I_tuser) begin
                    // 当前拍已经采集了第 0 组；下一有效组从第 1 组开始。
                    x_grp <= (IMG_W_GRP <= 1) ? 10'd0 : 10'd1;
                    y_pos <= 10'd0;
                end else if (x_grp == IMG_W_GRP-1) begin
                    x_grp <= 0;
                    if (y_pos == IMG_H_GRP-1) y_pos <= 0;
                    else y_pos <= y_pos + 1;
                end else
                    x_grp <= x_grp + 1;
            end

            // 候选模块在 EOF 后一拍锁存最大候选；此处再快照，确保末组命中已计入。
            if (blob_done0) begin
                s_x0 <= blob_x0; s_xm0 <= blob_xm0; s_y0 <= blob_y0; s_ym0 <= blob_ym0;
                s_a0 <= blob_a0; s_hit0 <= blob_v0;
                s_x1 <= blob_x1; s_xm1 <= blob_xm1; s_y1 <= blob_y1; s_ym1 <= blob_ym1;
                s_a1 <= blob_a1; s_hit1 <= blob_v1;
                s_x2 <= blob_x2; s_xm2 <= blob_xm2; s_y2 <= blob_y2; s_ym2 <= blob_ym2;
                s_a2 <= blob_a2; s_hit2 <= blob_v2;
            end
        end
    end

    // ---- 帧末流水: 每色复用一个 14x14 面积乘法器 ----
    // fe_d[0]: 跨度/尺寸; [1]: 轴向面积; [2]: 45°面积及轴向归一化;
    // [3]: 22.5°面积及45°归一化; [4]: 22.5°归一化;
    // [5..7]: 依次分类红/绿/蓝；[8]: 同拍发布三色结果。
    reg [14:0] fe_d;
    // Resource prototype: three IIR datapaths across the existing six idle
    // post-frame slots. Publish all coordinates atomically at original fe_d[8].
    wire [10:0] shared_x0,shared_y0,shared_xmin0,shared_xmax0,shared_ymin0,shared_ymax0;
    wire [10:0] shared_x1,shared_y1,shared_xmin1,shared_xmax1,shared_ymin1,shared_ymax1;
    wire [10:0] shared_x2,shared_y2,shared_xmin2,shared_xmax2,shared_ymin2,shared_ymax2;
    generate if(IMG_W_GRP*IMG_H_GRP>=32) begin:gen_shared_smooth
      reg [32:0] smooth_work[0:5];
      reg [32:0] smooth_old,smooth_new;
      reg smooth_enabled;
      reg fast_pair;
      wire first_half=fe_d[2] || fe_d[4] || fe_d[6];
      wire fast_now=F_fast_move(smooth_old[32:22],smooth_old[21:11],
                               smooth_new[32:22],smooth_new[21:11]);
      wire use_fast=first_half?fast_now:fast_pair;
      always @* begin
       smooth_old=0;smooth_new=0;smooth_enabled=0;
       case(1'b1)
        fe_d[2]:begin smooth_old={O_x0,O_y0,O_xmin0};smooth_new={raw_x0,center_y0,raw_xmin0};smooth_enabled=O_v0;end
        fe_d[3]:begin smooth_old={O_xmax0,O_ymin0,O_ymax0};smooth_new={raw_xmax0,raw_ymin0,raw_ymax0};smooth_enabled=O_v0;end
        fe_d[4]:begin smooth_old={O_x1,O_y1,O_xmin1};smooth_new={raw_x1,center_y1,raw_xmin1};smooth_enabled=O_v1;end
        fe_d[5]:begin smooth_old={O_xmax1,O_ymin1,O_ymax1};smooth_new={raw_xmax1,raw_ymin1,raw_ymax1};smooth_enabled=O_v1;end
        fe_d[6]:begin smooth_old={O_x2,O_y2,O_xmin2};smooth_new={raw_x2,center_y2,raw_xmin2};smooth_enabled=O_v2;end
        fe_d[7]:begin smooth_old={O_xmax2,O_ymin2,O_ymax2};smooth_new={raw_xmax2,raw_ymin2,raw_ymax2};smooth_enabled=O_v2;end
        default:begin end
       endcase
      end
      wire [32:0] smooth_result=(smooth_enabled && !use_fast) ? {
       F_smooth4(smooth_old[32:22],smooth_new[32:22]),
       F_smooth4(smooth_old[21:11],smooth_new[21:11]),
       F_smooth4(smooth_old[10:0],smooth_new[10:0])} : smooth_new;
      // Payload is not observed until fe_d[8], after every one of the six
      // words has been written at [2..7]. Output validity/coordinates retain
      // reset. Removing the unobservable 198-bit reset lets TD pack these
      // registers with the existing datapath rather than reset-only slices.
      always @(posedge I_clk)begin
        if(fe_d[2])smooth_work[0]<=smooth_result;
        if(fe_d[3])smooth_work[1]<=smooth_result;
        if(fe_d[4])smooth_work[2]<=smooth_result;
        if(fe_d[5])smooth_work[3]<=smooth_result;
        if(fe_d[6])smooth_work[4]<=smooth_result;
        if(fe_d[7])smooth_work[5]<=smooth_result;
      end
      // The SAME decision controls centre and all four bounds atomically.
      // Do not independently threshold each coordinate (can invert a box).
      always @(posedge I_clk or negedge I_rst_n)
       if(!I_rst_n)fast_pair<=0;else if(first_half)fast_pair<=fast_now;
      assign {shared_x0,shared_y0,shared_xmin0}=smooth_work[0];
      assign {shared_xmax0,shared_ymin0,shared_ymax0}=smooth_work[1];
      assign {shared_x1,shared_y1,shared_xmin1}=smooth_work[2];
      assign {shared_xmax1,shared_ymin1,shared_ymax1}=smooth_work[3];
      assign {shared_x2,shared_y2,shared_xmin2}=smooth_work[4];
      assign {shared_xmax2,shared_ymin2,shared_ymax2}=smooth_work[5];
    end else begin:gen_short_frame_smooth
      assign shared_x0=O_v0 ? F_smooth4(O_x0,raw_x0) : raw_x0;
      assign shared_y0=O_v0 ? F_smooth4(O_y0,center_y0) : center_y0;
      assign shared_xmin0=O_v0 ? F_smooth4(O_xmin0,raw_xmin0) : raw_xmin0;
      assign shared_xmax0=O_v0 ? F_smooth4(O_xmax0,raw_xmax0) : raw_xmax0;
      assign shared_ymin0=O_v0 ? F_smooth4(O_ymin0,raw_ymin0) : raw_ymin0;
      assign shared_ymax0=O_v0 ? F_smooth4(O_ymax0,raw_ymax0) : raw_ymax0;
      assign shared_x1=O_v1 ? F_smooth4(O_x1,raw_x1) : raw_x1;
      assign shared_y1=O_v1 ? F_smooth4(O_y1,center_y1) : center_y1;
      assign shared_xmin1=O_v1 ? F_smooth4(O_xmin1,raw_xmin1) : raw_xmin1;
      assign shared_xmax1=O_v1 ? F_smooth4(O_xmax1,raw_xmax1) : raw_xmax1;
      assign shared_ymin1=O_v1 ? F_smooth4(O_ymin1,raw_ymin1) : raw_ymin1;
      assign shared_ymax1=O_v1 ? F_smooth4(O_ymax1,raw_ymax1) : raw_ymax1;
      assign shared_x2=O_v2 ? F_smooth4(O_x2,raw_x2) : raw_x2;
      assign shared_y2=O_v2 ? F_smooth4(O_y2,center_y2) : center_y2;
      assign shared_xmin2=O_v2 ? F_smooth4(O_xmin2,raw_xmin2) : raw_xmin2;
      assign shared_xmax2=O_v2 ? F_smooth4(O_xmax2,raw_xmax2) : raw_xmax2;
      assign shared_ymin2=O_v2 ? F_smooth4(O_ymin2,raw_ymin2) : raw_ymin2;
      assign shared_ymax2=O_v2 ? F_smooth4(O_ymax2,raw_ymax2) : raw_ymax2;
    end endgenerate

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            fe_d <= 15'd0;class_label_seen<=0;
            shape_cand0 <= 2'd3; shape_cand1 <= 2'd3; shape_cand2 <= 2'd3;
            bar_dense0 <= 1'b0; bar_dense1 <= 1'b0; bar_dense2 <= 1'b0;
            c_w0 <= 0; c_w1 <= 0; c_w2 <= 0;
            c_h0 <= 0; c_h1 <= 0; c_h2 <= 0;
            c_ba0 <= 0; c_ba1 <= 0; c_ba2 <= 0;
            c_wp0 <= 0; c_wp1 <= 0; c_wp2 <= 0;
            c_a80 <= 0; c_a81 <= 0; c_a82 <= 0;
            s_v0 <= 0; s_v1 <= 0; s_v2 <= 0;
            miss0 <= 0; miss1 <= 0; miss2 <= 0;
            shape_pending0 <= 2'd3; shape_pending1 <= 2'd3; shape_pending2 <= 2'd3;
            shape_wait0 <= 1'b0; shape_wait1 <= 1'b0; shape_wait2 <= 1'b0;
            O_v0 <= 0; O_x0 <= 0; O_y0 <= 0; O_shape0 <= 2'd3;
            O_xmin0 <= 0; O_xmax0 <= 0; O_ymin0 <= 0; O_ymax0 <= 0;
            O_v1 <= 0; O_x1 <= 0; O_y1 <= 0; O_shape1 <= 2'd3;
            O_xmin1 <= 0; O_xmax1 <= 0; O_ymin1 <= 0; O_ymax1 <= 0;
            O_v2 <= 0; O_x2 <= 0; O_y2 <= 0; O_shape2 <= 2'd3;
            O_xmin2 <= 0; O_xmax2 <= 0; O_ymin2 <= 0; O_ymax2 <= 0;
            O_obj_cnt <= 4'd0;
            O_track_valid <= 0;
        end else begin
            fe_d <= {fe_d[13:0], blob_done0};
            O_track_valid <= 1'b0;
            if (fe_d[5]) begin shape_cand0 <= red_filled_ellipse ? 2'd0 : class_result; bar_dense0 <= class_bar_dense; end
            if (fe_d[9]) begin shape_cand1 <= class_result; bar_dense1 <= class_bar_dense; end
            if (fe_d[13]) begin shape_cand2 <= class_result; bar_dense2 <= class_bar_dense; end

            if (fe_d[0]) begin
                // w/h 减法 (s_* 寄存器出发, 1 级) — 供 fe_d[1] 乘法用
                c_w0 <= s_xm0 - s_x0 + 10'd1;
                c_h0 <= s_ym0 - s_y0 + 10'd1;
                c_w1 <= s_xm1 - s_x1 + 10'd1;
                c_h1 <= s_ym1 - s_y1 + 10'd1;
                c_w2 <= s_xm2 - s_x2 + 10'd1;
                c_h2 <= s_ym2 - s_y2 + 10'd1;
                // s_v 用组合 w/h 直算 (不依赖 c_w 寄存器, 避免读旧值)
                s_v0 <= s_hit0 &&
                        ((s_xm0 - s_x0 + 10'd1) >= MIN_W_G) &&
                        ((s_ym0 - s_y0 + 10'd1) >= MIN_H_G);
                s_v1 <= s_hit1 &&
                        ((s_xm1 - s_x1 + 10'd1) >= MIN_W_G) &&
                        ((s_ym1 - s_y1 + 10'd1) >= MIN_H_G);
                s_v2 <= s_hit2 &&
                        ((s_xm2 - s_x2 + 10'd1) >= MIN_W_G) &&
                        ((s_ym2 - s_y2 + 10'd1) >= MIN_H_G);
            end

            if(fe_d[1])begin
                c_ba0<=serial_product[19:0];
                c_wp0<={c_w0,2'd0};c_wp1<={c_w1,2'd0};c_wp2<={c_w2,2'd0};
                c_a80<={1'b0,s_a0,3'd0};c_a81<={1'b0,s_a1,3'd0};c_a82<={1'b0,s_a2,3'd0};
            end
            if(fe_d[5])c_ba1<=serial_product[19:0];
            if(fe_d[9])c_ba2<=serial_product[19:0];

            if (fe_d[14]) begin
                // 区域过滤 + 跨帧稳定。首次锁定直接输出；已锁定后坐标取
                // (3*old+new)/4，抑制阈值边缘造成的包围盒抖动。
                if (filt_v0) begin
                    O_v0 <= 1'b1; miss0 <= 0;
                    O_x0 <= shared_x0;
                    O_y0 <= shared_y0;
                    O_xmin0 <= shared_xmin0;
                    O_xmax0 <= shared_xmax0;
                    O_ymin0 <= shared_ymin0;
                    O_ymax0 <= shared_ymax0;
                    if(motion_conflict0)begin
                        O_v0<=0;shape_wait0<=0;shape_pending0<=O_shape0;
                        O_x0<=raw_x0;O_y0<=center_y0;
                        O_xmin0<=raw_xmin0;O_xmax0<=raw_xmax0;O_ymin0<=raw_ymin0;O_ymax0<=raw_ymax0;
                    end else if (!class_label_seen[0]) begin
                        class_label_seen[0]<=1;
                        O_shape0 <= shape_cand0;
                        shape_pending0 <= shape_cand0;
                        shape_wait0 <= 1'b0;
                    end else if (shape_cand0 == O_shape0) begin
                        shape_pending0 <= shape_cand0;
                        shape_wait0 <= 1'b0;
                    end else if (shape_pending0 != shape_cand0) begin
                        shape_pending0 <= shape_cand0;
                        shape_wait0 <= 1'b1;
                    end else if (shape_wait0) begin
                        O_shape0 <= shape_cand0;
                        shape_wait0 <= 1'b0;
                    end else begin
                        shape_wait0 <= 1'b1;
                    end
                end else if (O_v0 && (miss0 < LOSS_HOLD_FRAMES)) begin
                    O_v0 <= 1'b1; miss0 <= miss0 + 1'b1;
                    // A missing frame breaks consecutive class evidence.
                    shape_wait0 <= 1'b0; shape_pending0 <= O_shape0;
                end else begin
                    O_v0 <= 1'b0; class_label_seen[0]<=0;miss0 <= miss0; O_shape0 <= 2'd3;
                    shape_pending0 <= 2'd3; shape_wait0 <= 1'b0;
                    O_xmin0 <= 11'd0; O_xmax0 <= 11'd0; O_ymin0 <= 11'd0; O_ymax0 <= 11'd0;
                end

                if (filt_v1) begin
                    O_v1 <= 1'b1; miss1 <= 0;
                    O_x1 <= shared_x1;
                    O_y1 <= shared_y1;
                    O_xmin1 <= shared_xmin1;
                    O_xmax1 <= shared_xmax1;
                    O_ymin1 <= shared_ymin1;
                    O_ymax1 <= shared_ymax1;
                    if(motion_conflict1)begin
                        O_v1<=0;shape_wait1<=0;shape_pending1<=O_shape1;
                        O_x1<=raw_x1;O_y1<=center_y1;
                        O_xmin1<=raw_xmin1;O_xmax1<=raw_xmax1;O_ymin1<=raw_ymin1;O_ymax1<=raw_ymax1;
                    end else if (!class_label_seen[1]) begin
                        class_label_seen[1]<=1;
                        O_shape1 <= shape_cand1;
                        shape_pending1 <= shape_cand1;
                        shape_wait1 <= 1'b0;
                    end else if (shape_cand1 == O_shape1) begin
                        shape_pending1 <= shape_cand1;
                        shape_wait1 <= 1'b0;
                    end else if (shape_pending1 != shape_cand1) begin
                        shape_pending1 <= shape_cand1;
                        shape_wait1 <= 1'b1;
                    end else if (shape_wait1) begin
                        O_shape1 <= shape_cand1;
                        shape_wait1 <= 1'b0;
                    end else begin
                        shape_wait1 <= 1'b1;
                    end
                end else if (O_v1 && (miss1 < LOSS_HOLD_FRAMES)) begin
                    O_v1 <= 1'b1; miss1 <= miss1 + 1'b1;
                    // A missing frame breaks consecutive class evidence.
                    shape_wait1 <= 1'b0; shape_pending1 <= O_shape1;
                end else begin
                    O_v1 <= 1'b0; class_label_seen[1]<=0;miss1 <= miss1; O_shape1 <= 2'd3;
                    shape_pending1 <= 2'd3; shape_wait1 <= 1'b0;
                    O_xmin1 <= 11'd0; O_xmax1 <= 11'd0; O_ymin1 <= 11'd0; O_ymax1 <= 11'd0;
                end

                if (filt_v2) begin
                    O_v2 <= 1'b1; miss2 <= 0;
                    O_x2 <= shared_x2;
                    O_y2 <= shared_y2;
                    O_xmin2 <= shared_xmin2;
                    O_xmax2 <= shared_xmax2;
                    O_ymin2 <= shared_ymin2;
                    O_ymax2 <= shared_ymax2;
                    if(motion_conflict2)begin
                        O_v2<=0;shape_wait2<=0;shape_pending2<=O_shape2;
                        O_x2<=raw_x2;O_y2<=center_y2;
                        O_xmin2<=raw_xmin2;O_xmax2<=raw_xmax2;O_ymin2<=raw_ymin2;O_ymax2<=raw_ymax2;
                    end else if (!class_label_seen[2]) begin
                        class_label_seen[2]<=1;
                        O_shape2 <= shape_cand2;
                        shape_pending2 <= shape_cand2;
                        shape_wait2 <= 1'b0;
                    end else if (shape_cand2 == O_shape2) begin
                        shape_pending2 <= shape_cand2;
                        shape_wait2 <= 1'b0;
                    end else if (shape_pending2 != shape_cand2) begin
                        shape_pending2 <= shape_cand2;
                        shape_wait2 <= 1'b1;
                    end else if (shape_wait2) begin
                        O_shape2 <= shape_cand2;
                        shape_wait2 <= 1'b0;
                    end else begin
                        shape_wait2 <= 1'b1;
                    end
                end else if (O_v2 && (miss2 < LOSS_HOLD_FRAMES)) begin
                    O_v2 <= 1'b1; miss2 <= miss2 + 1'b1;
                    // A missing frame breaks consecutive class evidence.
                    shape_wait2 <= 1'b0; shape_pending2 <= O_shape2;
                end else begin
                    O_v2 <= 1'b0; class_label_seen[2]<=0;miss2 <= miss2; O_shape2 <= 2'd3;
                    shape_pending2 <= 2'd3; shape_wait2 <= 1'b0;
                    O_xmin2 <= 11'd0; O_xmax2 <= 11'd0; O_ymin2 <= 11'd0; O_ymax2 <= 11'd0;
                end

                O_obj_cnt <= {3'b000,keep_v0} + {3'b000,keep_v1} + {3'b000,keep_v2};
                O_track_valid <= 1'b1;
            end
        end
    end
endmodule

// Three colour channels, two candidate slots each. Hit must be one-hot or zero.
// Same EOF publication cycle as three ua_blob_select2 instances. One shared
// descriptor update ALU; all six descriptors/valid bits remain independent.
// The ERAM profile keeps two exact descriptors per colour. Published blob
// metadata is three clocks later; raster pixels and frame throughput do not
// change. Tiny synthetic frames retain the legacy combinational bank.
module ua_blob_bank3 #(parameter integer USE_ERAM=0,PROJECTION_SUPPORT=0)(
 input I_clk,I_rst_n,I_valid,I_sof,I_eof,input[2:0]I_hit,
 input[9:0]I_x,I_y,input[11:0]I_proj_u,I_proj_v,input[13:0]I_proj_p,I_proj_q,
 output O_frame_done,output[332:0]O_result
);
 generate if(USE_ERAM)begin:gen_eram
  ua_blob_bank3_eram #(.PROJECTION_SUPPORT(PROJECTION_SUPPORT)) storage(I_clk,I_rst_n,I_valid,I_sof,I_eof,I_hit,I_x,I_y,
   I_proj_u,I_proj_v,I_proj_p,I_proj_q,O_frame_done,O_result);
 end else begin:gen_legacy
  ua_blob_bank3_legacy storage(I_clk,I_rst_n,I_valid,I_sof,I_eof,I_hit,I_x,I_y,
   I_proj_u,I_proj_v,I_proj_p,I_proj_q,O_frame_done,O_result);
 end endgenerate
endmodule

module ua_blob_bank3_eram #(parameter integer PROJECTION_SUPPORT=0)(
 input I_clk,I_rst_n,I_valid,I_sof,I_eof,input[2:0]I_hit,
 input[9:0]I_x,I_y,input[11:0]I_proj_u,I_proj_v,input[13:0]I_proj_p,I_proj_q,
 output reg O_frame_done,output reg[332:0]O_result
);
 wire[1:0] input_ch=I_hit[0]?2'd0:I_hit[1]?2'd1:2'd2;
 /* fehdl force_ram=1, ram_style="bram" */ reg[343:0] descriptors[0:511];
 reg[343:0] read_pair,forward_pair;
 reg p_valid,p_sof,p_eof,p_hit,forward_valid;
 reg[1:0]p_ch,forward_ch;
 reg[2:0]p_hit_bits,v0,v1;
 reg[9:0]px,py;reg[11:0]pu,pv;reg[13:0]pp,pq;
 wire projection_hit;
 generate if(PROJECTION_SUPPORT)begin:gen_projection_rows
  reg[9:0]row_min[0:2],row_max[0:2],p1_min[0:2],p1_max[0:2],p2_min[0:2],p2_max[0:2];
  reg[2:0]row_v,p1_v,p2_v;reg[9:0]row_y;integer ch;
  reg[9:0]p3_min[0:2],p3_max[0:2];reg[2:0]p3_v;
  reg[9:0]p4_min[0:2],p4_max[0:2];reg[2:0]p4_v;
  reg[2:0]hist[0:2];integer hi;
  wire new_row=I_y!=row_y;
  wire[2:0]v1=new_row?row_v:p1_v,v2=new_row?p1_v:p2_v;
  wire[2:0]v3=new_row?p2_v:p3_v;
  wire[2:0]v4=new_row?p3_v:p4_v;
  wire[2:0]supported;
  wire x_zero=(I_x==10'd0);
  wire[9:0]x_minus_one=I_x-10'd1;
  for(genvar c=0;c<3;c=c+1)begin:gen_support
   wire[9:0]a=new_row?row_min[c]:p1_min[c],b=new_row?row_max[c]:p1_max[c];
   wire[9:0]d=new_row?p1_min[c]:p2_min[c],e=new_row?p1_max[c]:p2_max[c];
   wire[9:0]lo3=new_row?p2_min[c]:p3_min[c],hi3=new_row?p2_max[c]:p3_max[c];
   wire[9:0]lo4=new_row?p3_min[c]:p4_min[c],hi4=new_row?p3_max[c]:p4_max[c];
   assign supported[c]=!I_sof && v1[c] && v2[c] &&
    ({1'b0,I_x}+11'd1>={1'b0,a}) && (x_zero || x_minus_one<=b) &&
    ({1'b0,I_x}+11'd1>={1'b0,d}) && (x_zero || x_minus_one<=e) && v3[c] && ({1'b0,I_x}+11'd1>={1'b0,lo3}) && (x_zero || x_minus_one<=hi3) && v4[c] && ({1'b0,I_x}+11'd1>={1'b0,lo4}) && (x_zero || x_minus_one<=hi4);
  end
  wire[2:0]local_solid=(!new_row && !I_sof)?(I_hit&hist[0]&hist[1]&hist[2]):3'd0;
  assign projection_hit=|(supported&local_solid);
  // Payload is observed only under row-valid tags; no reset fanout to spans.
  always @(posedge I_clk)if(I_rst_n && I_valid)begin
   for(ch=0;ch<3;ch=ch+1)begin
    if(I_sof || new_row)begin
     p2_min[ch]<=p1_min[ch];p2_max[ch]<=p1_max[ch];p1_min[ch]<=row_min[ch];p1_max[ch]<=row_max[ch];
     p3_min[ch]<=p2_min[ch];p3_max[ch]<=p2_max[ch];
     p4_min[ch]<=p3_min[ch];p4_max[ch]<=p3_max[ch];
     row_min[ch]<=I_x;row_max[ch]<=I_x;
    end else if(local_solid[ch])begin
     if(!row_v[ch])row_min[ch]<=I_x;
     row_max[ch]<=I_x;
    end
   end
  end
  always @(posedge I_clk or negedge I_rst_n)begin
   if(!I_rst_n)begin hist[0]<=0;hist[1]<=0;hist[2]<=0;row_v<=0;p1_v<=0;p2_v<=0;p3_v<=0;p4_v<=0;row_y<=0;end
   else if(I_valid)begin
    if(I_sof || new_row)begin hist[2]<=0;hist[1]<=0;end
    else for(hi=2;hi>0;hi=hi-1)hist[hi]<=hist[hi-1];
    hist[0]<=I_hit;
    row_y<=I_y;
    if(I_sof)begin row_v<=0;p1_v<=0;p2_v<=0;p3_v<=0;p4_v<=0;end
    else if(new_row)begin row_v<=0;p1_v<=row_v;p2_v<=p1_v;p3_v<=p2_v;p4_v<=p3_v;end
    else row_v<=row_v|local_solid;
   end
  end
 end else begin:gen_raw_projection
  assign projection_hit=1'b1;
 end endgenerate
 reg p_projection;
 wire write_descriptor=p_valid && p_hit;
 wire[343:0] current_pair=(forward_valid && forward_ch==p_ch)?forward_pair:read_pair;
 wire[171:0]a=current_pair[343:172],b=current_pair[171:0];
 localparam [9:0] MATCH_GAP_X=PROJECTION_SUPPORT?10'd3:10'd1;
 wire y_upper_guard=(py<=10'd2);
 wire [9:0] py_minus2=py-10'd2;
 wire x_upper_guard=(px<=MATCH_GAP_X);
 wire [9:0] px_minus_gap=px-MATCH_GAP_X;
 wire match0=v0[p_ch] && (y_upper_guard || py_minus2<=a[131:122]) &&
  py>=a[151:142] && ({1'b0,px}+(PROJECTION_SUPPORT?11'd3:11'd1)>={1'b0,a[171:162]}) &&
  (x_upper_guard || px_minus_gap<=a[161:152]);
 wire match1=v1[p_ch] && (y_upper_guard || py_minus2<=b[131:122]) &&
  py>=b[151:142] && ({1'b0,px}+(PROJECTION_SUPPORT?11'd3:11'd1)>={1'b0,b[171:162]}) &&
  (x_upper_guard || px_minus_gap<=b[161:152]);
 wire target1=p_sof?1'b0:match0?1'b0:match1?1'b1:!v0[p_ch]?1'b0:!v1[p_ch]?1'b1:
  (a[121:104]<=b[121:104])?1'b0:1'b1;
 wire replace_slot=p_sof || (!match0 && !match1);
 wire[171:0]old=target1?b:a;
 reg[171:0]updated;
 always @*begin
  updated=old;
  if(replace_slot)updated={px,px,py,py,py,18'd1,
   (p_projection?pu:12'hfff),(p_projection?pu:12'd0),(p_projection?pv:12'hfff),(p_projection?pv:12'd0),
   (p_projection?pp:14'h3fff),(p_projection?pp:14'd0),(p_projection?pq:14'h3fff),(p_projection?pq:14'd0)};
  else begin
   updated[131:122]=py;updated[121:104]=old[121:104]+18'd1;
   if(px<old[171:162])updated[171:162]=px;if(px>old[161:152])updated[161:152]=px;
   if(py<old[151:142])updated[151:142]=py;if(py>old[141:132])updated[141:132]=py;
   if(p_projection)begin
   if(pu<old[103:92])updated[103:92]=pu;if(pu>old[91:80])updated[91:80]=pu;
   if(pv<old[79:68])updated[79:68]=pv;if(pv>old[67:56])updated[67:56]=pv;
   if(pp<old[55:42])updated[55:42]=pp;if(pp>old[41:28])updated[41:28]=pp;
   if(pq<old[27:14])updated[27:14]=pq;if(pq>old[13:0])updated[13:0]=pq;
   end
  end
 end
 wire[343:0] updated_pair=target1?{a,updated}:{updated,b};
 // Forward a write on the next cycle. Suppress simultaneous same-address
 // reads: neither simulation nor hardware relies on ERAM collision mode.
 always @(posedge I_clk)if(I_rst_n)begin
  if(I_valid && !(write_descriptor && p_ch==input_ch))read_pair<=descriptors[{7'd0,input_ch}];
  if(write_descriptor)descriptors[{7'd0,p_ch}]<=updated_pair;
 end
 reg pub_valid,pub_sof,pub_v0,pub_v1;
 reg[1:0]pub_ch,selected_ch;
 reg selected_valid,selected_sof;
 reg[171:0]selected;
 wire no_projection=PROJECTION_SUPPORT && selected[91:80]<selected[103:92];
 wire[11:0]fallback_w=({2'b0,selected[161:152]}-{2'b0,selected[171:162]}+12'd1)<<2;
 wire[11:0]fallback_h={2'b0,selected[141:132]}-{2'b0,selected[151:142]}+12'd1;
 wire[11:0]fallback_diag=fallback_w+fallback_h;
 wire[13:0]fallback_p=({2'b0,fallback_w}<<2)+{2'b0,fallback_w}+({2'b0,fallback_h}<<1);
 wire[13:0]fallback_q=({2'b0,fallback_w}<<1)+({2'b0,fallback_h}<<2)+{2'b0,fallback_h};
 wire pub_winner0=pub_v0 && (!pub_v1 || forward_pair[293:276]>=forward_pair[121:104]);
 reg[110:0]winner_cache[0:2];reg[2:0]winner_valid,end_delay;
 integer c;
 // Data registers are consumed only under their resettable valid tags.
 // Avoid distributing asynchronous reset to 588 unobservable payload bits.
 always @(posedge I_clk)if(I_rst_n)begin
  if(I_valid)begin px<=I_x;py<=I_y;pu<=I_proj_u;pv<=I_proj_v;pp<=I_proj_p;pq<=I_proj_q;end
  if(write_descriptor)forward_pair<=updated_pair;
  if(pub_valid)selected<=pub_winner0?forward_pair[343:172]:forward_pair[171:0];
 end
 always @(posedge I_clk or negedge I_rst_n)begin
  if(!I_rst_n)begin
   p_projection<=0;p_valid<=0;p_sof<=0;p_eof<=0;p_hit<=0;p_ch<=0;p_hit_bits<=0;
   v0<=0;v1<=0;
   forward_valid<=0;forward_ch<=0;
   pub_valid<=0;pub_sof<=0;pub_v0<=0;pub_v1<=0;pub_ch<=0;
   selected_valid<=0;selected_sof<=0;selected_ch<=0;
   winner_valid<=0;end_delay<=0;O_frame_done<=0;O_result<=0;
  end else begin
   p_valid<=I_valid;
   if(I_valid)begin
    p_projection<=projection_hit;p_sof<=I_sof;p_eof<=I_eof;p_hit<=|I_hit;p_hit_bits<=I_hit;p_ch<=input_ch;
   end
   forward_valid<=write_descriptor;
   if(write_descriptor)forward_ch<=p_ch;
   if(p_valid)begin
    if(p_sof)begin v0<=p_hit_bits;v1<=0;end
    else if(p_hit)begin if(target1)v1[p_ch]<=1;else v0[p_ch]<=1;end
   end
   pub_valid<=write_descriptor;pub_sof<=p_valid && p_sof;
   pub_ch<=p_ch;pub_v0<=p_sof?p_hit:(!target1 || v0[p_ch]);
   pub_v1<=!p_sof && (target1 || v1[p_ch]);
   selected_valid<=pub_valid;selected_sof<=pub_sof;selected_ch<=pub_ch;
   if(selected_sof)winner_valid<=0;
   if(selected_valid)begin
    winner_valid[selected_ch]<=1;
    winner_cache[selected_ch]<={1'b1,selected[171:132],selected[121:104],
     (no_projection?fallback_diag:(selected[91:80]-selected[103:92]+(PROJECTION_SUPPORT?12'd17:12'd5))),(no_projection?fallback_diag:(selected[67:56]-selected[79:68]+(PROJECTION_SUPPORT?12'd17:12'd5))),
     (no_projection?fallback_p:(selected[41:28]-selected[55:42]+(PROJECTION_SUPPORT?14'd82:14'd22))),(no_projection?fallback_q:(selected[13:0]-selected[27:14]+(PROJECTION_SUPPORT?14'd37:14'd13)))};
   end
   end_delay<={end_delay[1:0],p_valid && p_eof};
   O_frame_done<=end_delay[2];
   if(end_delay[2])for(c=0;c<3;c=c+1)
    O_result[c*111+:111]<=winner_valid[c]?winner_cache[c]:111'd0;
  end
 end
endmodule

module ua_blob_bank3_legacy(
 input I_clk,I_rst_n,I_valid,I_sof,I_eof,input[2:0]I_hit,
 input[9:0]I_x,I_y,input[11:0]I_proj_u,I_proj_v,input[13:0]I_proj_p,I_proj_q,
 output reg O_frame_done,output reg[332:0]O_result
);
 reg[171:0]slot0[0:2],slot1[0:2];
 reg[2:0]v0,v1;reg emit_pending;
 wire[1:0]ch=I_hit[0]?2'd0:I_hit[1]?2'd1:2'd2;
 wire[171:0]a=slot0[ch],b=slot1[ch];
 wire match0=v0[ch] && ({1'b0,I_y}<={1'b0,a[131:122]}+11'd2) &&
   I_y>=a[151:142] && ({1'b0,I_x}+11'd1>={1'b0,a[171:162]}) &&
   ({1'b0,I_x}<={1'b0,a[161:152]}+11'd1);
 wire match1=v1[ch] && ({1'b0,I_y}<={1'b0,b[131:122]}+11'd2) &&
   I_y>=b[151:142] && ({1'b0,I_x}+11'd1>={1'b0,b[171:162]}) &&
   ({1'b0,I_x}<={1'b0,b[161:152]}+11'd1);
 wire target1=I_sof?1'b0:match0?1'b0:match1?1'b1:!v0[ch]?1'b0:!v1[ch]?1'b1:
              (a[121:104]<=b[121:104])?1'b0:1'b1;
 wire replace_slot=I_sof || (!match0 && !match1);
 wire[171:0]old=target1?b:a;
 reg[171:0]updated;
 always @*begin
   updated=old;
   if(replace_slot)updated={I_x,I_x,I_y,I_y,I_y,18'd1,
       I_proj_u,I_proj_u,I_proj_v,I_proj_v,I_proj_p,I_proj_p,I_proj_q,I_proj_q};
   else begin
     updated[131:122]=I_y;updated[121:104]=old[121:104]+18'd1;
     if(I_x<old[171:162])updated[171:162]=I_x;
     if(I_x>old[161:152])updated[161:152]=I_x;
     if(I_y<old[151:142])updated[151:142]=I_y;
     if(I_y>old[141:132])updated[141:132]=I_y;
     if(I_proj_u<old[103:92])updated[103:92]=I_proj_u;
     if(I_proj_u>old[91:80])updated[91:80]=I_proj_u;
     if(I_proj_v<old[79:68])updated[79:68]=I_proj_v;
     if(I_proj_v>old[67:56])updated[67:56]=I_proj_v;
     if(I_proj_p<old[55:42])updated[55:42]=I_proj_p;
     if(I_proj_p>old[41:28])updated[41:28]=I_proj_p;
     if(I_proj_q<old[27:14])updated[27:14]=I_proj_q;
     if(I_proj_q>old[13:0])updated[13:0]=I_proj_q;
   end
 end
 // Data is never used until its valid bit has been initialized. No bulk reset
 // of descriptor arrays; invalid candidates publish the same all-zero result.
 always @(posedge I_clk)if(I_rst_n && I_valid && |I_hit)begin
   if(target1)slot1[ch]<=updated;else slot0[ch]<=updated;
 end
 integer c;reg winner0;reg[171:0]w;reg[11:0]du,dv;reg[13:0]dp,dq;
 always @(posedge I_clk or negedge I_rst_n)begin
   if(!I_rst_n)begin v0<=0;v1<=0;emit_pending<=0;O_frame_done<=0;O_result<=0;end
   else begin
     O_frame_done<=emit_pending;emit_pending<=I_valid && I_eof;
     if(emit_pending)for(c=0;c<3;c=c+1)begin
       winner0=v0[c] && (!v1[c] || slot0[c][121:104]>=slot1[c][121:104]);
       w=winner0?slot0[c]:slot1[c];
       du=w[91:80]-w[103:92]+12'd5;dv=w[67:56]-w[79:68]+12'd5;
       dp=w[41:28]-w[55:42]+14'd22;dq=w[13:0]-w[27:14]+14'd13;
       O_result[c*111+:111]<=(v0[c]||v1[c])?
         {1'b1,w[171:132],w[121:104],du,dv,dp,dq}:111'd0;
     end
     if(I_valid)begin
       if(I_sof)begin v0<=I_hit;v1<=0;end
       else if(|I_hit)begin if(target1)v1[ch]<=1;else v0[ch]<=1;end
     end
   end
 end
endmodule

// 每色两个候选区域的流式选择器。
//
// 这是有限标签的轻量替代：不保存全帧标签图。每个命中组按相邻行及包围盒
// 横向连续性归入两个槽之一；两个分离色块因此不会再形成一个全局包围盒。
// 当同色区域超过两个时，保留当前较大槽并回收较小槽。EOF 后一拍输出面积最大的槽，
// 便于上层在寄存器边界继续进行尺寸、填充率和形状过滤。
module ua_blob_select2 #(
    parameter IMG_W_GRP = 320
)(
    input               I_clk,
    input               I_rst_n,
    input               I_valid,
    input               I_sof,
    input               I_eof,
    input               I_hit,
    input      [9:0]    I_x,
    input      [9:0]    I_y,
    input      [11:0]   I_proj_u,
    input      [11:0]   I_proj_v,
    input      [13:0]   I_proj_p,
    input      [13:0]   I_proj_q,
    output reg          O_frame_done,
    output reg          O_v,
    output reg  [9:0]   O_xmin,
    output reg  [9:0]   O_xmax,
    output reg  [9:0]   O_ymin,
    output reg  [9:0]   O_ymax,
    output reg  [17:0]  O_area,
    output reg  [11:0]  O_du, O_dv,
    output reg  [13:0]  O_dp, O_dq
);
    reg v0, v1;
    reg [9:0] xmin0, xmax0, ymin0, ymax0, last_y0;
    reg [9:0] xmin1, xmax1, ymin1, ymax1, last_y1;
    reg [17:0] area0, area1;
    reg [11:0] umin0, umax0, vmin0, vmax0;
    reg [11:0] umin1, umax1, vmin1, vmax1;
    reg [13:0] pmin0, pmax0, qmin0, qmax0;
    reg [13:0] pmin1, pmax1, qmin1, qmax1;
    reg emit_pending;

    // Select the winning descriptor BEFORE subtracting its extrema. Only one
    // slot is published at EOF, so two parallel span datapaths are redundant.
    // Keep the original tie rule and the same registered publication cycle.
    wire winner0 = v0 && (!v1 || area0 >= area1);
    wire [11:0] winner_umin = winner0 ? umin0 : umin1;
    wire [11:0] winner_umax = winner0 ? umax0 : umax1;
    wire [11:0] winner_vmin = winner0 ? vmin0 : vmin1;
    wire [11:0] winner_vmax = winner0 ? vmax0 : vmax1;
    wire [13:0] winner_pmin = winner0 ? pmin0 : pmin1;
    wire [13:0] winner_pmax = winner0 ? pmax0 : pmax1;
    wire [13:0] winner_qmin = winner0 ? qmin0 : qmin1;
    wire [13:0] winner_qmax = winner0 ? qmax0 : qmax1;

    // Shared projection inputs are derived from I_x/I_y in the parent color
    // detector. v/q retain their fixed bias so unsigned extrema remain valid.
    // 同一槽：当前行或紧邻下一行，且 x 与既有包围盒有接触（允许 1 组间隙）。
    // 11 位比较避免 xmax/last_y 位于最大值时 +1 回绕。
    wire match0 = I_valid && I_hit && !I_sof && v0 &&
                  ({1'b0,I_y} <= {1'b0,last_y0} + 11'd1) &&
                  (I_y >= ymin0) &&
                  ({1'b0,I_x} + 11'd1 >= {1'b0,xmin0}) &&
                  ({1'b0,I_x} <= {1'b0,xmax0} + 11'd1);
    wire match1 = I_valid && I_hit && !I_sof && v1 &&
                  ({1'b0,I_y} <= {1'b0,last_y1} + 11'd1) &&
                  (I_y >= ymin1) &&
                  ({1'b0,I_x} + 11'd1 >= {1'b0,xmin1}) &&
                  ({1'b0,I_x} <= {1'b0,xmax1} + 11'd1);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            v0 <= 1'b0; v1 <= 1'b0;
            xmin0 <= 0; xmax0 <= 0; ymin0 <= 0; ymax0 <= 0; last_y0 <= 0; area0 <= 0;
            xmin1 <= 0; xmax1 <= 0; ymin1 <= 0; ymax1 <= 0; last_y1 <= 0; area1 <= 0;
            umin0 <= 0; umax0 <= 0; vmin0 <= 0; vmax0 <= 0;
            umin1 <= 0; umax1 <= 0; vmin1 <= 0; vmax1 <= 0;
            pmin0 <= 0; pmax0 <= 0; qmin0 <= 0; qmax0 <= 0;
            pmin1 <= 0; pmax1 <= 0; qmin1 <= 0; qmax1 <= 0;
            emit_pending <= 1'b0;
            O_frame_done <= 1'b0; O_v <= 1'b0;
            O_xmin <= 0; O_xmax <= 0; O_ymin <= 0; O_ymax <= 0; O_area <= 0;
            O_du <= 0; O_dv <= 0; O_dp <= 0; O_dq <= 0;
        end else begin
            O_frame_done <= 1'b0;

            // EOF 的最后一个命中已在前一拍更新槽寄存器；现在输出已稳定的最佳槽。
            if (emit_pending) begin
                O_frame_done <= 1'b1;
                if (winner0) begin
                    O_v <= 1'b1;
                    O_xmin <= xmin0; O_xmax <= xmax0;
                    O_ymin <= ymin0; O_ymax <= ymax0; O_area <= area0;
                end else if (v1) begin
                    O_v <= 1'b1;
                    O_xmin <= xmin1; O_xmax <= xmax1;
                    O_ymin <= ymin1; O_ymax <= ymax1; O_area <= area1;
                end else begin
                    O_v <= 1'b0;
                    O_xmin <= 0; O_xmax <= 0; O_ymin <= 0; O_ymax <= 0; O_area <= 0;
                    O_du <= 0; O_dv <= 0; O_dp <= 0; O_dq <= 0;
                end
                if (winner0 || v1) begin
                    O_du <= winner_umax - winner_umin + 12'd5;
                    O_dv <= winner_vmax - winner_vmin + 12'd5;
                    O_dp <= winner_pmax - winner_pmin + 14'd22;
                    O_dq <= winner_qmax - winner_qmin + 14'd13;
                end
                emit_pending <= 1'b0;
            end

            if (I_valid) begin
                if (I_sof) begin
                    // 新帧从空槽开始，首组若命中则直接成为槽0的种子。
                    v0 <= I_hit; v1 <= 1'b0;
                    xmin0 <= I_x; xmax0 <= I_x; ymin0 <= I_y; ymax0 <= I_y; last_y0 <= I_y;
                    area0 <= I_hit ? 18'd1 : 18'd0;
                    umin0 <= I_proj_u; umax0 <= I_proj_u; vmin0 <= I_proj_v; vmax0 <= I_proj_v;
                    pmin0 <= I_proj_p; pmax0 <= I_proj_p; qmin0 <= I_proj_q; qmax0 <= I_proj_q;
                    xmin1 <= 0; xmax1 <= 0; ymin1 <= 0; ymax1 <= 0; last_y1 <= 0; area1 <= 0;
                    umin1 <= 0; umax1 <= 0; vmin1 <= 0; vmax1 <= 0;
                    pmin1 <= 0; pmax1 <= 0; qmin1 <= 0; qmax1 <= 0;
                    emit_pending <= I_eof;
                end else if (I_hit) begin
                    // 优先匹配已有槽；无匹配时分配空槽。两个槽都占用时回收
                    // 当前面积较小者，使帧首零散噪点不会永久挡住后续真实大目标。
                    if (match0) begin
                        area0 <= area0 + 18'd1;
                        last_y0 <= I_y;
                        if (I_x < xmin0) xmin0 <= I_x;
                        if (I_x > xmax0) xmax0 <= I_x;
                        if (I_y < ymin0) ymin0 <= I_y;
                        if (I_y > ymax0) ymax0 <= I_y;
                        if (I_proj_u < umin0) umin0 <= I_proj_u;
                        if (I_proj_u > umax0) umax0 <= I_proj_u;
                        if (I_proj_v < vmin0) vmin0 <= I_proj_v;
                        if (I_proj_v > vmax0) vmax0 <= I_proj_v;
                        if (I_proj_p < pmin0) pmin0 <= I_proj_p;
                        if (I_proj_p > pmax0) pmax0 <= I_proj_p;
                        if (I_proj_q < qmin0) qmin0 <= I_proj_q;
                        if (I_proj_q > qmax0) qmax0 <= I_proj_q;
                    end else if (match1) begin
                        area1 <= area1 + 18'd1;
                        last_y1 <= I_y;
                        if (I_x < xmin1) xmin1 <= I_x;
                        if (I_x > xmax1) xmax1 <= I_x;
                        if (I_y < ymin1) ymin1 <= I_y;
                        if (I_y > ymax1) ymax1 <= I_y;
                        if (I_proj_u < umin1) umin1 <= I_proj_u;
                        if (I_proj_u > umax1) umax1 <= I_proj_u;
                        if (I_proj_v < vmin1) vmin1 <= I_proj_v;
                        if (I_proj_v > vmax1) vmax1 <= I_proj_v;
                        if (I_proj_p < pmin1) pmin1 <= I_proj_p;
                        if (I_proj_p > pmax1) pmax1 <= I_proj_p;
                        if (I_proj_q < qmin1) qmin1 <= I_proj_q;
                        if (I_proj_q > qmax1) qmax1 <= I_proj_q;
                    end else if (!v0) begin
                        v0 <= 1'b1;
                        xmin0 <= I_x; xmax0 <= I_x; ymin0 <= I_y; ymax0 <= I_y; last_y0 <= I_y;
                        area0 <= 18'd1;
                        umin0 <= I_proj_u; umax0 <= I_proj_u; vmin0 <= I_proj_v; vmax0 <= I_proj_v;
                        pmin0 <= I_proj_p; pmax0 <= I_proj_p; qmin0 <= I_proj_q; qmax0 <= I_proj_q;
                    end else if (!v1) begin
                        v1 <= 1'b1;
                        xmin1 <= I_x; xmax1 <= I_x; ymin1 <= I_y; ymax1 <= I_y; last_y1 <= I_y;
                        area1 <= 18'd1;
                        umin1 <= I_proj_u; umax1 <= I_proj_u; vmin1 <= I_proj_v; vmax1 <= I_proj_v;
                        pmin1 <= I_proj_p; pmax1 <= I_proj_p; qmin1 <= I_proj_q; qmax1 <= I_proj_q;
                    end else if (area0 <= area1) begin
                        xmin0 <= I_x; xmax0 <= I_x; ymin0 <= I_y; ymax0 <= I_y; last_y0 <= I_y;
                        area0 <= 18'd1;
                        umin0 <= I_proj_u; umax0 <= I_proj_u; vmin0 <= I_proj_v; vmax0 <= I_proj_v;
                        pmin0 <= I_proj_p; pmax0 <= I_proj_p; qmin0 <= I_proj_q; qmax0 <= I_proj_q;
                    end else begin
                        xmin1 <= I_x; xmax1 <= I_x; ymin1 <= I_y; ymax1 <= I_y; last_y1 <= I_y;
                        area1 <= 18'd1;
                        umin1 <= I_proj_u; umax1 <= I_proj_u; vmin1 <= I_proj_v; vmax1 <= I_proj_v;
                        pmin1 <= I_proj_p; pmax1 <= I_proj_p; qmin1 <= I_proj_q; qmax1 <= I_proj_q;
                    end
                    if (I_eof) emit_pending <= 1'b1;
                end else if (I_eof) begin
                    emit_pending <= 1'b1;
                end
            end
        end
    end
endmodule


// Experimental raster-only blob storage. Not in the maintained source list.
// Two candidates per colour; cache geometry, RAM stores projection extrema.
module ua_blob_fouraxis_round2 #(parameter integer PROJECTION_SUPPORT=1,GAP_X=3)(
 input I_clk,I_rst_n,I_valid,I_sof,I_eof,input[2:0]I_hit,
 input[9:0]I_x,I_y,input[11:0]I_proj_u,I_proj_v,input[13:0]I_proj_p,I_proj_q,I_proj_r,I_proj_s,
 output reg O_frame_done,output[416:0]O_result
);
 wire projection_hit;
 generate if(PROJECTION_SUPPORT)begin:gen_projection_rows
  reg[9:0]row_min[0:2],row_max[0:2],p1_min[0:2],p1_max[0:2],p2_min[0:2],p2_max[0:2];
  reg[2:0]row_v,p1_v,p2_v;reg[9:0]row_y;integer ch;
  reg[9:0]p3_min[0:2],p3_max[0:2];reg[2:0]p3_v;
  reg[9:0]p4_min[0:2],p4_max[0:2];reg[2:0]p4_v;
  reg[2:0]hist[0:2];integer hi;
  wire new_row=I_y!=row_y;
  wire[2:0]v1=new_row?row_v:p1_v,v2=new_row?p1_v:p2_v;
  wire[2:0]v3=new_row?p2_v:p3_v;
  wire[2:0]v4=new_row?p3_v:p4_v;
  wire[2:0]supported;
  wire x_zero=(I_x==10'd0);
  wire[9:0]x_minus_one=I_x-10'd1;
  for(genvar c=0;c<3;c=c+1)begin:gen_support
   wire[9:0]a=new_row?row_min[c]:p1_min[c],b=new_row?row_max[c]:p1_max[c];
   wire[9:0]d=new_row?p1_min[c]:p2_min[c],e=new_row?p1_max[c]:p2_max[c];
   wire[9:0]lo3=new_row?p2_min[c]:p3_min[c],hi3=new_row?p2_max[c]:p3_max[c];
   wire[9:0]lo4=new_row?p3_min[c]:p4_min[c],hi4=new_row?p3_max[c]:p4_max[c];
   assign supported[c]=!I_sof && v1[c] && v2[c] &&
    ({1'b0,I_x}+11'd1>={1'b0,a}) && (x_zero || x_minus_one<=b) &&
    ({1'b0,I_x}+11'd1>={1'b0,d}) && (x_zero || x_minus_one<=e) && v3[c] && ({1'b0,I_x}+11'd1>={1'b0,lo3}) && (x_zero || x_minus_one<=hi3) && v4[c] && ({1'b0,I_x}+11'd1>={1'b0,lo4}) && (x_zero || x_minus_one<=hi4);
  end
  wire[2:0]local_solid=(!new_row && !I_sof)?(I_hit&hist[0]&hist[1]&hist[2]):3'd0;
  assign projection_hit=|(supported&local_solid);
  // Payload is observed only under row-valid tags; no reset fanout to spans.
  always @(posedge I_clk)if(I_rst_n && I_valid)begin
   for(ch=0;ch<3;ch=ch+1)begin
    if(I_sof || new_row)begin
     p2_min[ch]<=p1_min[ch];p2_max[ch]<=p1_max[ch];p1_min[ch]<=row_min[ch];p1_max[ch]<=row_max[ch];
     p3_min[ch]<=p2_min[ch];p3_max[ch]<=p2_max[ch];
     p4_min[ch]<=p3_min[ch];p4_max[ch]<=p3_max[ch];
     row_min[ch]<=I_x;row_max[ch]<=I_x;
    end else if(local_solid[ch])begin
     if(!row_v[ch])row_min[ch]<=I_x;
     row_max[ch]<=I_x;
    end
   end
  end
  always @(posedge I_clk or negedge I_rst_n)begin
   if(!I_rst_n)begin hist[0]<=0;hist[1]<=0;hist[2]<=0;row_v<=0;p1_v<=0;p2_v<=0;p3_v<=0;p4_v<=0;row_y<=0;end
   else if(I_valid)begin
    if(I_sof || new_row)begin hist[2]<=0;hist[1]<=0;end
    else for(hi=2;hi>0;hi=hi-1)hist[hi]<=hist[hi-1];
    hist[0]<=I_hit;
    row_y<=I_y;
    if(I_sof)begin row_v<=0;p1_v<=0;p2_v<=0;p3_v<=0;p4_v<=0;end
    else if(new_row)begin row_v<=0;p1_v<=row_v;p2_v<=p1_v;p3_v<=p2_v;p4_v<=p3_v;end
    else row_v<=row_v|local_solid;
   end
  end
 end else begin:gen_raw_projection
  assign projection_hit=1'b1;
 end endgenerate

 // Metadata: xmin, xmax, ymin, last_y=ymax, area. Raster y is monotone.
 reg[57:0]metadata[0:5];reg[2:0]v0,v1;
 wire[1:0]ch_in=I_hit[0]?2'd0:I_hit[1]?2'd1:2'd2;
 wire[57:0]m0=metadata[{ch_in,1'b0}],m1=metadata[{ch_in,1'b1}];
 wire valid0=!I_sof && v0[ch_in],valid1=!I_sof && v1[ch_in];
 wire match0=valid0 && {1'b0,I_y}<={1'b0,m0[27:18]}+11'd2 && I_y>=m0[37:28] &&
  {1'b0,I_x}+GAP_X>={1'b0,m0[57:48]} && {1'b0,I_x}<={1'b0,m0[47:38]}+GAP_X;
 wire match1=valid1 && {1'b0,I_y}<={1'b0,m1[27:18]}+11'd2 && I_y>=m1[37:28] &&
  {1'b0,I_x}+GAP_X>={1'b0,m1[57:48]} && {1'b0,I_x}<={1'b0,m1[47:38]}+GAP_X;
 // On an exact area tie preserve slot zero, rather than evicting the winner.
 wire target1=match0?1'b0:match1?1'b1:!valid0?1'b0:!valid1?1'b1:
  (m0[17:0]<m1[17:0])?1'b0:1'b1;
 wire replace_slot=I_sof || (!match0 && !match1);
 wire[2:0]address_in={ch_in,target1};
 wire[57:0]old_meta=target1?m1:m0;
 reg[57:0]new_meta;
 always @*begin
  new_meta=old_meta;
  if(replace_slot)new_meta={I_x,I_x,I_y,I_y,18'd1};
  else begin
   if(I_x<old_meta[57:48])new_meta[57:48]=I_x;
   if(I_x>old_meta[47:38])new_meta[47:38]=I_x;
   new_meta[27:18]=I_y;new_meta[17:0]=old_meta[17:0]+18'd1;
  end
 end
 wire other_valid=target1?valid0:valid1;
 wire[17:0]other_area=target1?m0[17:0]:m1[17:0];
 wire winner_in=!other_valid || new_meta[17:0]>other_area ||
  (new_meta[17:0]==other_area && !target1);
 always @(posedge I_clk)if(I_rst_n && I_valid && |I_hit)metadata[address_in]<=new_meta;
 always @(posedge I_clk or negedge I_rst_n)begin
  if(!I_rst_n)begin v0<=0;v1<=0;end
  else if(I_valid)begin
   if(I_sof)begin v0<=I_hit;v1<=0;end
   else if(|I_hit)begin if(target1)v1[ch_in]<=1;else v0[ch_in]<=1;end
  end
 end
 /* fehdl force_ram=1, ram_style="bram" */ reg[159:0]projections[0:5];
 reg[159:0]read_value,forward_value;
 reg p_valid,p_hit,p_sof,p_eof,p_replace,p_projection,p_winner;
 reg[2:0]p_address,forward_address;reg forward_valid;
 reg[57:0]p_meta;reg[11:0]pu,pv;reg[13:0]pp,pq,pr,ps;
 wire write_descriptor=p_valid && p_hit;
 wire[159:0]old=(forward_valid && forward_address==p_address)?forward_value:read_value;
 reg[159:0]updated;
 always @*begin
  updated=old;
  if(p_replace)updated={
   (p_projection?pr:14'h3fff),(p_projection?pr:14'd0),
   (p_projection?ps:14'h3fff),(p_projection?ps:14'd0),
   (p_projection?pu:12'hfff),(p_projection?pu:12'd0),
   (p_projection?pv:12'hfff),(p_projection?pv:12'd0),
   (p_projection?pp:14'h3fff),(p_projection?pp:14'd0),
   (p_projection?pq:14'h3fff),(p_projection?pq:14'd0)};
  else if(p_projection)begin
   if(pr<old[159:146])updated[159:146]=pr;if(pr>old[145:132])updated[145:132]=pr;
   if(ps<old[131:118])updated[131:118]=ps;if(ps>old[117:104])updated[117:104]=ps;
   if(pu<old[103:92])updated[103:92]=pu;if(pu>old[91:80])updated[91:80]=pu;
   if(pv<old[79:68])updated[79:68]=pv;if(pv>old[67:56])updated[67:56]=pv;
   if(pp<old[55:42])updated[55:42]=pp;if(pp>old[41:28])updated[41:28]=pp;
   if(pq<old[27:14])updated[27:14]=pq;if(pq>old[13:0])updated[13:0]=pq;
  end
 end
 always @(posedge I_clk)if(I_rst_n)begin
  if(I_valid && !(write_descriptor && p_address==address_in))read_value<=projections[address_in];
  if(write_descriptor)begin projections[p_address]<=updated;forward_value<=updated;end
  if(I_valid)begin p_meta<=new_meta;pu<=I_proj_u;pv<=I_proj_v;pp<=I_proj_p;pq<=I_proj_q;pr<=I_proj_r;ps<=I_proj_s;end
 end
 wire no_projection=PROJECTION_SUPPORT && updated[91:80]<updated[103:92];
 wire[11:0]fallback_w=({2'd0,p_meta[47:38]}-{2'd0,p_meta[57:48]}+12'd1)<<2;
 wire[11:0]fallback_h={2'd0,p_meta[27:18]}-{2'd0,p_meta[37:28]}+12'd1;
 wire[11:0]fallback_diag=fallback_w+fallback_h;
 wire[13:0]fallback_p=({2'd0,fallback_w}<<2)+{2'd0,fallback_w}+({2'd0,fallback_h}<<1);
 wire[13:0]fallback_q=({2'd0,fallback_w}<<1)+({2'd0,fallback_h}<<2)+{2'd0,fallback_h};
 wire[138:0]packet={
  (no_projection?fallback_q:(updated[145:132]-updated[159:146]+(PROJECTION_SUPPORT?14'd52:14'd13))),
  (no_projection?fallback_p:(updated[117:104]-updated[131:118]+(PROJECTION_SUPPORT?14'd88:14'd22))),1'b1,p_meta[57:28],p_meta[27:18],p_meta[17:0],
  (no_projection?fallback_diag:(updated[91:80]-updated[103:92]+(PROJECTION_SUPPORT?12'd17:12'd5))),
  (no_projection?fallback_diag:(updated[67:56]-updated[79:68]+(PROJECTION_SUPPORT?12'd17:12'd5))),
  (no_projection?fallback_p:(updated[41:28]-updated[55:42]+(PROJECTION_SUPPORT?14'd82:14'd22))),
  (no_projection?fallback_q:(updated[13:0]-updated[27:14]+(PROJECTION_SUPPORT?14'd37:14'd13)))};
 reg[138:0]summary;reg[1:0]summary_ch;reg summary_valid;
 reg[138:0]winner_cache[0:2];reg[2:0]winner_valid,end_delay;
 genvar colour;
 generate for(colour=0;colour<3;colour=colour+1)begin:gen_result
  assign O_result[colour*139+:139]=winner_valid[colour]?winner_cache[colour]:139'd0;
 end endgenerate
 always @(posedge I_clk)if(I_rst_n)begin
  if(write_descriptor && p_winner)summary<=packet;
  if(summary_valid)winner_cache[summary_ch]<=summary;
 end
 always @(posedge I_clk or negedge I_rst_n)begin
  if(!I_rst_n)begin
   p_valid<=0;p_hit<=0;p_sof<=0;p_eof<=0;p_replace<=0;p_projection<=0;p_winner<=0;p_address<=0;
   forward_valid<=0;forward_address<=0;summary_valid<=0;summary_ch<=0;
   winner_valid<=0;end_delay<=0;O_frame_done<=0;
  end else begin
   p_valid<=I_valid;
   if(I_valid)begin
    p_hit<=|I_hit;p_sof<=I_sof;p_eof<=I_eof;p_replace<=replace_slot;
    p_projection<=projection_hit;p_winner<=winner_in;p_address<=address_in;
   end
   forward_valid<=write_descriptor;if(write_descriptor)forward_address<=p_address;
   summary_valid<=write_descriptor && p_winner;summary_ch<=p_address[2:1];
   if(p_valid && p_sof)winner_valid<=0;
   else if(summary_valid)winner_valid[summary_ch]<=1;
   end_delay<={end_delay[1:0],p_valid && p_eof};O_frame_done<=end_delay[2];
  end
 end
endmodule
