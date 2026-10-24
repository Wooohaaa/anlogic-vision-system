// Robust frame-updated AWB with one shared iterative divider.
//
// The input is four packed RGB888 pixels per 96-bit beat. A saturation-limited
// gray-world estimator collects non-clipped, mid-brightness, low-chroma
// pixels. G/R and G/B ratios are then computed sequentially with one 48-step
// restoring divider. Low-confidence frames hold the previous gains; valid
// estimates are clamped, smoothed, and committed only at a later frame start.
// Bootstrap uses a wider raw candidate gate; tracking checks corrected colors.
// Two or more populated, agreeing quadrants and three stable estimates gate updates.
// Near-neutral estimates target unity so low-light noise does not keep a cast
// alive or drive small frame-to-frame color changes.
//
// The official compact line delay is retained to preserve the existing FIFO
// reset lead and video latency. tuser intentionally remains an early marker;
// delayed valid/data and the derived line-end marker stay aligned.
module ua_awb_frame #(
    parameter integer IMG_HEIGHT = 720,
    parameter integer IMG_WIDTH  = 1280,
    parameter integer OUTPUT_CHANNEL_BITS = 8,
    parameter integer RUNTIME_CONTROL = 0
) (
    input                   I_clk,
    input                   I_rst_n,
    input                   I_tlast,
    input                   I_tuser,
    input      [95:0]       I_tdata,
    input                   I_tvalid,
    output                  I_tready,
    output                  O_tlast,
    output                  O_tuser,
    output     [12*OUTPUT_CHANNEL_BITS-1:0] O_tdata,
    output                  O_tvalid,
    input                   O_tready,
    input                   I_enable,
    output [10:0]           O_status
);
    localparam integer LINE_COUNT_W = (IMG_HEIGHT <= 1) ? 1 : $clog2(IMG_HEIGHT);
    localparam [LINE_COUNT_W-1:0] LAST_LINE = IMG_HEIGHT - 1;
    localparam integer AWB_FRAME_PIXELS = IMG_WIDTH * IMG_HEIGHT;
    localparam integer AWB_ESTIMATOR_PIXELS = (AWB_FRAME_PIXELS / 4);
    // At most one 8-bit channel per beat. Bound accumulators by a legal frame,
    // rather than carrying unused high bits through every statistics mux.
    localparam integer SUM_W = (AWB_ESTIMATOR_PIXELS < 1) ? 8 :
        $clog2(AWB_ESTIMATOR_PIXELS * 255 + 1);
    // Calculation takes 96 divider cycles plus launch/decision. Larger frames
    // cannot overlap calculations even with no blanking; tiny tests retain it.
    localparam integer ALLOW_SHORT_FRAME_QUEUE = (AWB_ESTIMATOR_PIXELS <= 100);
    localparam integer SAMPLE_COUNT_W =
        (AWB_ESTIMATOR_PIXELS < 4) ? 3 : $clog2(AWB_ESTIMATOR_PIXELS + 1);
    localparam integer MIN_AWB_SAMPLES_INT =
        (AWB_ESTIMATOR_PIXELS < 16) ? AWB_ESTIMATOR_PIXELS :
        ((AWB_ESTIMATOR_PIXELS / 256) > 16 ?
         (AWB_ESTIMATOR_PIXELS / 256) : 16);
    localparam [SAMPLE_COUNT_W-1:0] MIN_AWB_SAMPLES = MIN_AWB_SAMPLES_INT;
    localparam integer LINE_BEATS = IMG_WIDTH / 4;
    localparam integer X_COUNT_W = (LINE_BEATS <= 1) ? 1 : $clog2(LINE_BEATS);
    localparam integer REGION_MAX_SAMPLES = ((IMG_HEIGHT+1)/2)*((LINE_BEATS+1)/2);
    localparam integer REGION_COUNT_W = (REGION_MAX_SAMPLES < 2) ? 1 : $clog2(REGION_MAX_SAMPLES+1);
    localparam integer REGION_MIN_INT = (AWB_ESTIMATOR_PIXELS < 64) ? 1 :
        ((AWB_ESTIMATOR_PIXELS / 512) > 4 ? AWB_ESTIMATOR_PIXELS / 512 : 4);
    localparam [REGION_COUNT_W-1:0] REGION_MIN = REGION_MIN_INT;

    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_DIV_R = 2'd1;
    localparam [1:0] ST_DIV_B = 2'd2;
    localparam [1:0] ST_DECIDE = 2'd3;

    reg [LINE_COUNT_W-1:0] line_index;
    reg [SUM_W-1:0] sum_r;
    reg [SUM_W-1:0] sum_g;
    reg [SUM_W-1:0] sum_b;
    reg [SAMPLE_COUNT_W-1:0] sample_count;
    reg [1:0] sample_lane_index;
    reg [X_COUNT_W-1:0] sample_x;
    reg [REGION_COUNT_W-1:0] region_count [0:3];
    reg signed [REGION_COUNT_W:0] region_red_vote [0:3];
    reg signed [REGION_COUNT_W:0] region_blue_vote [0:3];
    // A vote is only a chromatic-direction confidence check, not a second AWB.
    // Four quadrants share the existing ratio divider and RGB scaling path.
    wire [1:0] sample_region = {
        !I_tuser && (line_index >= (IMG_HEIGHT+1)/2),
        !I_tuser && (sample_x >= (LINE_BEATS+1)/2)};
    wire signed [1:0] sample_red_vote;
    wire signed [1:0] sample_blue_vote;
    wire [1:0] region_red_direction [0:3];
    wire [1:0] region_blue_direction [0:3];
    genvar region_idx;
    generate for (region_idx=0;region_idx<4;region_idx=region_idx+1) begin : gen_region_confidence
        assign region_red_direction[region_idx] =
            F_vote_direction(region_red_vote[region_idx],region_count[region_idx]);
        assign region_blue_direction[region_idx] =
            F_vote_direction(region_blue_vote[region_idx],region_count[region_idx]);
    end endgenerate
    wire [3:0] region_populated;
    generate for (region_idx=0;region_idx<4;region_idx=region_idx+1) begin : gen_region_coverage
        assign region_populated[region_idx] = region_count[region_idx]>=REGION_MIN;
    end endgenerate
    wire [1:0] anchor_red = region_populated[0] ? region_red_direction[0] :
                            region_populated[1] ? region_red_direction[1] :
                            region_populated[2] ? region_red_direction[2] : region_red_direction[3];
    wire [1:0] anchor_blue = region_populated[0] ? region_blue_direction[0] :
                             region_populated[1] ? region_blue_direction[1] :
                             region_populated[2] ? region_blue_direction[2] : region_blue_direction[3];
    wire two_regions = (region_populated[0] && region_populated[1]) ||
                       (region_populated[0] && region_populated[2]) ||
                       (region_populated[0] && region_populated[3]) ||
                       (region_populated[1] && region_populated[2]) ||
                       (region_populated[1] && region_populated[3]) ||
                       (region_populated[2] && region_populated[3]);
    wire [3:0] region_agrees;
    generate for (region_idx=0;region_idx<4;region_idx=region_idx+1) begin : gen_region_agreement
        assign region_agrees[region_idx] = !region_populated[region_idx] ||
            ((region_red_direction[region_idx]==anchor_red) &&
             (region_blue_direction[region_idx]==anchor_blue));
    end endgenerate
    // Excludes the final beat from confidence only; ratio totals still include it.
    // Ignore genuinely empty quadrants, but every populated quadrant must agree.
    wire spatial_confident = (IMG_HEIGHT < 2 || LINE_BEATS < 2) ||
        (two_regions && (&region_agrees));
    wire [1:0] sample_lane = I_tuser ? 2'd0 : sample_lane_index;

    reg [19:0] gain_r;
    reg [19:0] gain_b;
    reg enable_meta, enable_sync, enabled;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin enable_meta<=1'b1;enable_sync<=1'b1;enabled<=1'b1;end
        else begin
            enable_meta<=I_enable;enable_sync<=enable_meta;
            if(I_tuser) enabled <= (RUNTIME_CONTROL == 0) ? 1'b1 : enable_sync;
        end
    end
    wire [19:0] applied_r = enabled ? gain_r : 20'h10000;
    wire [19:0] applied_b = enabled ? gain_b : 20'h10000;
    // Display in tenths, round half up; legal gains 0.5..2.0 -> 05..20.
    wire [23:0] display_r = ({4'd0,applied_r} << 3) + ({4'd0,applied_r} << 1) + 24'd32768;
    wire [23:0] display_b = ({4'd0,applied_b} << 3) + ({4'd0,applied_b} << 1) + 24'd32768;
    assign O_status = {enabled,display_r[20:16],display_b[20:16]};
    reg bootstrap_mode;
    reg [4:0] invalid_estimates;
    reg reacquire_pending;

    wire        line_delay_valid;
    wire [95:0] line_delay_data;
    wire        line_delay_user_unused;
    reg  [95:0] line_delay_data_r;
    reg         line_delay_valid_d1;
    reg         line_delay_valid_d2;
    reg  [12*OUTPUT_CHANNEL_BITS-1:0] scaled_data_r;

    reg [23:0] sampled_pixel_rgb;
    always @* begin
        case (sample_lane)
            2'd0: sampled_pixel_rgb = I_tdata[95:72];
            2'd1: sampled_pixel_rgb = I_tdata[71:48];
            2'd2: sampled_pixel_rgb = I_tdata[47:24];
            default: sampled_pixel_rgb = I_tdata[23:0];
        endcase
    end
    wire [23:0] corrected_sample_rgb = {
        F_scale_channel(sampled_pixel_rgb[23:16],gain_r),
        sampled_pixel_rgb[15:8],
        F_scale_channel(sampled_pixel_rgb[7:0],gain_b)};
    wire sample_pixel_use = F_awb_pixel_eligible(sampled_pixel_rgb) &&
        (bootstrap_mode || F_tracking_pixel_eligible(corrected_sample_rgb));
    wire [9:0] beat_r = sample_pixel_use ?
                        {2'b00,sampled_pixel_rgb[23:16]} : 10'd0;
    wire [9:0] beat_g = sample_pixel_use ?
                        {2'b00,sampled_pixel_rgb[15:8]} : 10'd0;
    wire [9:0] beat_b = sample_pixel_use ?
                        {2'b00,sampled_pixel_rgb[7:0]} : 10'd0;
    wire [2:0] beat_sample_count = sample_pixel_use ? 3'd1 : 3'd0;
    assign sample_red_vote =
        (beat_g > beat_r + (beat_g >> 5)) ? 2'sd1 :
        (beat_r > beat_g + (beat_r >> 5)) ? -2'sd1 : 2'sd0;
    assign sample_blue_vote =
        (beat_g > beat_b + (beat_g >> 5)) ? 2'sd1 :
        (beat_b > beat_g + (beat_b >> 5)) ? -2'sd1 : 2'sd0;

    wire [SUM_W-1:0] beat_r_ext = beat_r;
    wire [SUM_W-1:0] beat_g_ext = beat_g;
    wire [SUM_W-1:0] beat_b_ext = beat_b;
    wire [SAMPLE_COUNT_W-1:0] beat_sample_count_ext = beat_sample_count;
    wire [SUM_W-1:0] frame_total_r = I_tuser ? beat_r_ext : sum_r + beat_r_ext;
    wire [SUM_W-1:0] frame_total_g = I_tuser ? beat_g_ext : sum_g + beat_g_ext;
    wire [SUM_W-1:0] frame_total_b = I_tuser ? beat_b_ext : sum_b + beat_b_ext;
    wire [SAMPLE_COUNT_W-1:0] frame_total_sample_count = I_tuser ?
        beat_sample_count_ext : sample_count + beat_sample_count_ext;

    wire frame_end = I_tvalid && I_tlast &&
                     (I_tuser ? (IMG_HEIGHT <= 1) : (line_index == LAST_LINE));

    reg [19:0] pending_gain_r;
    reg [19:0] pending_gain_b;
    reg [19:0] calc_gain_r;
    reg [19:0] calc_gain_b;
    reg        pending_gain_valid;
    wire gains_settled = F_gain_bucket_close(gain_r,pending_gain_r) &&
                         F_gain_bucket_close(gain_b,pending_gain_b);
    // Both Q16 distances are evaluated after the divider, outside its
    // 48-bit subtract path. A total deviation below 1/8 is treated as
    // neutral; the frame IIR then eases previous gains back to unity.
    wire [19:0] pending_red_distance =
        (calc_gain_r >= 20'h10000) ?
        (calc_gain_r - 20'h10000) : (20'h10000 - calc_gain_r);
    wire [19:0] pending_blue_distance =
        (calc_gain_b >= 20'h10000) ?
        (calc_gain_b - 20'h10000) : (20'h10000 - calc_gain_b);
    wire pending_near_neutral =
        ({1'b0,pending_red_distance} + {1'b0,pending_blue_distance}) < 21'h02000;

    reg [1:0]  div_state;
    reg [47:0] div_numerator;
    reg [47:0] div_quotient;
    reg [32:0] div_remainder;
    reg [31:0] div_denominator;
    reg [5:0]  div_bit_index;
    reg [31:0] calc_sum_g;
    reg [31:0] calc_sum_b;

    reg [SUM_W-1:0] queued_sum_r;
    reg [SUM_W-1:0] queued_sum_g;
    reg [SUM_W-1:0] queued_sum_b;
    reg [SAMPLE_COUNT_W-1:0] queued_sample_count;
    reg        queued_stats_valid;
    reg        queued_spatial_confident;
    reg [19:0] confirmed_target_r, confirmed_target_b;
    reg [1:0] stable_estimates;
    wire [19:0] target_r = pending_near_neutral ? 20'h10000 : calc_gain_r;
    wire [19:0] target_b = pending_near_neutral ? 20'h10000 : calc_gain_b;
    wire signed [20:0] target_delta_r = $signed({1'b0,target_r}) - $signed({1'b0,confirmed_target_r});
    wire signed [20:0] target_delta_b = $signed({1'b0,target_b}) - $signed({1'b0,confirmed_target_b});
    wire target_close = (target_delta_r >= -21'sd4096) && (target_delta_r <= 21'sd4096) &&
                        (target_delta_b >= -21'sd4096) && (target_delta_b <= 21'sd4096);

    wire [SUM_W-1:0] launch_sum_r = queued_stats_valid ? queued_sum_r : frame_total_r;
    wire [SUM_W-1:0] launch_sum_g = queued_stats_valid ? queued_sum_g : frame_total_g;
    wire [SUM_W-1:0] launch_sum_b = queued_stats_valid ? queued_sum_b : frame_total_b;
    wire [SAMPLE_COUNT_W-1:0] launch_sample_count = queued_stats_valid ?
        queued_sample_count : frame_total_sample_count;
    wire have_stats = queued_stats_valid || frame_end;

wire [32:0] div_remainder_shift = {div_remainder[31:0],div_numerator[47]};
wire [32:0] div_sub_result = div_remainder_shift - {1'b0,div_denominator};
wire        div_subtract = !div_sub_result[32];
wire [32:0] div_remainder_next = div_subtract ? div_sub_result
                                              : div_remainder_shift;
    wire [47:0] div_quotient_next = {div_quotient[46:0],div_subtract};

    // Saturation-limited gray-world sample selection. One lane is sampled per
    // beat and the lane rotates through all four packed pixels, reducing the
    // per-pixel compare hardware without biasing a single CFA x-phase. Ignore
    // saturated colors, dark noise, and clipped highlights. A 1/2 raw chroma
    // gate admits a gray surface with up to 2x channel imbalance at bootstrap.
    // Once settled, corrected-color tracking additionally rejects colored objects.
    function F_awb_pixel_eligible;
        input [23:0] pixel_rgb;
        reg [7:0] r_value;
        reg [7:0] g_value;
        reg [7:0] b_value;
        reg [7:0] max_value;
        reg [7:0] min_value;
        begin
            r_value = pixel_rgb[23:16];
            g_value = pixel_rgb[15:8];
            b_value = pixel_rgb[7:0];
            max_value = r_value;
            if (g_value > max_value) max_value = g_value;
            if (b_value > max_value) max_value = b_value;
            min_value = r_value;
            if (g_value < min_value) min_value = g_value;
            if (b_value < min_value) min_value = b_value;

            F_awb_pixel_eligible = (max_value >= 8'd32) &&
                                   (max_value <= 8'd224) && (min_value >= 8'd16) &&
                                   ((max_value - min_value) <= (max_value >> 1));
        end
    endfunction

    // Channel ratios around green after applying the current gains. Raw sums
    // remain uncorrected, so ratios are absolute gains, not recursively compounded.
    function F_tracking_pixel_eligible;
        input [23:0] pixel_rgb;
        reg [8:0] low_bound,high_bound;
        begin
            low_bound = {1'b0,pixel_rgb[15:8]} - {3'b0,pixel_rgb[15:10]};
            high_bound = {1'b0,pixel_rgb[15:8]} + {3'b0,pixel_rgb[15:10]};
            F_tracking_pixel_eligible =
                ({1'b0,pixel_rgb[23:16]}>=low_bound) && ({1'b0,pixel_rgb[23:16]}<=high_bound) &&
                ({1'b0,pixel_rgb[7:0]}>=low_bound) && ({1'b0,pixel_rgb[7:0]}<=high_bound) &&
                (pixel_rgb[23:16]<8'd248) && (pixel_rgb[7:0]<8'd248);
        end
    endfunction

    // Same or adjacent 1/16-gain buckets: error <1/8, small enough to enter the
    // corrected-color tracking gate. Avoid equality-only lock at exact 2.0/unity.
    function F_gain_bucket_close;
        input [19:0] current_gain,target_gain;
        reg [5:0] c,t;
        begin
            c=current_gain[17:12];t=target_gain[17:12];
            F_gain_bucket_close = (c==t) || ({1'b0,c}+7'd1=={1'b0,t}) ||
                                  ({1'b0,t}+7'd1=={1'b0,c});
        end
    endfunction

    // Prevent an abnormal frame from producing extreme channel gains.
    function [19:0] F_limit_gain;
        input [47:0] quotient;
        begin
            if (quotient > 48'h000000020000)
                F_limit_gain = 20'h20000; // 2.0 in Q16 (v8 range)
            else if (quotient < 48'h000000008000)
                F_limit_gain = 20'h08000; // 0.5 in Q16
            else
                F_limit_gain = {2'b0,quotient[17:0]};
        end
    endfunction

    // 1/8 temporal IIR update suppresses frame-to-frame color pumping.
    function [19:0] F_smooth_gain;
        input [19:0] current_gain;
        input [19:0] target_gain;
        reg signed [18:0] delta;
        reg signed [18:0] step;
        reg signed [18:0] next_gain;
        begin
            // Both operands are initialized to unity and are bounded by
            // F_limit_gain. floor((target-current)/8) keeps next between them,
            // so the former second clamp is unreachable on legal state.
            delta = $signed({1'b0,target_gain[17:0]}) - $signed({1'b0,current_gain[17:0]});
            step = delta >>> 3;
            next_gain = $signed({1'b0,current_gain[17:0]}) + step;
            F_smooth_gain = {2'b0,next_gain[17:0]};
        end
    endfunction

    // |vote| > count/4 is exactly the original pair of signed comparisons,
    // but shares the magnitude comparator and removes threshold negation.
    function [1:0] F_vote_direction;
        input signed [REGION_COUNT_W:0] vote;
        input [REGION_COUNT_W-1:0] count;
        reg [REGION_COUNT_W:0] magnitude;
        begin
            // For a negative vote, -vote=(~vote)+1. Append the sign as the
            // comparator's low bit instead of building eight negation adders.
            // Positive: m>t; negative: (~vote)>=t, exactly abs(vote)>t.
            magnitude = vote ^ {(REGION_COUNT_W+1){vote[REGION_COUNT_W]}};
            F_vote_direction = ({magnitude,vote[REGION_COUNT_W]} > {1'b0,(count >> 2),1'b0}) ?
                (vote[REGION_COUNT_W] ? 2'd2 : 2'd1) : 2'd0;
        end
    endfunction

    function [7:0] F_scale_channel;
        input [7:0]  channel;
        input [19:0] gain;
        reg [27:0] product;
        begin
            product = {8'd0,gain} * {20'd0,channel};
            if (|product[27:24])
                F_scale_channel = 8'hff;
            else
                F_scale_channel = product[23:16];
        end
    endfunction

    // Wide production output retains the complete legal 0..510 gain product.
    // The estimator still uses its original 8-bit corrected candidate gate.
    function [OUTPUT_CHANNEL_BITS-1:0] F_output_channel;
        input [7:0] channel;
        input [19:0] gain;
        reg [27:0] product;
        begin
            product={8'd0,gain}*{20'd0,channel};
            if(OUTPUT_CHANNEL_BITS==9) F_output_channel=product[24:16];
            else F_output_channel=(|product[27:24])?8'hff:product[23:16];
        end
    endfunction

    assign I_tready = O_tready;
    assign O_tuser  = I_tuser;

    // Keep the established 50-beat line-delay path. Besides preserving the
    // frame-start reset margin at the DDR/video boundary, this keeps all
    // existing downstream alignment unchanged while the divider is replaced.
    signal_delay #(
        .IMG_HEIGHT(IMG_HEIGHT),
        .IMG_WIDTH(IMG_WIDTH),
        .DATA_WIDTH(96),
        .DELAY_CYCLE(50)
    ) u_awb_line_delay (
        .I_clk(I_clk),
        .I_rst_n(I_rst_n),
        .I_tuser(I_tuser),
        .I_valid(I_tvalid),
        .I_data(I_tdata),
        .O_valid(line_delay_valid),
        .O_data(line_delay_data),
        .O_tuser(line_delay_user_unused)
    );

    // Accumulate eligible gray-world samples. tuser may precede the first valid
    // beat; clearing on the marker supports both early-marker and same-cycle streams.
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sum_r <= 32'd0;
            sum_g <= 32'd0;
            sum_b <= 32'd0;
            sample_count <= {SAMPLE_COUNT_W{1'b0}};
        end else if (I_tuser) begin
            if (I_tvalid) begin
                sum_r <= beat_r_ext;
                sum_g <= beat_g_ext;
                sum_b <= beat_b_ext;
                sample_count <= beat_sample_count_ext;
            end else begin
                sum_r <= 32'd0;
                sum_g <= 32'd0;
                sum_b <= 32'd0;
                sample_count <= {SAMPLE_COUNT_W{1'b0}};
            end
        end else if (I_tvalid) begin
            sum_r <= sum_r + beat_r_ext;
            sum_g <= sum_g + beat_g_ext;
            sum_b <= sum_b + beat_b_ext;
            sample_count <= sample_count + beat_sample_count_ext;
        end
    end

    // Rotate the statistics tap across the four packed pixels. One sample per
    // 96-bit beat keeps the estimator lightweight and still visits every lane.
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)
            sample_lane_index <= 2'd0;
        else if (I_tuser)
            sample_lane_index <= 2'd0;
        else if (I_tvalid)
            sample_lane_index <= sample_lane_index + 1'b1;
    end

    integer region_reset_idx;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sample_x <= 0;
            for (region_reset_idx=0;region_reset_idx<4;region_reset_idx=region_reset_idx+1) begin
                region_count[region_reset_idx] <= 0;
                region_red_vote[region_reset_idx] <= 0;
                region_blue_vote[region_reset_idx] <= 0;
            end
        end else if (I_tuser) begin
            sample_x <= (I_tvalid && !I_tlast) ? 1 : 0;
            for (region_reset_idx=0;region_reset_idx<4;region_reset_idx=region_reset_idx+1) begin
                region_count[region_reset_idx] <=
                    (region_reset_idx==0 && I_tvalid && sample_pixel_use) ? 1 : 0;
                region_red_vote[region_reset_idx] <=
                    (region_reset_idx==0 && I_tvalid && sample_pixel_use) ? sample_red_vote : 2'sd0;
                region_blue_vote[region_reset_idx] <=
                    (region_reset_idx==0 && I_tvalid && sample_pixel_use) ? sample_blue_vote : 2'sd0;
            end
        end else if (I_tvalid) begin
            sample_x <= I_tlast ? 0 : sample_x + 1'b1;
            if (sample_pixel_use) begin
                region_count[sample_region] <= region_count[sample_region] + 1'b1;
                region_red_vote[sample_region] <= region_red_vote[sample_region] +
                    {{(REGION_COUNT_W-1){sample_red_vote[1]}},sample_red_vote};
                region_blue_vote[sample_region] <= region_blue_vote[sample_region] +
                    {{(REGION_COUNT_W-1){sample_blue_vote[1]}},sample_blue_vote};
            end
        end
    end

    // Count line-end markers to distinguish tlast (line end) from frame end.
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            line_index <= {LINE_COUNT_W{1'b0}};
        end else begin
            if (I_tuser)
                line_index <= {LINE_COUNT_W{1'b0}};
            if (I_tvalid && I_tlast) begin
                if (I_tuser) begin
                    if (IMG_HEIGHT <= 1)
                        line_index <= {LINE_COUNT_W{1'b0}};
                    else
                        line_index <= {{(LINE_COUNT_W-1){1'b0}},1'b1};
                end else if (line_index == LAST_LINE) begin
                    line_index <= {LINE_COUNT_W{1'b0}};
                end else begin
                    line_index <= line_index + 1'b1;
                end
            end
        end
    end

    // The shared restoring divider has one 48-bit numerator path and is used
    // first for G/R, then for G/B. At 1280x720 there are 230400 stream beats
    // per frame, so the 96 divider cycles are comfortably amortized per frame.
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            gain_r               <= 20'h10000;
            gain_b               <= 20'h10000;
            pending_gain_r       <= 20'h10000;
            pending_gain_b       <= 20'h10000;
            calc_gain_r          <= 20'h10000;
            calc_gain_b          <= 20'h10000;
            pending_gain_valid   <= 1'b0;
            div_state            <= ST_IDLE;
            div_numerator        <= 48'd0;
            div_quotient         <= 48'd0;
            div_remainder        <= 33'd0;
            div_denominator      <= 32'd0;
            div_bit_index        <= 6'd0;
            calc_sum_g           <= 32'd0;
            calc_sum_b           <= 32'd0;
            queued_sum_r         <= 32'd0;
            queued_sum_g         <= 32'd0;
            queued_sum_b         <= 32'd0;
            queued_sample_count  <= {SAMPLE_COUNT_W{1'b0}};
            queued_stats_valid  <= 1'b0;
            queued_spatial_confident <= 1'b0;
            confirmed_target_r <= 20'h10000;
            confirmed_target_b <= 20'h10000;
            stable_estimates <= 0;
            bootstrap_mode <= 1'b1;
            invalid_estimates <= 0;
            reacquire_pending <= 1'b0;
        end else begin
            // Change the candidate policy only at frame boundaries, never in
            // the middle of statistics. No first frame is stored or subtracted.
            if (I_tuser) begin
                if (reacquire_pending) begin
                    bootstrap_mode <= 1'b1;
                    reacquire_pending <= 1'b0;
                end else if (pending_gain_valid && gains_settled) begin
                    bootstrap_mode <= 1'b0;
                end
            end
            // Commit a complete pair of candidate gains only at frame start.
            if (I_tuser && pending_gain_valid) begin
                gain_r             <= F_smooth_gain(gain_r,pending_gain_r);
                gain_b             <= F_smooth_gain(gain_b,pending_gain_b);
                pending_gain_valid <= 1'b0;
            end

            // If a very short frame arrives during the 96-cycle calculation,
            // retain the newest completed totals and process them when idle.
            if (ALLOW_SHORT_FRAME_QUEUE && frame_end && (div_state != ST_IDLE || queued_stats_valid)) begin
                queued_sum_r        <= frame_total_r;
                queued_sum_g        <= frame_total_g;
                queued_sum_b        <= frame_total_b;
                queued_sample_count <= frame_total_sample_count;
                queued_spatial_confident <= spatial_confident;
                queued_stats_valid <= 1'b1;
            end

            case (div_state)
                ST_IDLE: begin
                    if (have_stats) begin
                        if (queued_stats_valid && !frame_end)
                            queued_stats_valid <= 1'b0;

                        if (launch_sample_count >= MIN_AWB_SAMPLES &&
                            (queued_stats_valid ? queued_spatial_confident : spatial_confident)) begin
                            invalid_estimates <= 0;
                            calc_sum_g <= launch_sum_g;
                            calc_sum_b <= launch_sum_b;

                            if ((launch_sum_r == 32'd0) ||
                                (launch_sum_g == 32'd0) ||
                                (launch_sum_b == 32'd0)) begin
                                // Invalid channel statistics are not a color cast.
                                // Hold the last stable estimate instead of adapting.
                                div_state <= ST_IDLE;
                                stable_estimates <= 0;
                            end else begin
                                div_numerator   <= {launch_sum_g,16'd0};
                                div_quotient    <= 48'd0;
                                div_remainder   <= 33'd0;
                                div_denominator <= launch_sum_r;
                                div_bit_index   <= 6'd47;
                                div_state       <= ST_DIV_R;
                            end
                        end else begin
                            stable_estimates <= 0;
                            if (invalid_estimates<16) invalid_estimates <= invalid_estimates+1'b1;
                            if (invalid_estimates>=15) reacquire_pending <= 1'b1;
                        end
                    end
                end

                ST_DIV_R: begin
                    div_numerator  <= {div_numerator[46:0],1'b0};
                    div_remainder  <= div_remainder_next;
                    div_quotient   <= div_quotient_next;
                    if (div_bit_index == 6'd0) begin
                        calc_gain_r <= F_limit_gain(div_quotient_next);
                        if (calc_sum_b == 32'd0) begin
                            pending_gain_r     <= F_limit_gain(div_quotient_next);
                            pending_gain_b     <= gain_b;
                            pending_gain_valid <= 1'b1;
                            div_state          <= ST_IDLE;
                        end else begin
                            div_numerator   <= {calc_sum_g,16'd0};
                            div_quotient    <= 48'd0;
                            div_remainder   <= 33'd0;
                            div_denominator <= calc_sum_b;
                            div_bit_index   <= 6'd47;
                            div_state       <= ST_DIV_B;
                        end
                    end else begin
                        div_bit_index <= div_bit_index - 1'b1;
                    end
                end

                ST_DIV_B: begin
                    div_numerator <= {div_numerator[46:0],1'b0};
                    div_remainder <= div_remainder_next;
                    div_quotient  <= div_quotient_next;
                    if (div_bit_index == 6'd0) begin
                        calc_gain_b        <= F_limit_gain(div_quotient_next);
                        div_state          <= ST_DECIDE;
                    end else begin
                        div_bit_index <= div_bit_index - 1'b1;
                    end
                end

                ST_DECIDE: begin
                    if (stable_estimates!=0 && target_close) begin
                        if (stable_estimates < 3) stable_estimates <= stable_estimates+1'b1;
                        if (stable_estimates >= 2) begin
                            pending_gain_r <= target_r;
                            pending_gain_b <= target_b;
                            pending_gain_valid <= 1'b1;
                        end
                    end else begin
                        stable_estimates <= 1;
                    end
                    confirmed_target_r <= target_r;
                    confirmed_target_b <= target_b;
                    div_state <= ST_IDLE;
                end

                default: div_state <= ST_IDLE;
            endcase
        end
    end

    // Match the existing AWB's two-cycle post-RAM pipeline. O_tlast marks the
    // final valid beat when the delayed stream drops between lines.
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            line_delay_data_r  <= 96'd0;
            line_delay_valid_d1 <= 1'b0;
            line_delay_valid_d2 <= 1'b0;
            scaled_data_r       <= 96'd0;
        end else begin
            line_delay_data_r   <= line_delay_data;
            line_delay_valid_d1 <= line_delay_valid;
            line_delay_valid_d2 <= line_delay_valid_d1;
            if (line_delay_valid_d1) begin
                scaled_data_r <= {
                    F_output_channel(line_delay_data_r[95:88],applied_r),
                    {{(OUTPUT_CHANNEL_BITS-8){1'b0}},line_delay_data_r[87:80]},
                    F_output_channel(line_delay_data_r[79:72],applied_b),
                    F_output_channel(line_delay_data_r[71:64],applied_r),
                    {{(OUTPUT_CHANNEL_BITS-8){1'b0}},line_delay_data_r[63:56]},
                    F_output_channel(line_delay_data_r[55:48],applied_b),
                    F_output_channel(line_delay_data_r[47:40],applied_r),
                    {{(OUTPUT_CHANNEL_BITS-8){1'b0}},line_delay_data_r[39:32]},
                    F_output_channel(line_delay_data_r[31:24],applied_b),
                    F_output_channel(line_delay_data_r[23:16],applied_r),
                    {{(OUTPUT_CHANNEL_BITS-8){1'b0}},line_delay_data_r[15:8]},
                    F_output_channel(line_delay_data_r[7:0],applied_b)
                };
            end else begin
                scaled_data_r <= 96'd0;
            end
        end
    end

    assign O_tvalid = line_delay_valid_d2;
    assign O_tlast  = (line_delay_valid_d1 == 1'b0) &&
                      (line_delay_valid_d2 == 1'b1);
    assign O_tdata  = O_tvalid ? scaled_data_r : 96'd0;
endmodule
