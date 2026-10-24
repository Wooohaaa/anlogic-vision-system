// Frame-level luminance statistics for automatic exposure.
// 初学者提示：这是统计支路，不修改显示像素；结果在帧首更新并保持一帧，
// 让跨时钟域接收端有充足的稳定时间。
//
// The input is the 96-bit demosaic stream before AWB/Gamma (four RGB888 pixels per clock).  To keep
// the logic small, only pixel 0 is sampled on a regular grid inside a centred
// 512-pixel-wide window.  At the product 1280x720 geometry this is 32 samples
// per row over 32 rows = exactly 1024 samples, so the frame mean is a shift.
`timescale 1ns/1ps
module ua_luma_stats #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    parameter integer HIGHLIGHT_ENABLE = 0,
    parameter integer REFLECTION_TOLERANT = 0,
    // Must exceed the controller bright threshold in the production pairing.
    // Legacy default retains prior standalone fixtures; product selects 96.
    parameter [7:0] REFLECTION_CEILING = 8'd72
)(
    input             I_clk,
    input             I_rst_n,
    input             I_tlast,
    input             I_tuser,
    input      [95:0] I_tdata,
    input             I_tvalid,
    output reg  [7:0] O_luma_mean,
    output reg        O_frame_toggle,
    output reg [1:0]  O_highlight
);
    localparam integer IMG_WIDTH_GRP = IMG_WIDTH >> 2;
    // Keep the number of horizontal samples fixed at 32 for 720p and 600p.
    // The 128-group window is 512 pixels (128 groups × 4 pixels/group).
    localparam integer SAMPLE_WINDOW_GRP = 128;
    localparam integer X_START_GRP   = (IMG_WIDTH_GRP > SAMPLE_WINDOW_GRP) ?
                                       ((IMG_WIDTH_GRP - SAMPLE_WINDOW_GRP) >> 1) : 0;
    localparam integer X_END_GRP     = (IMG_WIDTH_GRP > SAMPLE_WINDOW_GRP) ?
                                       (X_START_GRP + SAMPLE_WINDOW_GRP) : IMG_WIDTH_GRP;
    localparam integer SAMPLE_LINES  = 32;
    localparam integer Y_STRIDE      = 16;
    localparam integer Y_MARGIN      = (IMG_HEIGHT - SAMPLE_LINES * Y_STRIDE) / 2;
    localparam [3:0]   Y_PHASE       = Y_MARGIN % Y_STRIDE;

    reg [9:0]  x_grp;
    reg [9:0]  y_line;
    reg [10:0] sample_count;
    reg [17:0] luma_sum;

    wire [23:0] sample_pixel = I_tdata[95:72];
    wire [9:0] sample_gray_sum = {2'b00, sample_pixel[23:16]} +
                                 {1'b0, sample_pixel[15:8], 1'b0} +
                                 {2'b00, sample_pixel[7:0]};
    wire [7:0] sample_luma = sample_gray_sum[9:2];
    // Winsorized metering only: bright window pixels have bounded influence
    // on centre statistics. Display RGB and upper-tail counts stay untouched.
    wire [7:0] metered_luma=(REFLECTION_TOLERANT!=0 && sample_luma>REFLECTION_CEILING)?REFLECTION_CEILING:sample_luma;

    wire in_centre_grid = (x_grp >= X_START_GRP) &&
                          (x_grp <  X_END_GRP) &&
                          (x_grp[1:0] == 2'b00) &&
                          (y_line >= Y_MARGIN) &&
                          (y_line <  Y_MARGIN + SAMPLE_LINES * Y_STRIDE) &&
                          (y_line[3:0] == Y_PHASE);

    // Three cumulative upper-tail bins approximate percentile constraints.
    // 32x32 dispersed samples cover the image, not just the dark centre.
    localparam integer GX_STEP=(IMG_WIDTH_GRP>=32)?IMG_WIDTH_GRP/32:1;
    localparam integer GY_STEP=(IMG_HEIGHT>=32)?IMG_HEIGHT/32:1;
    reg [9:0] next_x,next_y;
    reg [10:0] global_count;
    localparam integer HCW=(REFLECTION_TOLERANT!=0)?8:5;
    reg [HCW-1:0] warm_count,hot_count,clip_count;
    wire global_sample=(x_grp==next_x)&&(y_line==next_y)&&(global_count<1024);
    wire warm_pixel=(sample_pixel[23:16]>=192)||(sample_pixel[15:8]>=192)||(sample_pixel[7:0]>=192);
    wire hot_pixel=(sample_pixel[23:16]>=224)||(sample_pixel[15:8]>=224)||(sample_pixel[7:0]>=224);
    wire clip_pixel=(sample_pixel[23:16]>=240)||(sample_pixel[15:8]>=240)||(sample_pixel[7:0]>=240);
    always @(posedge I_clk or negedge I_rst_n)begin
      if(!I_rst_n)begin
        next_x<=GX_STEP/2;next_y<=GY_STEP/2;global_count<=0;
        warm_count<=0;hot_count<=0;clip_count<=0;O_highlight<=0;
      end else if(HIGHLIGHT_ENABLE!=0 && I_tvalid)begin
        if(I_tuser)begin
          if(sample_count==1024 && global_count==1024)
            O_highlight<=(REFLECTION_TOLERANT!=0) ?
                ((clip_count>=128 || hot_count>=192)?2'd3:
                 (clip_count>=64 || hot_count>=96)?2'd2:
                 (hot_count>=64 || warm_count>=128)?2'd1:2'd0) :
                (clip_count>=8)?2'd3:(hot_count>=8)?2'd2:
                ((warm_count>=16)||(hot_count>=4))?2'd1:2'd0;
          next_x<=GX_STEP/2;next_y<=GY_STEP/2;global_count<=0;
          warm_count<=0;hot_count<=0;clip_count<=0;
        end else begin
          if(global_sample)begin
            global_count<=global_count+1'b1;next_x<=next_x+GX_STEP;
            if(warm_pixel && warm_count!={HCW{1'b1}})warm_count<=warm_count+1'b1;
            if(hot_pixel && hot_count!={HCW{1'b1}})hot_count<=hot_count+1'b1;
            if(clip_pixel && clip_count!={HCW{1'b1}})clip_count<=clip_count+1'b1;
          end
          if(I_tlast)begin
            next_x<=GX_STEP/2;
            if(y_line==next_y)next_y<=next_y+GY_STEP;
          end
        end
      end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            x_grp          <= 10'd0;
            y_line         <= 10'd0;
            sample_count   <= 11'd0;
            luma_sum       <= 18'd0;
            O_luma_mean    <= 8'd0;
            O_frame_toggle <= 1'b0;
        end else if (I_tvalid) begin
            if (I_tuser) begin
                // Publish the completed previous frame.  The value then stays
                // stable for a full frame, which permits a low-cost bundled
                // data CDC together with O_frame_toggle.
                if (sample_count == 11'd1024) begin
                    O_luma_mean    <= luma_sum[17:10];
                    O_frame_toggle <= ~O_frame_toggle;
                end

                sample_count <= 11'd0;
                luma_sum     <= 18'd0;
                x_grp        <= 10'd1; // tuser is carried by group zero
                y_line       <= 10'd0;
            end else begin
                if (in_centre_grid && (sample_count < 11'd1024)) begin
                    sample_count <= sample_count + 1'b1;
                    luma_sum     <= luma_sum + metered_luma;
                end

                if (I_tlast) begin
                    x_grp <= 10'd0;
                    if (y_line == IMG_HEIGHT - 1)
                        y_line <= 10'd0;
                    else
                        y_line <= y_line + 1'b1;
                end else begin
                    x_grp <= x_grp + 1'b1;
                end
            end
        end
    end
endmodule
