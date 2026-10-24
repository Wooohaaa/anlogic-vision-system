// ua_motion_detect.v — 进阶④: 帧差法运动目标检测 (旁路统计, 输出直通)
//
// 原理: 帧差法 — 当前帧灰度与上一帧同位置比较, |差| > 阈值 → 运动像素
// 域: 组均值灰度域 (x/4 降采样, 4 像素/拍 → 1 组值/拍)。参考帧可再隔行
// 采样以节省 ERAM；还可只保存手势 ROI 内的组。视频数据始终逐拍完整直通，
// 不降低显示分辨率；ROI 只影响运动统计和背景 RAM 地址映射。
// 计数器结构对齐 ua_user_algo_96 (x_grp 递增在 tuser 条件外)
// RAM 时序: 用 PH1P_LOGIC_ERAM 原语 (SDP 模式), 写地址/数据各延迟 1 拍
//   写 A 口: 上一拍的地址+数据 (write-behind), 读 B 口: 当前地址 (上一帧值)
//   FILL_ALL="ZERO" 免复位清零
// 阅读入口：先看 RAM_DEPTH/ADDR_W，再看 ERAM 的 A 写/B 读连接，最后看
// 帧末如何锁存 O_motion_count。首帧只建立参考，不能当作检测结果。
`timescale 1ns/1ps
module ua_motion_detect #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    parameter IMG_W_GRP  = (IMG_WIDTH / 4), // x 组数 = IMG_WIDTH/4
    parameter IMG_H_GRP  = IMG_HEIGHT,   // y 行数 (默认跟随 IMG_HEIGHT)
    parameter Y_DOWNSAMPLE = 1,          // 参考帧垂直采样率: 1/2/4 行采样
    parameter THRESHOLD  = 8'd24,
    // 暗光时同一物体与背景的灰度差会整体收缩。仅当当前值和参考值都
    // 低于 LOW_LIGHT_LEVEL 时改用较低阈值；默认 LEVEL=0 完全保持旧行为。
    parameter [7:0] LOW_LIGHT_LEVEL = 8'd0,
    parameter [7:0] LOW_LIGHT_THRESHOLD = THRESHOLD,
    // 运动参考帧的可选组域 ROI。默认关闭时仍保存整幅参考帧，便于
    // 独立仿真与历史调用保持原有行为；主工程将其对齐到手势 ROI。
    parameter integer ROI_ENABLE = 0,
    parameter integer ROI_X0_GRP = 0,
    parameter integer ROI_X1_GRP = IMG_W_GRP - 1,
    parameter integer ROI_Y0 = 0,
    parameter integer ROI_Y1 = IMG_H_GRP - 1,
    // 0: 传统相邻帧差，每帧覆盖参考；1: 运动位置暂不更新参考，形成
    // 选择性背景模型。后者适合手势识别，手停住后轮廓仍保持为前景。
    parameter integer HOLD_BACKGROUND_ON_MOTION = 0,
    // Exact-depth inferred storage avoids unused depth in the legacy macro.
    // The legacy branch remains available for cycle-by-cycle equivalence.
    parameter integer COMPACT_REFERENCE_RAM = 1
)(
    input               I_clk,
    input               I_rst_n,
    input               I_tlast,
    input               I_tuser,
    input      [95:0]   I_tdata,
    input               I_tvalid,
    input               I_tready,
    // 请求在下一帧重新建立背景。请求可在帧内任意时刻到来，模块会先锁存，
    // 等到下一个 tuser 帧首再整帧采集；采集期间运动结果被屏蔽。
    input               I_background_restart,
    output reg          O_tlast,
    output reg          O_tuser,
    output reg  [95:0]  O_tdata,
    output reg          O_tvalid,
    output              O_tready,
    // 与 O_tdata/O_tvalid 同拍的组级帧差结果。手势旁路复用该结果，把静态
    // 暖色墙面、衣物等从肤色候选中排除；Y_DOWNSAMPLE=2 时仅采样行有效。
    output              O_motion_sample_valid,
    // 手势专用的无背景门控采样/帧结束标记。帧差统计仍使用上面的门控输出，
    // 手势则可在摄像头启动后直接观察首帧及静止手势，不依赖首帧背景模板。
    output              O_hand_sample_valid,
    output              O_hand_frame_done,
    output              O_motion_hit,
    output reg [9:0]     O_motion_x_grp,
    output reg [9:0]     O_motion_y,
    output reg          O_motion_valid,
    output reg  [15:0]  O_motion_count
);
    assign O_tready = I_tready;

    // ---- 像素拆包 → 灰度 → 组均值 (与 ua_user_algo_96 同域同算法) ----
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

    wire [9:0] grp_sum = {2'b00, gray0} + {2'b00, gray1} + {2'b00, gray2} + {2'b00, gray3};
    wire [7:0] grp_gray = grp_sum[9:2];

    // SOF describes the CURRENT beat, not the previous counter position.
    // A camera can already be streaming when reset is released. Prioritizing
    // SOF both here and in the next-state logic recovers a partial first frame.
    reg [9:0] x_next;
    reg [9:0] y_next;
    wire [9:0] x_grp = I_tuser ? 10'd0 : x_next;
    wire [9:0] y_pos = I_tuser ? 10'd0 : y_next;
    // (修复#33) TD 要求 ERAM ADDR_WIDTH = ceil(log2(DATA_DEPTH)) 严格匹配:
    //   #28 隔行后 RAM_DEPTH 153600→76800, 原固定 ADDR_W=18 → "Addr width mismatch"。
    //   改为随 RAM_DEPTH 动态取对数, 改深度不需再手工改位宽。
    function integer clog2(input integer d);
        integer i;
        begin
            clog2 = 0;
            for (i = d - 1; i > 0; i = i >> 1) clog2 = clog2 + 1;
        end
    endfunction
    // 关闭 ROI 时退化为完整画面；打开 ROI 后地址原点移到 ROI 左上角。
    // 根据实际抽取相位求 ROI 内首/末采样行，避免
    // ROI 边界恰好落在未采样行时少算一行或提前结束背景采集。
    localparam integer ROI_X0_I = (ROI_ENABLE != 0) ? ROI_X0_GRP : 0;
    localparam integer ROI_X1_I = (ROI_ENABLE != 0) ? ROI_X1_GRP : (IMG_W_GRP - 1);
    localparam integer ROI_Y0_I = (ROI_ENABLE != 0) ? ROI_Y0 : 0;
    localparam integer ROI_Y1_I = (ROI_ENABLE != 0) ? ROI_Y1 : (IMG_H_GRP - 1);
    localparam integer SAMPLE_PHASE = (IMG_H_GRP - 1) % Y_DOWNSAMPLE;
    localparam integer ROI_SAMPLE_FIRST_Y = ROI_Y0_I +
        ((SAMPLE_PHASE + Y_DOWNSAMPLE - (ROI_Y0_I % Y_DOWNSAMPLE)) % Y_DOWNSAMPLE);
    localparam integer ROI_SAMPLE_LAST_Y = ROI_Y1_I -
        ((ROI_Y1_I + Y_DOWNSAMPLE - SAMPLE_PHASE) % Y_DOWNSAMPLE);
    localparam integer ROI_GRP_WIDTH = (ROI_X1_I >= ROI_X0_I) ?
                                       (ROI_X1_I - ROI_X0_I + 1) : 1;
    localparam integer SAMPLE_HEIGHT = (ROI_SAMPLE_LAST_Y >= ROI_SAMPLE_FIRST_Y) ?
        ((ROI_SAMPLE_LAST_Y - ROI_SAMPLE_FIRST_Y) / Y_DOWNSAMPLE + 1) : 1;
    localparam integer RAM_DEPTH = ROI_GRP_WIDTH * SAMPLE_HEIGHT;
    localparam ADDR_W = clog2(RAM_DEPTH);

    // 总是选中最后一行，保证帧末样本能触发统计锁存。
    wire sample_row = (Y_DOWNSAMPLE == 1) ? 1'b1 :
                      (Y_DOWNSAMPLE == 2) ? (y_pos[0] == SAMPLE_PHASE) :
                      (y_pos[1:0] == SAMPLE_PHASE);
    wire roi_x_active = (x_grp >= ROI_X0_I) && (x_grp <= ROI_X1_I);
    wire roi_y_active = (y_pos >= ROI_Y0_I) && (y_pos <= ROI_Y1_I);
    wire sample_accept = I_tvalid && sample_row && roi_x_active && roi_y_active;
    wire [9:0] sample_y_abs = y_pos / Y_DOWNSAMPLE;
    localparam integer ROI_SAMPLE_Y0_INDEX = ROI_SAMPLE_FIRST_Y / Y_DOWNSAMPLE;
    wire [9:0] sample_y = sample_y_abs - ROI_SAMPLE_Y0_INDEX;
    wire [9:0] sample_x = x_grp - ROI_X0_I;
    wire [ADDR_W-1:0] ref_addr = sample_y * ROI_GRP_WIDTH + sample_x;

    // ---- 写地址/写数据各延迟 1 拍: 写发生在读之后一拍 ----
    reg [ADDR_W-1:0] ref_addr_d1;
    reg [7:0]  grp_gray_d1;
    reg        sample_valid_d1;
    reg        sample_start_d1;
    reg        sample_end_d1;
    reg        frame_end_d1;
    reg        hand_frame_done_d1;

    assign O_hand_sample_valid = sample_valid_d1;
    // 再延迟一拍，确保最后一个有效像素组已被手势模块累计后再结束该帧。
    assign O_hand_frame_done = hand_frame_done_d1;

    // ---- PH1P_LOGIC_ERAM 原语: DP 模式 (A口写, B口读) ----
    //  (修复) MODE 合法值 = "DP"/"SP"/"PDPW"/"FIFO" (官方模型注释), 无 "SDP";
    //   官方 awb/demosaic RAM 的 A写B读 均用 DP。
    //  (修复#20) FILL_ALL 合法值 = "NONE" 或二进制串 (官方模型注释), "ZERO" 非法;
    //   参考帧无需初始化: 帧0/1 只做写+建参考, 计数从帧2 起 (读到的必是已写地址)
    wire [7:0] eram_dout;
    wire       ref_write_en;
    generate if(COMPACT_REFERENCE_RAM!=0)begin:gen_compact_reference
    ua_motion_ref_ram #(.DEPTH(RAM_DEPTH),.ADDR_W(ADDR_W)) u_compact_ref(
        .I_clk(I_clk),.I_write(sample_valid_d1 && ref_write_en),.I_read(sample_accept),
        .I_write_addr(ref_addr_d1),.I_read_addr(ref_addr),.I_data(grp_gray_d1),.O_data(eram_dout)
    );
    end else begin:gen_legacy_reference
    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A (8), .DATA_WIDTH_B (8),
        .ADDR_WIDTH_A (ADDR_W), .ADDR_WIDTH_B (ADDR_W),
        .DATA_DEPTH_A (RAM_DEPTH), .DATA_DEPTH_B (RAM_DEPTH),
        .MODE         ("DP"),
        .REGMODE_A    ("NOREG"), .REGMODE_B    ("NOREG"),
        .WRITEMODE_A  ("NORMAL"), .WRITEMODE_B ("NORMAL"),
        .CLKMODE      ("ASYNC"),
        .IMPLEMENT    ("20K(FAST)"),
        .FILL_ALL     ("NONE"),
        .ECC_ENCODE   ("DISABLE"), .ECC_DECODE ("DISABLE")
    ) u_eram_ref (
        // A 口承载的是延迟一拍的地址/数据，写使能也必须使用同一拍的
        // sample_valid_d1。否则有效拍后的 blank 会吞掉该样本，尤其是帧末组。
        .clka (I_clk), .cea (sample_valid_d1), .wea (ref_write_en),
        .addra(ref_addr_d1), .dia (grp_gray_d1),
        .doa (), .bea (1'b0), .rsta (1'b0), .ocea (1'b0),
        .clkb (I_clk), .ceb (sample_accept), .web (1'b0),
        .addrb(ref_addr), .dib (8'd0),
        .dob (eram_dout),
        .beb (1'b0), .rstb (1'b0), .oceb (1'b0),
        .ecc_sbiterr (), .ecc_dbiterr (),
        .ecc_sbiterrinj (1'b0), .ecc_dbiterrinj (1'b0)
    );
    end endgenerate


    reg       have_ref;
    reg       bg_restart_pending;
    reg       bg_capture_active;
    // 首帧（复位后）或显式重启后的下一帧都作为新的参考背景。
    wire      start_background_frame = I_tvalid && I_tuser &&
                                       (I_background_restart ||
                                        bg_restart_pending || !have_ref);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            have_ref   <= 1'b0;
            bg_restart_pending <= 1'b0;
            bg_capture_active  <= 1'b0;
            ref_addr_d1 <= 0;
            grp_gray_d1 <= 8'd0;
            sample_valid_d1 <= 1'b0;
            O_motion_x_grp <= 10'd0;
            O_motion_y <= 10'd0;
            sample_start_d1 <= 1'b0;
            sample_end_d1 <= 1'b0;
            frame_end_d1 <= 1'b0;
            hand_frame_done_d1 <= 1'b0;
        end else begin
            // 模式切换产生的脉冲可能落在当前帧中间，必须保持到下一帧帧首。
            if (I_background_restart)
                bg_restart_pending <= 1'b1;
            if (start_background_frame) begin
                bg_restart_pending <= 1'b0;
                bg_capture_active  <= 1'b1;
                have_ref           <= 1'b0;
            end
            // sample_end_d1 对应延迟一拍后的最后一个采样组；该拍已经写入
            // 新背景，随后解除采集门控，下一帧即可开始检测。
            if (bg_capture_active && sample_end_d1) begin
                bg_capture_active <= 1'b0;
                have_ref          <= 1'b1;
            end
            sample_valid_d1 <= sample_accept;
            if (sample_accept) begin
                O_motion_x_grp <= x_grp;
                O_motion_y <= y_pos;
            end
            sample_start_d1 <= sample_accept &&
                               (x_grp == ROI_X0_I) &&
                               (sample_y == 0);
            sample_end_d1 <= sample_accept &&
                              (x_grp == ROI_X1_I) &&
                              (y_pos == ROI_SAMPLE_LAST_Y);
            // 对外 O_motion_valid 仍保持帧末语义；ROI 末样本只负责完成
            // 背景写入和锁存计数，避免改变下游 OSD/手势的帧边界时序。
            frame_end_d1 <= I_tvalid &&
                            (x_grp == IMG_W_GRP - 1) &&
                            (y_pos == IMG_H_GRP - 1);
            hand_frame_done_d1 <= frame_end_d1;
            if (sample_accept) begin
                ref_addr_d1 <= ref_addr;
                grp_gray_d1 <= grp_gray;
                // 没有帧首的非法/片段流仍保留旧的“首个有效样本建参考”兜底，
                // 但正常首帧由 sample_end_d1 统一标记为完整背景。
                if (!have_ref && !bg_capture_active && !start_background_frame)
                    have_ref <= 1'b1;
            end
        end
    end

    // 帧计数: 第1帧建参考，从第2帧开始输出帧差计数。
    reg [7:0] frame_n;
    wire      frame_n_valid = (frame_n >= 8'd2) &&
                              !bg_capture_active && !bg_restart_pending &&
                              !start_background_frame;

    // ---- 帧差比较 (grp_gray_d1 与 eram_dout 同地址同拍: ERAM 同步读 1 拍延迟,
    //  dob(k)=mem[addr(k-1)] 为上一帧参考值, grp_gray_d1(k)=gray(k-1) 为当前帧值) ----
    wire [8:0] diff = (grp_gray_d1 > eram_dout) ? (grp_gray_d1 - eram_dout) : (eram_dout - grp_gray_d1);
    wire       low_light_pair = (LOW_LIGHT_LEVEL != 0) &&
                                (grp_gray_d1 < LOW_LIGHT_LEVEL) &&
                                (eram_dout < LOW_LIGHT_LEVEL);
    wire [7:0] motion_threshold = low_light_pair ?
                                  LOW_LIGHT_THRESHOLD : THRESHOLD;
    wire       is_motion = (diff > motion_threshold) && have_ref && frame_n_valid;
    // 第一参考帧必须完整写入。进入检测阶段后，持久模式只吸收稳定背景，
    // 不让刚出现的目标在下一帧被“学进背景”。
    assign ref_write_en = sample_valid_d1 &&
                          (bg_capture_active ||
                           (HOLD_BACKGROUND_ON_MOTION == 0) ||
                           !frame_n_valid || !is_motion);
    assign O_motion_sample_valid = sample_valid_d1 && frame_n_valid;
    assign O_motion_hit = O_motion_sample_valid && is_motion;

    reg  [17:0] motion_cnt;
    reg  [17:0] motion_cnt_r;
    reg         motion_valid_r;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tlast <= 1'b0;
            O_tuser <= 1'b0;
            O_tdata <= 96'd0;
            O_tvalid <= 1'b0;
            x_next <= 10'd0;
            y_next <= 10'd0;
            motion_cnt <= 18'd0;
            motion_cnt_r <= 16'd0;
            motion_valid_r <= 1'b0;
            frame_n <= 8'd0;
        end else begin
            O_tlast  <= I_tlast;
            O_tuser  <= I_tuser;
            O_tvalid <= I_tvalid;
            O_tdata  <= I_tdata;

            if (I_tvalid) begin
                if (I_tuser) begin
                    // 新背景帧从编号 1 重新开始，下一帧编号 2 才恢复检测。
                    if (start_background_frame)
                        frame_n <= 8'd1;
                    else if(frame_n < 8'd2)
                        frame_n <= frame_n + 8'd1;
                end

                if (x_grp == IMG_W_GRP - 1) begin
                    x_next <= 10'd0;
                    if (y_pos == IMG_H_GRP - 1) begin
                        y_next <= 10'd0;
                    end else begin
                        y_next <= y_pos + 1'b1;
                    end
                end else begin
                    x_next <= x_grp + 1'b1;
                    y_next <= y_pos;
                end
            end

            // ERAM 的读数据比输入晚一拍，因此统计、清零和帧末锁存都使用
            // 同步延迟后的边界标志。这样最后一组不会落到下一帧后被丢弃。
            motion_valid_r <= 1'b0;
            if (sample_valid_d1) begin
                if (sample_start_d1)
                    motion_cnt <= is_motion ? 18'd1 : 18'd0;
                else if (is_motion)
                    motion_cnt <= motion_cnt + 18'd1;

                if (sample_end_d1 && frame_n_valid) begin
                    motion_cnt_r <= motion_cnt + (is_motion ? 18'd1 : 18'd0);
                end
            end
            if (frame_end_d1)
                motion_valid_r <= frame_n_valid;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_motion_count <= 16'd0;
            O_motion_valid <= 1'b0;
        end else begin
            O_motion_count <= (motion_cnt_r > 18'hFFFF) ? 16'hFFFF : motion_cnt_r[15:0];
            O_motion_valid <= motion_valid_r;
        end
    end
endmodule
