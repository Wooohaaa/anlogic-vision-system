// ============================================================================
// ua_digit_recognizer : 固定区域的轻量数字识别器
//
// 输入为 AWB 后的 96-bit RGB888 流，每拍 4 个像素；tuser 是帧首，tlast
// 是行尾。模块只观察视频，不参与 ready/数据通路，因此不会改变 HDMI 图像。
//
// 算法约束（有意保持为可综合、可解释的竞赛演示版本）：
//   1. 外框 336x448，内框 280x392，内框划分为 5x7 个 56x56 单元；
//   2. 外框四角各采样 16x16 点估计白底亮度，当前帧用 bg-offset 做分割；
//   3. 每个单元每 4 行采样一次，统计 784 个采样点中的深色像素数；
//   4. 形成 35-bit 占用图，逐位与 0..9 模板比较；
//   5. 最佳/次佳距离形成置信度，连续三帧相同才发布 valid 脉冲。
//
// 该模块适用于固定位置的黑字白卡数字识别，不是自然场景 OCR，也不使用
// ERAM、DSP、除法器或乘法器。参数允许独立验证时缩小 ROI；实际 720p 默认值
// 与 design_top_user 的 1280x720 坐标对齐。
// ============================================================================
`timescale 1ns/1ps

module ua_digit_snapshot_reference #(
    parameter integer IMG_WIDTH   = 1280,
    parameter integer IMG_HEIGHT  = 720,
    parameter integer OUTER_X0    = 472,
    parameter integer OUTER_Y0    = 136,
    parameter integer OUTER_W     = 336,
    parameter integer OUTER_H     = 448,
    parameter integer INNER_X0    = 500,
    parameter integer INNER_Y0    = 164,
    parameter integer INNER_W     = 280,
    parameter integer INNER_H     = 392,
    parameter integer CELL_W      = 56,
    parameter integer CELL_H      = 56,
    parameter integer CELL_GRP_LOG2 = 4,
    parameter integer CELL_H_LOG2   = 6,
    // Numeric cell dimensions support non-power-of-two scaling while retaining
    // the legacy log2 parameters for older standalone testbench instantiations.
    parameter integer CELL_GROUPS_PER_CELL = (CELL_W / 4),
    parameter integer CELL_HEIGHT = CELL_H,
    parameter integer BG_OFFSET   = 32,
    parameter integer CELL_MIN    = 32,
    parameter integer MIN_MARGIN  = 2
)(
    input               I_clk,
    input               I_rst_n,
    input               I_tlast,
    input               I_tuser,
    input      [95:0]   I_tdata,
    input               I_tvalid,
    output reg          O_digit_valid,
    output reg  [3:0]   O_digit_id,
    output reg  [7:0]   O_digit_confidence
);

    localparam integer GRID_COLS = 5;
    localparam integer GRID_ROWS = 7;
    localparam integer GRID_CELLS = GRID_COLS * GRID_ROWS;
    localparam integer IMG_W_GRP = IMG_WIDTH / 4;
    localparam integer X0_GRP = INNER_X0 / 4;
    localparam integer OUTER_X0_GRP = OUTER_X0 / 4;
    localparam integer OUTER_X1_GRP = (OUTER_X0 + OUTER_W - 1) / 4;
    localparam integer CORNER_SIZE = 16;
    localparam integer CORNER_GROUPS = CORNER_SIZE / 4;

    // 四像素拆包与现有 ua_user_algo_96/ua_track_detect 保持相同的顺序。
    wire [23:0] pix0 = I_tdata[95:72];
    wire [23:0] pix1 = I_tdata[71:48];
    wire [23:0] pix2 = I_tdata[47:24];
    wire [23:0] pix3 = I_tdata[23:0];

    function [7:0] F_luma;
        input [23:0] p;
        reg [9:0] sum;
        begin
            sum = {2'b00,p[23:16]} + {1'b0,p[15:8],1'b0} + {2'b00,p[7:0]};
            F_luma = sum[9:2];
        end
    endfunction

    wire [7:0] y0 = F_luma(pix0);
    wire [7:0] y1 = F_luma(pix1);
    wire [7:0] y2 = F_luma(pix2);
    wire [7:0] y3 = F_luma(pix3);

    reg [9:0] x_grp;
    reg [9:0] y_pos;
    wire [9:0] cur_x_grp = I_tuser ? 10'd0 : x_grp;
    wire [9:0] cur_y     = I_tuser ? 10'd0 : y_pos;

    reg [7:0] bg_luma;
    reg       bg_ready;
    wire [8:0] threshold_ext = (bg_luma > BG_OFFSET) ?
                               {1'b0,bg_luma} - BG_OFFSET : 9'd0;
    wire [7:0] threshold = threshold_ext[7:0];

    wire [2:0] black_sum =
        (y0 < threshold) + (y1 < threshold) +
        (y2 < threshold) + (y3 < threshold);

    // 外框四角各采样 16x16 区域、每四行取一行，总计 256 个样本；
    // 帧尾右移 8 位得到平均值，综合时不出现除法器。
    wire corner_x = ((cur_x_grp >= OUTER_X0_GRP) &&
                     (cur_x_grp < OUTER_X0_GRP + CORNER_GROUPS)) ||
                    ((cur_x_grp > OUTER_X1_GRP - CORNER_GROUPS) &&
                     (cur_x_grp <= OUTER_X1_GRP));
    wire corner_y = ((cur_y >= OUTER_Y0) &&
                     (cur_y < OUTER_Y0 + CORNER_SIZE)) ||
                    ((cur_y > OUTER_Y0 + OUTER_H - CORNER_SIZE - 1) &&
                     (cur_y <= OUTER_Y0 + OUTER_H - 1));
    wire bg_sample_en = I_tvalid && corner_x && corner_y && (cur_y[1:0] == 2'b00);
    wire [11:0] bg_add = bg_sample_en ?
                         ({4'd0,y0} + {4'd0,y1} + {4'd0,y2} + {4'd0,y3}) : 12'd0;
    reg [19:0] bg_accum;
    wire frame_end = I_tvalid && I_tlast && (cur_y == IMG_HEIGHT-1);

    // 每个 56x56 单元每四行统计一次，最多 784 个样本；保留 11 bit，
    // 兼容较大的独立验证参数。
    reg [10:0] cell_count [0:GRID_CELLS-1];
    reg [10:0] cell_snapshot [0:GRID_CELLS-1];
    integer reset_i;

    wire inner_x = (cur_x_grp >= X0_GRP) &&
                   (cur_x_grp < (INNER_X0 + INNER_W) / 4);
    wire inner_y = (cur_y >= INNER_Y0) &&
                   (cur_y < INNER_Y0 + INNER_H);
    wire cell_sample_en = I_tvalid && inner_x && inner_y && (cur_y[1:0] == 2'b00);
    wire [9:0] inner_group_x = cur_x_grp - X0_GRP;
    // 用分界比较映射网格，避免非 2 的幂次 cell 尺寸推导出除法器。
    wire [2:0] cell_col =
        (inner_group_x < (CELL_GROUPS_PER_CELL * 1)) ? 3'd0 :
        (inner_group_x < (CELL_GROUPS_PER_CELL * 2)) ? 3'd1 :
        (inner_group_x < (CELL_GROUPS_PER_CELL * 3)) ? 3'd2 :
        (inner_group_x < (CELL_GROUPS_PER_CELL * 4)) ? 3'd3 : 3'd4;
    wire [9:0] inner_y_offset = cur_y - INNER_Y0;
    wire [2:0] cell_row =
        (inner_y_offset < (CELL_HEIGHT * 1)) ? 3'd0 :
        (inner_y_offset < (CELL_HEIGHT * 2)) ? 3'd1 :
        (inner_y_offset < (CELL_HEIGHT * 3)) ? 3'd2 :
        (inner_y_offset < (CELL_HEIGHT * 4)) ? 3'd3 :
        (inner_y_offset < (CELL_HEIGHT * 5)) ? 3'd4 :
        (inner_y_offset < (CELL_HEIGHT * 6)) ? 3'd5 : 3'd6;
    wire [5:0] cell_index = cell_row * GRID_COLS + cell_col;

    // 5x7 模板，位序为 row*5+col，常量只占 LUT，不推断 RAM。
    function [34:0] F_template;
        input [3:0] digit;
        begin
            case (digit)
                4'd0: F_template = 35'b01110_10001_10001_10001_10001_10001_01110;
                4'd1: F_template = 35'b00100_01100_00100_00100_00100_00100_01110;
                4'd2: F_template = 35'b01110_10001_00001_00010_00100_01000_11111;
                4'd3: F_template = 35'b11110_00001_00001_01110_00001_00001_11110;
                4'd4: F_template = 35'b00010_00110_01010_10010_11111_00010_00010;
                4'd5: F_template = 35'b11111_10000_10000_11110_00001_00001_11110;
                4'd6: F_template = 35'b01110_10000_10000_11110_10001_10001_01110;
                4'd7: F_template = 35'b11111_00001_00010_00100_01000_01000_01000;
                4'd8: F_template = 35'b01110_10001_10001_01110_10001_10001_01110;
                4'd9: F_template = 35'b01110_10001_10001_01111_00001_00001_01110;
                default: F_template = 35'd0;
            endcase
        end
    endfunction

    reg [GRID_CELLS-1:0] observed_bits;
    reg [3:0]  digit_index;
    reg [5:0]  bit_index;
    reg [5:0]  current_distance;
    reg [5:0]  best_distance;
    reg [5:0]  second_distance;
    reg [3:0]  best_digit;
    reg [3:0]  result_digit;
    reg [5:0]  result_best_distance;
    reg [5:0]  result_second_distance;
    reg [1:0]  stable_run;
    reg [3:0]  stable_digit;
    reg [1:0]  frame_count;

    localparam ST_IDLE   = 3'd0;
    localparam ST_FEATURE= 3'd1;
    localparam ST_HAM    = 3'd2;
    localparam ST_RESULT = 3'd3;
    reg [2:0] state;

    wire [34:0] template_word = F_template(digit_index);
    // 模板字面量的左端是第 0 行第 0 列（bit34），而 observed_bits[0]
    // 也是第 0 行第 0 列，因此比较时反向索引模板。
    wire template_bit = template_word[6'd34 - bit_index];
    wire [5:0] distance_next = current_distance +
                                ((observed_bits[bit_index] ^ template_bit) ? 6'd1 : 6'd0);

    // 坐标计数器只随有效数据前进。tuser 所在拍直接使用 (0,0)，因此不再
    // 依赖上游模块固定流水拍数，和 ua_I_tuser_aligned 的约定一致。
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            x_grp <= 10'd0;
            y_pos <= 10'd0;
        end else if (I_tvalid) begin
            if (I_tuser) begin
                x_grp <= 10'd1;
                y_pos <= 10'd0;
            end else if (I_tlast) begin
                x_grp <= 10'd0;
                y_pos <= y_pos + 10'd1;
            end else if (x_grp == IMG_W_GRP-1) begin
                x_grp <= 10'd0;
                y_pos <= y_pos + 10'd1;
            end else begin
                x_grp <= x_grp + 10'd1;
            end
        end
    end

    // 采样、快照和识别 FSM。快照保证帧首立即到来时，下一帧清零计数器
    // 不会覆盖上一帧的分类数据。
    always @(posedge I_clk or negedge I_rst_n) begin : p_digit_core
        integer i;
        reg [19:0] bg_total;
        reg [5:0] last_dist;
        reg [5:0] new_best;
        reg [5:0] new_second;
        reg [3:0] new_best_digit;
        reg [7:0] margin_value;
        if (!I_rst_n) begin
            bg_luma <= 8'd220;
            bg_ready <= 1'b0;
            bg_accum <= 20'd0;
            observed_bits <= 35'd0;
            digit_index <= 4'd0;
            bit_index <= 6'd0;
            current_distance <= 6'd0;
            best_distance <= 6'd63;
            second_distance <= 6'd63;
            best_digit <= 4'd0;
            result_digit <= 4'hf;
            result_best_distance <= 6'd63;
            result_second_distance <= 6'd63;
            stable_run <= 2'd0;
            stable_digit <= 4'hf;
            frame_count <= 2'd0;
            O_digit_valid <= 1'b0;
            O_digit_id <= 4'hf;
            O_digit_confidence <= 8'd0;
            state <= ST_IDLE;
            for (reset_i = 0; reset_i < GRID_CELLS; reset_i = reset_i + 1) begin
                cell_count[reset_i] <= 11'd0;
                cell_snapshot[reset_i] <= 11'd0;
            end
        end else begin
            O_digit_valid <= 1'b0;

            // 每帧开始清空当前帧计数，并在帧首后的数据拍继续累加。
            if (I_tvalid && I_tuser) begin
                bg_accum <= 20'd0;
                for (i = 0; i < GRID_CELLS; i = i + 1)
                    cell_count[i] <= 11'd0;
            end else begin
                if (bg_sample_en)
                    bg_accum <= bg_accum + bg_add;
                if (cell_sample_en)
                    cell_count[cell_index] <= cell_count[cell_index] + black_sum;
            end

            // 帧尾得到白底平均值并复制网格计数。720p 内框在帧尾之前结束，
            // 因此最后一拍不会同时写入 cell_count，快照无需额外修正。
            if (frame_end) begin
                bg_total = bg_accum + bg_add;
                if (|bg_total[19:16])
                    bg_luma <= 8'hff;
                else
                    bg_luma <= bg_total[15:8];
                bg_ready <= 1'b1;
                if (frame_count != 2'd3)
                    frame_count <= frame_count + 2'd1;
                for (i = 0; i < GRID_CELLS; i = i + 1)
                    cell_snapshot[i] <= cell_count[i];
                if (state == ST_IDLE)
                    state <= ST_FEATURE;
            end

            case (state)
                ST_FEATURE: begin
                    for (i = 0; i < GRID_CELLS; i = i + 1)
                        observed_bits[i] <= (cell_snapshot[i] >= CELL_MIN);
                    digit_index <= 4'd0;
                    bit_index <= 6'd0;
                    current_distance <= 6'd0;
                    best_distance <= 6'd63;
                    second_distance <= 6'd63;
                    best_digit <= 4'd0;
                    state <= ST_HAM;
                end

                ST_HAM: begin
                    if (bit_index == 6'd34) begin
                        last_dist = distance_next;
                        new_best = best_distance;
                        new_second = second_distance;
                        new_best_digit = best_digit;
                        if (last_dist < best_distance) begin
                            new_second = best_distance;
                            new_best = last_dist;
                            new_best_digit = digit_index;
                        end else if (last_dist < second_distance) begin
                            new_second = last_dist;
                        end
                        current_distance <= 6'd0;
                        if (digit_index == 4'd9) begin
                            result_digit <= new_best_digit;
                            result_best_distance <= new_best;
                            result_second_distance <= new_second;
                            state <= ST_RESULT;
                        end else begin
                            best_distance <= new_best;
                            second_distance <= new_second;
                            best_digit <= new_best_digit;
                            digit_index <= digit_index + 4'd1;
                            bit_index <= 6'd0;
                        end
                    end else begin
                        current_distance <= distance_next;
                        bit_index <= bit_index + 6'd1;
                    end
                end

                ST_RESULT: begin
                    if ((frame_count >= 2'd2) &&
                        (result_best_distance <= 6'd12) &&
                        ((result_second_distance - result_best_distance) >= MIN_MARGIN)) begin
                        margin_value = {2'd0,result_second_distance} -
                                       {2'd0,result_best_distance};
                        O_digit_confidence <= margin_value;
                        O_digit_id <= result_digit;
                        if ((stable_digit == result_digit) && (stable_run != 2'd3))
                            stable_run <= stable_run + 2'd1;
                        else if (stable_digit != result_digit) begin
                            stable_digit <= result_digit;
                            stable_run <= 2'd1;
                        end
                        // 新候选的第一帧只建立稳定计数；只有同一候选已经
                        // 连续出现三帧时才发布，避免切换数字时沿用旧 run。
                        if ((stable_digit == result_digit) && (stable_run >= 2'd2)) begin
                            O_digit_valid <= 1'b1;
                            O_digit_id <= result_digit;
                        end
                    end else begin
                        stable_run <= 2'd0;
                        stable_digit <= 4'hf;
                        O_digit_id <= 4'hf;
                        O_digit_confidence <= 8'd0;
                    end
                    state <= ST_IDLE;
                end

                default: begin
                    // ST_IDLE 等待当前帧帧尾；采样逻辑在状态机之外持续运行。
                    // 无赋值即保持当前状态；避免覆盖同拍的帧尾 ST_FEATURE 跳转。
                end
            endcase
        end
    end

endmodule


