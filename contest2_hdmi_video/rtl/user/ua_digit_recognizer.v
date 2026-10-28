// ============================================================================
// ua_digit_recognizer : 固定区域的轻量数字识别器
//
// 输入为 AWB 后的 96-bit RGB888 流，每拍 4 个像素；tuser 是帧首，tlast
// 是行尾。模块只观察视频，不参与 ready/数据通路，因此不会改变 HDMI 图像。
//
// 算法约束（有意保持为可综合、可解释的竞赛演示版本）：
//   1. 外框 288x384，内框 240x336，内框划分为 5x7 个 48x48 单元；
//   2. 外框四角各采样 16x16 点估计白底亮度，当前帧用 bg-offset 做分割；
//   3. 每个单元每 4 行采样一次，至少 1/8 采样点为深色才计为笔画；
//   4. 形成 35-bit 占用图，逐位与 0..9 模板比较；
//   5. 最佳/次佳距离形成置信度，连续三帧相同才发布 valid 脉冲。
// v67: ADAPTIVE_ROI=1 时先在外框附近定位有足够行支撑的深色数字，
// 下一帧按其包围盒归一化为5x7；内部占用门槛37.5%，拒绝搜索边界截断。
// ADAPTIVE_ROI=0 保留旧固定网格及显式CELL_MIN兼容路径。
//
// 该模块适用于固定位置的黑字白卡数字识别，不是自然场景 OCR，也不使用
// ERAM、DSP、除法器或乘法器。参数允许独立验证时缩小 ROI；实际 720p 默认值
// 与 design_top_user 的 1280x720 坐标对齐。
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module ua_digit_recognizer #(
    parameter integer IMG_WIDTH   = 1280,
    parameter integer IMG_HEIGHT  = 720,
    parameter integer OUTER_X0    = 496,
    parameter integer OUTER_Y0    = 168,
    parameter integer OUTER_W     = 288,
    parameter integer OUTER_H     = 384,
    parameter integer INNER_X0    = 520,
    parameter integer INNER_Y0    = 192,
    parameter integer INNER_W     = 240,
    parameter integer INNER_H     = 336,
    parameter integer CELL_W      = 48,
    parameter integer CELL_H      = 48,
    parameter integer CELL_GRP_LOG2 = 4,
    parameter integer CELL_H_LOG2   = 6,
    // Numeric cell dimensions support non-power-of-two scaling while retaining
    // the legacy log2 parameters for older standalone testbench instantiations.
    parameter integer CELL_GROUPS_PER_CELL = (CELL_W / 4),
    parameter integer CELL_HEIGHT = CELL_H,
    parameter integer BG_OFFSET   = 32,
    // Old product threshold was only 32/784 (~4%). Small fringe strokes
    // could fill the holes of 8. Scale the occupancy gate with sample area.
    parameter integer CELL_MIN    = (CELL_W * ((CELL_H + 3) / 4)) / 8,
    parameter integer MIN_MARGIN  = 2,
    parameter integer ADAPTIVE_ROI = 1,
    parameter integer AUTO_FIND = 0
)(
    input wire          I_clk,
    input wire          I_rst_n,
    input wire          I_tlast,
    input wire          I_tuser,
    input wire [95:0]   I_tdata,
    input wire          I_tvalid,
    output reg          O_digit_valid,
    output reg  [3:0]   O_digit_id,
    output reg  [7:0]   O_digit_confidence,
    output reg          O_result_event,
    output wire [56:0]  O_result_view
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
    wire card_found;
    wire [9:0] card_x0,card_x1,card_y0,card_y1;
    wire [7:0] rg=(pix0[23:16]>pix0[15:8])?(pix0[23:16]-pix0[15:8]):(pix0[15:8]-pix0[23:16]);
    wire [7:0] bg=(pix0[7:0]>pix0[15:8])?(pix0[7:0]-pix0[15:8]):(pix0[15:8]-pix0[7:0]);
    reg [7:0] white_level;
    reg [1:0] white_scan;
    reg [2:0] unconfirmed_frames;
    reg threshold_pending;
    wire [7:0] auto_threshold=white_level-8'd32;
    wire [2:0] black_sum;
    always @(posedge I_clk or negedge I_rst_n)begin
      if(!I_rst_n)begin white_level<=160;white_scan<=0;unconfirmed_frames<=0;threshold_pending<=0;end
      else if(AUTO_FIND)begin
        threshold_pending<=I_tvalid && frame_end;
        // Start in the bright-card level; search bounded alternatives when
        // lost or unconfirmed for eight frames. No full-frame peak dependency.
        if(threshold_pending)begin
          if(!card_found || (!held_valid && unconfirmed_frames==7))begin
            unconfirmed_frames<=0;
            white_scan<=white_scan+2'd1;
            case(white_scan)
              0:white_level<=96;
              1:white_level<=128;
              2:white_level<=160;
              3:white_level<=80;
            endcase
          end else if(held_valid)unconfirmed_frames<=0;
          else unconfirmed_frames<=unconfirmed_frames+3'd1;
        end
      end
    end
    generate if(AUTO_FIND)begin:gen_auto_card
      ua_digit_card_locator #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT)) u_card(
       .clk(I_clk),.rst_n(I_rst_n),.valid(I_tvalid),.sof(I_tuser),.eol(I_tlast),
       .white(y0>=white_level && y1>=white_level && y2>=white_level && y3>=white_level && rg<=48 && bg<=48),
       .dark(black_sum>=3),
       .x(cur_x_grp),.y(cur_y),.found(card_found),
       .x0(card_x0),.x1(card_x1),.y0(card_y0),.y1(card_y1));
    end else begin:gen_fixed_card
      assign card_found=1'b1;assign card_x0=OUTER_X0_GRP;assign card_x1=OUTER_X1_GRP;
      assign card_y0=OUTER_Y0;assign card_y1=OUTER_Y0+OUTER_H-1;
    end endgenerate
    reg snapshot_geometry_good;
    reg [43:0] snapshot_card;
    wire current_card_overlaps=card_found &&
      card_x1>={1'b0,snapshot_card[43:35]} && card_x0<={1'b0,snapshot_card[32:24]} &&
      {1'b0,card_y1}>=snapshot_card[21:11] && {1'b0,card_y0}<=snapshot_card[10:0];
    assign O_result_view={O_digit_valid,O_digit_id,O_digit_confidence,snapshot_card};

    reg [7:0] bg_luma;
    reg       bg_ready;
    wire [8:0] threshold_ext = (bg_luma > BG_OFFSET) ?
                               {1'b0,bg_luma} - BG_OFFSET : 9'd0;
    wire [7:0] threshold = AUTO_FIND?auto_threshold:threshold_ext[7:0];

    assign black_sum =
        (y0 < threshold) + (y1 < threshold) +
        (y2 < threshold) + (y3 < threshold);

    // 外框四角各采样 16x16 区域、每四行取一行，总计 256 个样本；
    // 帧尾右移 8 位得到平均值，综合时不出现除法器。
    wire corner_x = ((cur_x_grp >= card_x0) &&
                     (cur_x_grp < card_x0 + CORNER_GROUPS)) ||
                    ((cur_x_grp > card_x1 - CORNER_GROUPS) &&
                     (cur_x_grp <= card_x1));
    wire corner_y = ((cur_y >= card_y0) &&
                     (cur_y < card_y0 + CORNER_SIZE)) ||
                    ((cur_y > card_y1 - CORNER_SIZE) &&
                     (cur_y <= card_y1));
    wire bg_sample_en = !AUTO_FIND && I_tvalid && card_found && corner_x && corner_y && (cur_y[1:0] == 2'b00);
    wire [11:0] bg_add = bg_sample_en ?
                         ({4'd0,y0} + {4'd0,y1} + {4'd0,y2} + {4'd0,y3}) : 12'd0;
    reg [19:0] bg_accum;
    wire frame_end = I_tvalid && I_tlast && (cur_y == IMG_HEIGHT-1);

    // Locate the foreground first, then normalize the following frame. A small
    // guard accommodates handwriting close to the displayed box, but clipped
    // components touching the guard are rejected instead of becoming digit 1.
    localparam integer FIXED_SEARCH_X0 = (OUTER_X0 >= 24) ? (OUTER_X0-24)/4 : 0;
    localparam integer FIXED_SEARCH_X1 = ((OUTER_X0+OUTER_W+24)/4 < IMG_W_GRP) ?
                                   (OUTER_X0+OUTER_W+24)/4 : IMG_W_GRP;
    localparam integer FIXED_SEARCH_Y0 = (OUTER_Y0 >= 24) ? OUTER_Y0-24 : 0;
    localparam integer FIXED_SEARCH_Y1 = (OUTER_Y0+OUTER_H+24 < IMG_HEIGHT) ?
                                   OUTER_Y0+OUTER_H+24 : IMG_HEIGHT;
    wire [9:0] SEARCH_X0=AUTO_FIND?((card_x0>8)?card_x0-10'd8:10'd0):FIXED_SEARCH_X0;
    wire [9:0] SEARCH_X1=AUTO_FIND?((card_x1<IMG_W_GRP-9)?card_x1+10'd9:IMG_W_GRP):FIXED_SEARCH_X1;
    wire [9:0] SEARCH_Y0=AUTO_FIND?((card_y0>16)?card_y0-10'd16:10'd0):FIXED_SEARCH_Y0;
    wire [9:0] SEARCH_Y1=AUTO_FIND?((card_y1<IMG_HEIGHT-17)?card_y1+10'd17:IMG_HEIGHT):FIXED_SEARCH_Y1;
    reg [9:0] fg_x0,fg_x1,fg_y0,fg_y1;
    reg fg_seen;
    reg [9:0] row_x0,row_x1;
    reg [6:0] row_hits;
    localparam integer ROW_SUPPORT = AUTO_FIND?2:((FIXED_SEARCH_X1-FIXED_SEARCH_X0>=64) ? 8 : 2);
    wire locate_hit = I_tvalid && card_found && (cur_y[1:0]==0) && black_sum>=3 &&
        cur_x_grp>=SEARCH_X0 && cur_x_grp<SEARCH_X1 &&
        cur_y>=SEARCH_Y0 && cur_y<SEARCH_Y1;
    wire bbox_good = AUTO_FIND?card_found:(card_found && fg_seen && fg_x1-fg_x0>=7 && fg_y1-fg_y0>=44 &&
        fg_x0>SEARCH_X0 && fg_x1<SEARCH_X1-1 &&
        fg_y0>SEARCH_Y0 && fg_y1<SEARCH_Y1-4);
    reg [9:0] norm_x0,norm_y0,pending_x0,pending_y0;
    reg [9:0] rem_x,rem_y;
    reg [6:0] quotient_x,quotient_y,step_x,step_y;
    reg [2:0] extra_columns;
    reg geometry_busy,geometry_ready,pending_narrow;
    // Explicit shift/add widths avoid 32-bit constant multipliers in TD.
    wire [9:0] quotient_x5={1'b0,quotient_x,2'b00}+{3'b000,quotient_x};
    wire [10:0] narrow_start={1'b0,pending_x0}-{1'b0,quotient_x5}-(AUTO_FIND?{8'd0,rem_x[2:0]}:11'd0);
    wire [9:0] step_x5={1'b0,step_x,2'b00}+{3'b000,step_x};
    wire [9:0] step_y7={step_y,3'b000}-{3'b000,step_y};
    wire [10:0] norm_end_x={1'b0,norm_x0}+{1'b0,step_x5}+{8'd0,extra_columns};
    wire [10:0] norm_end_y={1'b0,norm_y0}+{1'b0,step_y7};
    wire [9:0] box_x0=AUTO_FIND?card_x0:fg_x0,box_x1=AUTO_FIND?card_x1:fg_x1;
    wire [9:0] box_y0=AUTO_FIND?card_y0:fg_y0;
    wire [9:0] bbox_width = box_x1-box_x0+1'b1;
    wire [9:0] bbox_height = AUTO_FIND?(card_y1-card_y0+1'b1):(fg_y1-fg_y0+10'd4);
    // A narrow '1' must retain side whitespace rather than be stretched to 5
    // full columns. Other digits use the detected extent directly.
    wire narrow_digit = (bbox_width<<2) < (bbox_height>>1);
    // Shift/add approximation of height*5/28 in four-pixel groups; no divider.
    wire [9:0] padded_width = narrow_digit ?
        ((bbox_height>>3)+(bbox_height>>5)+(bbox_height>>6)+(bbox_height>>7)) : bbox_width;
    wire [9:0] desired_x0 = narrow_digit ? (box_x0+box_x1+1'b1) : box_x0;
    wire [7:0] norm_sample_rows = {3'd0,step_y[6:2]} + (|step_y[1:0]);
    wire [14:0] norm_sample_product = step_x * norm_sample_rows;
    wire [15:0] adaptive_gate = {1'b0,norm_sample_product} + (norm_sample_product>>1);
    wire [10:0] occupancy_gate = ADAPTIVE_ROI ?
        ((adaptive_gate>=2) ? adaptive_gate[10:0] : 11'd2) : CELL_MIN;
    // Each extra-width column gets the same 37.5% occupancy threshold,
    // computed with one shared add rather than five new multipliers.
    wire [14:0] wide_product=norm_sample_product+{7'd0,norm_sample_rows};
    wire [15:0] wide_gate={1'b0,wide_product}+(wide_product>>1);
    wire [10:0] occupancy_gate_wide=(wide_gate>=2)?wide_gate[10:0]:11'd2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            fg_seen<=0;fg_x0<=0;fg_x1<=0;fg_y0<=0;fg_y1<=0;
            row_x0<=0;row_x1<=0;row_hits<=0;
            norm_x0<=0;norm_y0<=0;pending_x0<=0;pending_y0<=0;
            rem_x<=0;rem_y<=0;quotient_x<=0;quotient_y<=0;
            extra_columns<=0;step_x<=1;step_y<=1;geometry_busy<=0;geometry_ready<=0;pending_narrow<=0;
        end else if(ADAPTIVE_ROI) begin
            if(!AUTO_FIND)begin
            if(I_tvalid && I_tuser) begin fg_seen<=0;row_hits<=0;end
            else if(I_tvalid && I_tlast) begin
                row_hits<=0;
                if(cur_y[1:0]==0 && row_hits>=ROW_SUPPORT) begin
                    if(!fg_seen) begin
                        fg_x0<=row_x0;fg_x1<=row_x1;
                        fg_y0<=cur_y;fg_y1<=cur_y;fg_seen<=1;
                    end else begin
                        if(row_x0<fg_x0)fg_x0<=row_x0;
                        if(row_x1>fg_x1)fg_x1<=row_x1;
                        fg_y1<=cur_y;
                    end
                end
            end else if(locate_hit) begin
                if(row_hits==0)row_x0<=cur_x_grp;
                row_x1<=cur_x_grp;
                if(row_hits!=127)row_hits<=row_hits+1'b1;
            end
            end
            if(frame_end) begin
                geometry_ready<=0;
                geometry_busy<=bbox_good;
                pending_x0<=desired_x0;pending_y0<=box_y0;
                pending_narrow<=narrow_digit;
                rem_x<=padded_width+(AUTO_FIND?10'd0:10'd4);rem_y<=bbox_height+6;
                quotient_x<=0;quotient_y<=0;
            end else if(geometry_busy) begin
                // Shared-in-time constant divisors, not parallel /5 and /7.
                if(rem_x>=5)begin rem_x<=rem_x-5;quotient_x<=quotient_x+1'b1;end
                if(rem_y>=7)begin rem_y<=rem_y-7;quotient_y<=quotient_y+1'b1;end
                if(rem_x<5 && rem_y<7)begin
                    step_x<=(quotient_x!=0)?quotient_x:7'd1;step_y<=quotient_y;
                    extra_columns<=AUTO_FIND?rem_x[2:0]:3'd0;
                    norm_x0<=pending_narrow ? narrow_start[10:1] : pending_x0;
                    norm_y0<=pending_y0;
                    geometry_busy<=0;geometry_ready<=!AUTO_FIND || quotient_x!=0;
                end
            end
        end
    end

    // 每个 48x48 单元每四行统计一次，最多 576 个样本；保留 11 bit，
    // 兼容较大的独立验证参数。
    // Raster cell rows are monotone. Keep only the active row's five counts;
    // completed rows retain exact threshold bits, not unnecessary counts.
    reg [10:0] cell_count [0:GRID_COLS-1];
    reg [GRID_CELLS-1:0] row_feature_bits;
    reg [2:0] active_row;
    reg row_active;
    // Classification consumes only >=CELL_MIN, not the numerical counts.
    // Snapshot that exact predicate: 35 bits instead of 35*11, same FSM timing.
    reg [GRID_CELLS-1:0] cell_snapshot_bits;
    wire [GRID_COLS-1:0] completed_row;
    genvar gate_col;
    generate for(gate_col=0;gate_col<GRID_COLS;gate_col=gate_col+1)begin:gen_completed_row
      assign completed_row[gate_col]=(cell_count[gate_col]>=
          ((AUTO_FIND && gate_col<extra_columns)?occupancy_gate_wide:occupancy_gate));
    end endgenerate
    integer reset_i;

    wire [9:0] grid_x0 = ADAPTIVE_ROI ? norm_x0 : X0_GRP;
    wire [9:0] grid_y0 = ADAPTIVE_ROI ? norm_y0 : INNER_Y0;
    wire [9:0] grid_step_x = ADAPTIVE_ROI ? {3'd0,step_x} : CELL_GROUPS_PER_CELL;
    wire [9:0] grid_step_y = ADAPTIVE_ROI ? {3'd0,step_y} : CELL_HEIGHT;
    // Raster order allows countdown bins instead of ten parallel dynamic
    // boundary comparators and their shift/add thresholds (v67r1).
    reg [2:0] scan_col,scan_row;
    reg [6:0] col_remaining,row_remaining;
    wire first_column = cur_x_grp==grid_x0;
    wire first_row = cur_y==grid_y0;
    wire [2:0] raster_col = first_column ? 3'd0 :
        ((col_remaining==0) ? scan_col+3'd1 : scan_col);
    wire [2:0] raster_row = first_row ? 3'd0 :
        ((row_remaining==0) ? scan_row+3'd1 : scan_row);
    wire [7:0] raster_width={1'b0,step_x}+((AUTO_FIND && raster_col<extra_columns)?8'd1:8'd0);
    wire inner_x = (cur_x_grp >= grid_x0) && (ADAPTIVE_ROI ?
                   raster_col<5 : cur_x_grp < grid_x0 + grid_step_x*5);
    wire inner_y = (cur_y >= grid_y0) && (ADAPTIVE_ROI ?
                   raster_row<7 : cur_y < grid_y0 + grid_step_y*7);
    wire cell_sample_en = I_tvalid && card_found && inner_x && inner_y && (cur_y[1:0] == 2'b00);
    // Whiten padding beyond the located ink; tilted phone borders and an
    // adjacent partly visible card must not become normalization padding.
    wire [2:0] sample_black=(AUTO_FIND && (cur_x_grp<card_x0 || cur_x_grp>card_x1 ||
        cur_y<card_y0 || cur_y>card_y1))?3'd0:black_sum;
    wire [9:0] inner_group_x = cur_x_grp - grid_x0;
    // 用分界比较映射网格，避免非 2 的幂次 cell 尺寸推导出除法器。
    wire [2:0] cell_col = ADAPTIVE_ROI ? raster_col :
        (inner_group_x < (grid_step_x * 1)) ? 3'd0 :
        (inner_group_x < (grid_step_x * 2)) ? 3'd1 :
        (inner_group_x < (grid_step_x * 3)) ? 3'd2 :
        (inner_group_x < (grid_step_x * 4)) ? 3'd3 : 3'd4;
    wire [9:0] inner_y_offset = cur_y - grid_y0;
    wire [2:0] cell_row = ADAPTIVE_ROI ? raster_row :
        (inner_y_offset < (grid_step_y * 1)) ? 3'd0 :
        (inner_y_offset < (grid_step_y * 2)) ? 3'd1 :
        (inner_y_offset < (grid_step_y * 3)) ? 3'd2 :
        (inner_y_offset < (grid_step_y * 4)) ? 3'd3 :
        (inner_y_offset < (grid_step_y * 5)) ? 3'd4 :
        (inner_y_offset < (grid_step_y * 6)) ? 3'd5 : 3'd6;
    wire [5:0] cell_index = cell_row * GRID_COLS + cell_col;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)begin scan_col<=0;scan_row<=0;col_remaining<=0;row_remaining<=0;end
        else if(ADAPTIVE_ROI && I_tvalid)begin
            if(I_tuser)begin scan_row<=0;row_remaining<=0;end
            if(inner_x)begin
                scan_col<=raster_col;
                col_remaining<=(first_column || col_remaining==0) ? raster_width-8'd1 : col_remaining-1'b1;
            end
            if(I_tlast && inner_y)begin
                scan_row<=raster_row;
                row_remaining<=(first_row || row_remaining==0) ? step_y-1'b1 : row_remaining-1'b1;
            end
        end
    end

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
    // Median over three spatially coherent feature maps rejects one-frame
    // threshold flicker. Geometry loss invalidates history before reuse.
    reg [34:0] feature_prev1,feature_prev2;
    reg feature_history_ready;
    reg held_valid;
    reg [3:0] held_digit;
    reg [7:0] held_confidence;
    reg [2:0] held_age;
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
    reg stable_reject;
    reg [3:0]  stable_digit;
    reg [1:0]  frame_count;
    reg [9:0] template_address;
    reg [5:0] digit_best_distance;

    // Closed-loop classes need vertical support through the inner rows.
    // A wholly empty middle band cannot support 0/6/8/9; do not turn a
    // fragmented open glyph into a confident loop merely by template distance.
    wire closed_class=(result_digit==0 || result_digit==6 || result_digit==8 || result_digit==9);
    wire inner_row_support=(|observed_bits[9:5]) && (|observed_bits[14:10]) &&
        (|observed_bits[19:15]) && (|observed_bits[24:20]) && (|observed_bits[29:25]);
    wire feature_quality=!AUTO_FIND || !closed_class || inner_row_support;
    localparam ST_IDLE   = 3'd0;
    localparam ST_FEATURE= 3'd1;
    localparam ST_HAM    = 3'd2;
    localparam ST_RESULT = 3'd3;
    localparam ST_FETCH  = 3'd4;
    reg [2:0] state;

    wire [34:0] template_word;
    generate if(AUTO_FIND)begin:gen_tilted_templates
      ua_digit_template_rom u_codebook(I_clk,template_address,template_word);
    end else begin:gen_original_templates
      assign template_word=F_template(digit_index);
    end endgenerate
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
        integer i,feature_row;
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
            feature_prev1<=0;feature_prev2<=0;feature_history_ready<=0;
            held_valid<=0;held_digit<=15;held_confidence<=0;held_age<=0;
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
            stable_reject <= 1'b0;
            stable_digit <= 4'hf;
            frame_count <= 2'd0;
            template_address<=0;digit_best_distance<=63;
            O_digit_valid <= 1'b0;
            O_result_event<=0;snapshot_geometry_good<=0;snapshot_card<=0;
            O_digit_id <= 4'hf;
            O_digit_confidence <= 8'd0;
            state <= ST_IDLE;
            cell_snapshot_bits <= {GRID_CELLS{1'b0}};
            row_feature_bits <= {GRID_CELLS{(11'd0>=CELL_MIN)}};
            active_row <= 0;row_active <= 0;
            for (reset_i = 0; reset_i < GRID_COLS; reset_i = reset_i + 1) begin
                cell_count[reset_i] <= 11'd0;
            end
        end else begin
            O_digit_valid <= 1'b0;
            O_result_event<=0;

            // 每帧开始清空当前帧计数，并在帧首后的数据拍继续累加。
            if (I_tvalid && I_tuser) begin
                bg_accum <= 20'd0;
                for (i = 0; i < GRID_COLS; i = i + 1)
                    cell_count[i] <= 11'd0;
                row_feature_bits <= {GRID_CELLS{(11'd0>=CELL_MIN)}};
                row_active <= 0;active_row <= 0;
            end else begin
                if (bg_sample_en)
                    bg_accum <= bg_accum + bg_add;
                if (cell_sample_en) begin
                    if(!row_active || active_row!=cell_row) begin
                        // Decode seven rows once; avoid five independent
                        // variable bit-write muxes and the row*5 multiplier.
                        if(row_active) for(feature_row=0;feature_row<GRID_ROWS;feature_row=feature_row+1)
                            if(active_row==feature_row)
                                row_feature_bits[feature_row*GRID_COLS+:GRID_COLS] <= completed_row;
                        for(i=0;i<GRID_COLS;i=i+1)
                            cell_count[i] <= (cell_col==i) ? {8'd0,sample_black} : 11'd0;
                        row_active<=1;active_row<=cell_row;
                    end else cell_count[cell_col] <= cell_count[cell_col] + sample_black;
                end
            end

            // 帧尾得到白底平均值并复制网格计数。720p 内框在帧尾之前结束，
            // 因此最后一拍不会同时写入 cell_count，快照无需额外修正。
            if (frame_end) begin
                snapshot_card<={{card_x0[8:0],2'b00},{card_x1[8:0],2'b11},{1'b0,card_y0},{1'b0,card_y1}};
                snapshot_geometry_good<=card_found && geometry_ready &&
                  norm_x0>=SEARCH_X0 && norm_end_x<={1'b0,SEARCH_X1} &&
                  norm_y0>=SEARCH_Y0 && norm_end_y<={1'b0,SEARCH_Y1};
                bg_total = bg_accum + bg_add;
                if(AUTO_FIND)bg_luma<=white_level;
                else if (|bg_total[19:16])
                    bg_luma <= 8'hff;
                else
                    bg_luma <= bg_total[15:8];
                bg_ready <= 1'b1;
                if (frame_count != 2'd3)
                    frame_count <= frame_count + 2'd1;
                for (i = 0; i < GRID_CELLS; i = i + 1)
                    cell_snapshot_bits[i] <= (row_active && (i/GRID_COLS)==active_row) ?
                        (cell_count[i%GRID_COLS]>=((AUTO_FIND && (i%GRID_COLS)<extra_columns)?occupancy_gate_wide:occupancy_gate)) : row_feature_bits[i];
                if (state == ST_IDLE)
                    state <= ST_FEATURE;
            end

            case (state)
                ST_FEATURE: begin
                    observed_bits <= (AUTO_FIND && feature_history_ready && snapshot_geometry_good && current_card_overlaps) ?
                        ((cell_snapshot_bits & feature_prev1) | (cell_snapshot_bits & feature_prev2) | (feature_prev1 & feature_prev2)) : cell_snapshot_bits;
                    if(AUTO_FIND)begin
                        if(snapshot_geometry_good && current_card_overlaps)begin
                            feature_prev1<=cell_snapshot_bits;
                            feature_prev2<=feature_history_ready?feature_prev1:cell_snapshot_bits;
                            feature_history_ready<=1;
                        end else feature_history_ready<=0;
                    end
                    digit_index <= 4'd0;
                    bit_index <= 6'd0;
                    current_distance <= 6'd0;
                    best_distance <= 6'd63;
                    second_distance <= 6'd63;
                    best_digit <= 4'd0;
                    template_address<=0;digit_best_distance<=63;
                    state <= AUTO_FIND?ST_FETCH:ST_HAM;
                end

                ST_FETCH:state<=ST_HAM;

                ST_HAM: begin
                    if (bit_index == 6'd34) begin
                        last_dist = (AUTO_FIND && digit_best_distance<distance_next)?digit_best_distance:distance_next;
                        new_best = best_distance;
                        new_second = second_distance;
                        new_best_digit = best_digit;
                        current_distance<=0;
                        if(!AUTO_FIND || template_address[5:0]==6'd63)begin
                        if (last_dist < best_distance) begin
                            new_second = best_distance;
                            new_best = last_dist;
                            new_best_digit = digit_index;
                        end else if (last_dist < second_distance) begin
                            new_second = last_dist;
                        end
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
                        digit_best_distance<=63;
                        end else begin
                            digit_best_distance<=last_dist;
                            bit_index<=0;
                        end
                        if(AUTO_FIND && !(digit_index==9 && template_address[5:0]==63))begin
                            template_address<=template_address+1'b1;state<=ST_FETCH;
                        end
                    end else begin
                        current_distance <= distance_next;
                        bit_index <= bit_index + 6'd1;
                    end
                end

                ST_RESULT: begin
                    O_result_event<=1;
                    if ((frame_count >= 2'd2) && (!ADAPTIVE_ROI || geometry_ready) &&
                        (!AUTO_FIND || (snapshot_geometry_good && current_card_overlaps)) &&
                        feature_quality && (result_best_distance <= (AUTO_FIND?6'd6:6'd12)) &&
                        ((result_second_distance - result_best_distance) >= MIN_MARGIN)) begin
                        margin_value = {2'd0,result_second_distance} -
                                       {2'd0,result_best_distance};
                        stable_reject <= 1'b0;
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
                        // At most one rejected observation between matching
                        // accepted votes. Never bridge missing/disjoint cards.
                        if(AUTO_FIND && snapshot_geometry_good && current_card_overlaps &&
                           stable_run!=0 && !stable_reject) stable_reject<=1'b1;
                        else begin
                            stable_run <= 2'd0;
                            stable_digit <= 4'hf;
                            stable_reject <= 1'b0;
                        end
                        O_digit_id <= 4'hf;
                        O_digit_confidence <= 8'd0;
                    end
                    // Hold only a previously confirmed result, for at most
                    // five rejected frames. A missing/moved card clears it
                    // immediately; unconfirmed candidates never enter hold.
                    if(AUTO_FIND)begin
                        if(!snapshot_geometry_good || !current_card_overlaps)begin
                            held_valid<=0;held_age<=0;
                        end else if(frame_count>=2 && geometry_ready && feature_quality && result_best_distance<=6 &&
                            result_second_distance-result_best_distance>=MIN_MARGIN &&
                            stable_digit==result_digit && stable_run>=2)begin
                            held_valid<=1;held_age<=0;held_digit<=result_digit;
                            held_confidence<={2'd0,result_second_distance}-{2'd0,result_best_distance};
                        end else if(feature_quality && result_best_distance<=6 &&
                            result_second_distance-result_best_distance>=MIN_MARGIN &&
                            result_digit!=held_digit)begin
                            // A confident contradictory observation is a card
                            // change, not a missed frame. Clear stale display
                            // while the new class collects its own votes.
                            held_valid<=0;held_age<=0;
                        end else if(held_valid && held_age<5)begin
                            O_digit_valid<=1;O_digit_id<=held_digit;O_digit_confidence<=held_confidence;
                            held_age<=held_age+1'b1;
                        end else held_valid<=0;
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
`default_nettype wire
