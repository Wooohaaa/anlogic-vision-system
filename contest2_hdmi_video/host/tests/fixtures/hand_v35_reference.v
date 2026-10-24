// Gesture classifier using warm-color candidates. In DYNAMIC_ROI mode, a
// full-frame locator moves the profile window; production may disable motion
// gating so startup does not require an empty/background reference frame.
// IDs: 0=none, 1=fist, 2=point, 3=open. Two-tip shapes are rejected.
`timescale 1ns/1ps
module hand_v35_reference #(
    parameter integer IMG_WIDTH = 1280,
    parameter integer IMG_HEIGHT = 720,
    parameter integer ROI_X0_GRP = (IMG_WIDTH * 3) / 32,
    parameter integer ROI_X1_GRP = (IMG_WIDTH * 3) / 16 - 1,
    parameter integer ROI_Y0 = IMG_HEIGHT / 4,
    parameter integer ROI_Y1 = (IMG_HEIGHT * 3) / 4 - 1,
    parameter integer MIN_AREA = 200,
    parameter integer MAX_AREA = 7000,
    parameter integer DYNAMIC_ROI = 0,
    parameter integer LOC_MIN_AREA = 40,
    parameter integer SAMPLE_STEP = 2,
    // 0: classify warm-color candidates directly, without first-frame motion/background.
    // 1: retain legacy motion-gated behavior for standalone compatibility.
    parameter integer MOTION_GATE_ENABLE = 1,
    parameter integer TEMPORAL_RECOVERY = 1
)(
    input wire I_clk, I_rst_n, I_clear,
    input wire I_sample_valid, I_motion_hit,
    input wire [9:0] I_x_grp, I_y,
    input wire [95:0] I_rgb,
    input wire I_frame_done,
    output reg O_result_valid,
    output reg [1:0] O_id,
    output reg [2:0] O_tip_count,
    output reg O_box_valid,
    output reg [9:0] O_box_xmin, O_box_xmax, O_box_ymin, O_box_ymax
);
    localparam integer ROI_W = ROI_X1_GRP - ROI_X0_GRP + 1;
    localparam integer ROI_H = ROI_Y1 - ROI_Y0 + 1;
    localparam integer IMG_W_GRP = IMG_WIDTH / 4;
    localparam integer MAX_X0 = IMG_W_GRP - ROI_W;
    localparam integer MAX_Y0 = IMG_HEIGHT - ROI_H;
    localparam integer HIST_BINS = (IMG_HEIGHT + 15) / 16;
    // Eight 128-line bands in product geometry; use 32-line bands for the
    // 180-line reduced replay so both rasters map to the same source regions.
    localparam integer LOC_BIN_SHIFT = (IMG_HEIGHT >= 512) ? 7 : 5;
    localparam integer LOC_BIN_COUNT =
        (IMG_HEIGHT + (1 << LOC_BIN_SHIFT) - 1) >> LOC_BIN_SHIFT;
    localparam integer CLEAR_COUNT = (ROI_W > HIST_BINS) ? ROI_W : HIST_BINS;
    localparam integer SAMPLE_PHASE = (IMG_HEIGHT - 1) % SAMPLE_STEP;
    localparam integer OPEN_ROWS_MIN = (IMG_HEIGHT >= 512) ? 20 : 5;
    // A dim hand's finger runs can break for a few rows. Keep the close-triplet
    // requirement and profile occupancy guard, rather than compensating with
    // an unrestricted broad skin-color gate.
    localparam integer OPEN_THREE_ROWS_MIN = (IMG_HEIGHT >= 512) ? 36 : 10;
    localparam integer DIM_OPEN_THREE_ROWS_MIN = (IMG_HEIGHT >= 512) ? 32 : 8;
    localparam integer OPEN_CLOSE_ROWS_MIN = (IMG_HEIGHT >= 512) ? 24 : 3;
    localparam integer OPEN_RUN_MIN = (IMG_HEIGHT >= 512) ? 10 : 3;
    // Thin digits must not inflate the legacy full-frame OPEN run counters.
    localparam integer FINGER_RUN_MIN = (IMG_HEIGHT >= 512) ? 4 : 3;
    localparam integer OPEN_SPAN_MAX = IMG_W_GRP * 7 / 16;
    localparam [2:0] CAPTURE=0, GUARD=1, HIST=2, PROFILE=3, CLEAR=4,
                     SHOULDER=5, COMMIT=6;
    localparam [1:0] NONE=0, FIST=1, POINT=2, OPEN=3;

    wire [9:0] rs = {2'b0,I_rgb[95:88]} + {2'b0,I_rgb[71:64]} +
                    {2'b0,I_rgb[47:40]} + {2'b0,I_rgb[23:16]};
    wire [9:0] gs = {2'b0,I_rgb[87:80]} + {2'b0,I_rgb[63:56]} +
                    {2'b0,I_rgb[39:32]} + {2'b0,I_rgb[15:8]};
    wire [9:0] bs = {2'b0,I_rgb[79:72]} + {2'b0,I_rgb[55:48]} +
                    {2'b0,I_rgb[31:24]} + {2'b0,I_rgb[7:0]};
    // Background-free skin-color gate. Requiring the red/green/blue ordering
    // and a bounded red-vs-green excess rejects many beige/brick/gray regions
    // that passed the old broad warm-color test, while keeping a low absolute
    // level for the dim camera. Channel sums cover the same four-pixel group.
    wire [10:0] chroma_rg = {1'b0,rs} - {1'b0,gs};
    wire [10:0] chroma_gb = {1'b0,gs} - {1'b0,bs};
    wire warm = (rs >= 10'd96) &&
                ({1'b0,rs} >= {1'b0,gs} + 11'd16) &&
                ({1'b0,gs} >= {1'b0,bs} + 11'd16) &&
                (chroma_rg <= {chroma_gb[9:0],1'b0}) &&
                ({chroma_rg[9:0],1'b0} >= chroma_gb);
    // Broad chroma recovers the low-contrast silhouette; use stronger chroma
    // inside the small profile window to avoid turning beige clutter into tips.
    // Change thresholds only at a frame boundary, and only when most of the
    // frame is dim. A per-pixel threshold admitted normal-scene beige clutter.
    localparam integer FRAME_SAMPLES = (IMG_HEIGHT / SAMPLE_STEP) * IMG_W_GRP;
    reg [17:0] dim_samples;
    reg dim_scene;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            dim_samples <= 0;
            dim_scene <= 0;
        end else if (I_clear) begin
            dim_samples <= 0;
            dim_scene <= 0;
        end else if (I_frame_done) begin
            dim_scene <= dim_samples >= (FRAME_SAMPLES * 3 / 4);
            dim_samples <= 0;
        end else if (I_sample_valid && rs < 10'd576 &&
                     gs < 10'd576 && bs < 10'd576) begin
            if (dim_samples != 18'h3ffff) dim_samples <= dim_samples + 18'd1;
        end
    end
    // Keep brighter beige surfaces strict even in a predominantly dim frame.
    wire [10:0] profile_chroma_min = (dim_scene && rs < 10'd512) ? 11'd16 : 11'd24;
    wire warm_profile = warm && (chroma_rg >= profile_chroma_min) &&
                        (chroma_gb >= profile_chroma_min);
    // The locator observes the full foreground stream; only the more expensive
    // per-column profile is limited to the moving ROI.  ROI registers change
    // after frame_done, never in the middle of a captured frame.
    reg [9:0] roi_x0_r, roi_y0_r;
    reg roi_valid_r, capture_roi_valid;
    // A two-frame locator gap must not discard the search window. Skin and
    // geometry still have to pass; this does not manufacture a hand result.
    reg [1:0] roi_misses;
    reg [9:0] class_roi_x0;
    wire [9:0] roi_x0 = (DYNAMIC_ROI != 0) ? roi_x0_r : ROI_X0_GRP;
    wire [9:0] roi_y0 = (DYNAMIC_ROI != 0) ? roi_y0_r : ROI_Y0;
    wire [10:0] roi_x1 = {1'b0,roi_x0} + ROI_W - 1;
    wire [10:0] roi_y1 = {1'b0,roi_y0} + ROI_H - 1;
    wire [9:0] first_y = roi_y0 +
        ((SAMPLE_PHASE + SAMPLE_STEP - (roi_y0 % SAMPLE_STEP)) % SAMPLE_STEP);
    wire inside = ((DYNAMIC_ROI == 0) || roi_valid_r) &&
                  I_x_grp >= roi_x0 && {1'b0,I_x_grp} <= roi_x1 &&
                  I_y >= roi_y0 && {1'b0,I_y} <= roi_y1;
    wire foreground_gate = (MOTION_GATE_ENABLE != 0) ? I_motion_hit : 1'b1;
    wire raw_hit = I_sample_valid && foreground_gate && inside && warm_profile;
    reg [1:0] history;
    wire hit = raw_hit && (&history) && I_x_grp >= roi_x0+2;
    wire first_sample = I_sample_valid && inside &&
                        I_x_grp == roi_x0 && I_y == first_y;
    wire [7:0] col = I_x_grp - roi_x0;
    wire [5:0] bin = I_y[9:4];

    reg [ROI_W-1:0] seen;
    // Profile storage has one write port and one prefetched synchronous read.
    // 'seen' is the validity bitmap: invalid RAM words need no bulk reset.
    /* fehdl force_ram=1, ram_style="bram" */
    reg [9:0] top_y [0:ROI_W-1];
    reg [9:0] top_y_read;
    wire [7:0] top_read_addr =
        ((state == PROFILE || state == SHOULDER) && idx < ROI_W-1) ?
            idx + 8'd1 : 8'd0;
    always @(posedge I_clk) begin
        top_y_read <= top_y[top_read_addr];
        if (I_rst_n && !I_clear && state == CAPTURE &&
            I_sample_valid && inside && hit &&
            (I_y == first_y || !seen[col]))
            top_y[col] <= I_y;
    end
    reg [7:0] hist [0:HIST_BINS-1];
    reg [15:0] area, box_area;
    reg [7:0] columns, target, idx, run_width;
    reg bbox_seen;
    reg [9:0] xmin, xmax, ymin, ymax, box_height, baseline, tip_threshold;
    reg [8:0] cumulative;
    reg [2:0] state, peaks;
    reg [3:0] final_peaks;
    reg [7:0] first_tip_start, first_tip_end;
    reg [1:0] shoulder_count;
    reg [1:0] pending;
    reg pending_once;
    reg [2:0] miss_count;
    wire [9:0] box_width_next = xmax - xmin + 10'd1;
    wire [9:0] box_rows_next = ((ymax - ymin) / SAMPLE_STEP) + 10'd1;
    wire geometry_common = ((DYNAMIC_ROI == 0) || capture_roi_valid) &&
                           bbox_seen && area >= MIN_AREA && area <= MAX_AREA &&
                           columns >= 8'd12 &&
                           box_width_next >= 10'd14 && box_width_next <= ROI_W-2 &&
                           box_height >= 10'd40 &&
                           {area,2'b00} < ({2'b00,box_area} + {1'b0,box_area,1'b0});
    // Keep the sparse-profile allowance needed by fist/point silhouettes.
    wire geometry_ok = geometry_common && columns <= ROI_W-4 &&
                       {area,3'b000} > {3'b000,box_area};
    // A spread hand can occupy nearly the whole ROI; unlike a sparse warm
    // background, it must also fill at least a quarter of its profile box.
    wire open_geometry_ok = geometry_common && columns <= ROI_W-2 &&
                            {area,2'b00} > {2'b00,box_area};
    wire tip = seen[idx] &&
               ({1'b0,top_y_read} + {1'b0,tip_threshold} < {1'b0,baseline});
    wire [3:0] completed_peaks = {1'b0,peaks} +
        ((!tip && run_width >= 8'd2) ? 4'd1 : 4'd0) +
        ((idx == ROI_W-1 && tip && run_width >= 8'd1) ? 4'd1 : 4'd0);
    // The locator can clamp the ROI against a frame edge. In that case a
    // genuine raised finger stays *inside* the ROI, so the old above-ROI
    // evidence alone incorrectly turned a lower-frame POINT into FIST.
    wire [9:0] peak_height = (baseline > ymin) ? baseline - ymin : 10'd0;
    wire tall_single_peak = (final_peaks == 4'd1) &&
                            (peak_height >= 10'd16) &&
                            (peak_height >= (box_height >> 2));
    wire profile_point_evidence = (DYNAMIC_ROI == 0) ||
                                  upper_evidence || tall_single_peak;
    wire [1:0] profile_classified = (final_peaks == 4'd0) ?
                                ((DYNAMIC_ROI != 0 && upper_evidence) ? POINT : FIST) :
                            (final_peaks == 4'd1 && shoulder_count < 2'd2) ?
                                (profile_point_evidence ? POINT : FIST) :
                            (final_peaks == 4'd2 && DYNAMIC_ROI != 0 && !upper_evidence) ? FIST :
                            ((final_peaks >= 4'd3) ||
                             (final_peaks == 4'd2 && shoulder_count >= 2'd2)) ? OPEN : NONE;
    // The full-frame multi-run hint is not a hand by itself: textured walls
    // and equipment can produce many warm runs. Require the same compact
    // profile geometry as the other classes before publishing OPEN.
    // Rescue a clipped profile, or a broad profile with independent evidence
    // above the ROI. Do not let background triplets override a compact fist.
    localparam integer COHERENT_PROFILE_COLS = (IMG_HEIGHT >= 512) ? ROI_W*3/4 : ROI_W-2;
    wire qualified_coherent_open = coherent_open_hint && capture_roi_valid && bbox_seen &&
                                   area >= MIN_AREA &&
        ((IMG_HEIGHT < 512 && columns >= COHERENT_PROFILE_COLS &&
          (columns >= ROI_W-2 || upper_evidence)) ||
         (IMG_HEIGHT >= 512 && columns >= ROI_W/2 && coherent_finger_long));
    wire qualified_open_hint = (open_hint && open_geometry_ok) || qualified_coherent_open;
    // A tall, narrow warm strip (chair/door frame at the image edge) can have
    // zero profile peaks, but is not a fist. Width is in four-pixel groups;
    // A fist with a modest wrist may be up to 3:2 in pixel height/width.
    // 2*height <= 3*(4*group_width): use 14-bit sums, not a truncated shift.
    // This is only a FIST veto; it must not relax the skin or OPEN gates.
    wire [13:0] fist_width_limit = {1'b0,box_width_next,3'b000} +
                                  {2'b00,box_width_next,2'b00};
    wire fist_compact = {3'b000,box_height,1'b0} <= fist_width_limit;
    wire [1:0] classified = qualified_open_hint ? OPEN :
        ((profile_classified == FIST && !fist_compact) ? NONE : profile_classified);
    // A V can contain one high peak plus a lower second finger. Reject that
    // shoulder instead of silently reporting POINT.
    wire shoulder_hit = seen[idx] && (
        (final_peaks == 4'd1 &&
         xmax >= class_roi_x0 + first_tip_end + 10'd28 &&
         {1'b0,idx} >= {1'b0,first_tip_end} + 9'd8 &&
         {1'b0,top_y_read} <= {1'b0,baseline} + 11'd8) ||
        (final_peaks == 4'd2 &&
         {1'b0,idx} + 9'd8 < {1'b0,first_tip_start} &&
         {1'b0,top_y_read} + 11'd16 <= {1'b0,baseline}));
    integer i;
    // Use the densest vertical band of longest contiguous warm-color row runs.
    // It separates a hand from other skin-like regions elsewhere in the frame.
    reg loc_seen;
    reg [1:0] loc_history;
    reg [17:0] loc_area;
    reg [9:0] loc_xmin, loc_xmax, loc_ymin, loc_ymax;
    reg [17:0] loc_bin_area [0:LOC_BIN_COUNT-1];
    reg [9:0] loc_bin_xmin [0:LOC_BIN_COUNT-1];
    reg [9:0] loc_bin_xmax [0:LOC_BIN_COUNT-1];
    reg [17:0] loc_best_area;
    reg [7:0] loc_best_bin;
    reg [9:0] loc_best_xmin, loc_best_xmax;
    reg [9:0] loc_best_center_y;
    reg [9:0] loc_run_len, loc_run_start;
    reg [9:0] loc_row_best_len, loc_row_best_start;
    // A wide open hand can exceed the narrow profile ROI. Count spatially
    // separated, persistent warm runs across the full frame instead of
    // assuming every fingertip lies inside that ROI.
    reg [7:0] loc_row_runs, loc_open_rows, loc_three_rows, loc_close_rows;
    reg [9:0] loc_row_first, loc_row_last;
    reg [9:0] loc_prev1_start, loc_prev2_start;
    reg [9:0] loc_prev1_len, loc_prev2_len, loc_prev1_end, loc_prev2_end;
    reg finger_row_seen;
    reg [9:0] finger_row_xmin, finger_row_xmax;
    reg [7:0] finger_chain_rows, finger_best_rows;
    reg [9:0] finger_chain_xmin, finger_chain_xmax, finger_chain_ymin, finger_chain_ymax;
    reg [9:0] finger_best_xmin, finger_best_xmax, finger_best_ymin, finger_best_ymax;
    reg palm_bridge_seen;
    reg [9:0] palm_bridge_xmin, palm_bridge_xmax, palm_bridge_ymax;
    reg coherent_open_hint;
    reg coherent_finger_long;
    reg [1:0] finger_row_run_count;
    reg [9:0] finger_prev1_start, finger_prev2_start;
    // Row summaries decouple pixel/run arithmetic from cross-row scoring.
    // s1: completed-row capture; s2: chain/bridge decision; s3: best update.
    reg coherent_s1_valid, coherent_s1_seen;
    reg [9:0] coherent_s1_xmin, coherent_s1_xmax, coherent_s1_y;
    reg [9:0] coherent_s1_palm_start, coherent_s1_palm_end, coherent_s1_palm_len;
    reg coherent_s2_valid, coherent_s2_best, coherent_s2_palm;
    reg [7:0] coherent_s2_rows;
    reg [9:0] coherent_s2_xmin, coherent_s2_xmax, coherent_s2_ymin, coherent_s2_ymax;
    reg [9:0] coherent_s2_palm_start, coherent_s2_palm_end;
    reg [2:0] coherent_done_pipe;
    reg [2:0] guard_wait;
    reg [9:0] coherent_box_xmin, coherent_box_xmax, coherent_box_ymin, coherent_box_ymax;
    reg loc_row_close;
    reg loc_open_seen, open_hint;
    reg [9:0] loc_open_xmin, loc_open_xmax, loc_open_ymin, loc_open_ymax;
    reg loc_close_seen;
    reg [9:0] loc_close_xmin, loc_close_xmax, loc_close_ymin, loc_close_ymax;
    reg [9:0] open_box_xmin, open_box_xmax, open_box_ymin, open_box_ymax;
    reg upper_row_seen, upper_evidence;
    reg [7:0] upper_rows;
    // Display-only upper extent. The classifier's ROI intentionally follows
    // the palm; do not pretend that its cropped box contains the fingertips.
    // This independent gate also keeps valid skin whose RG/GB ratio exceeds
    // the legacy locator's 2:1 limit. It does NOT relax classification.
    wire [10:0] extent_rg_min = (dim_scene && rs < 10'd512) ? 11'd16 : 11'd48;
    wire [11:0] extent_rg3 = {1'b0,chroma_rg} + {chroma_rg,1'b0};
    wire [11:0] extent_gb3 = {1'b0,chroma_gb} + {chroma_gb,1'b0};
    wire extent_raw = I_sample_valid && foreground_gate && roi_valid_r &&
        I_x_grp >= roi_x0 && {1'b0,I_x_grp} <= roi_x1 &&
        I_y < roi_y0 && {1'b0,I_y} + (ROI_H/2) >= {1'b0,roi_y0} &&
        rs >= 10'd96 && rs>=gs && gs>=bs && chroma_rg >= extent_rg_min &&
        chroma_gb >= profile_chroma_min &&
        {1'b0,chroma_rg} <= extent_gb3 && extent_rg3 >= {1'b0,chroma_gb};
    reg [1:0] extent_history;
    reg extent_hit_d1, extent_done_d1;
    reg [9:0] extent_x_d1, extent_y_d1;
    wire [9:0] extent_start_d1 = extent_x_d1-10'd2;
    reg extent_seen;
    reg [9:0] extent_xmin, extent_xmax, extent_ymin, extent_ymax;
    reg [7:0] extent_count;
    reg extent_box_valid;
    reg [9:0] extent_box_xmin, extent_box_xmax, extent_box_ymin;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            extent_history<=0; extent_hit_d1<=0; extent_done_d1<=0;
            extent_x_d1<=0; extent_y_d1<=0; extent_seen<=0; extent_count<=0;
            extent_xmin<=0; extent_xmax<=0; extent_ymin<=0; extent_ymax<=0;
            extent_box_valid<=0; extent_box_xmin<=0; extent_box_xmax<=0; extent_box_ymin<=0;
        end else if (I_clear) begin
            extent_history<=0; extent_hit_d1<=0; extent_done_d1<=0;
            extent_seen<=0; extent_count<=0; extent_box_valid<=0;
        end else begin
            extent_done_d1<=I_frame_done;
            extent_hit_d1<=extent_raw && (&extent_history) && I_x_grp>=roi_x0+10'd2;
            extent_x_d1<=I_x_grp; extent_y_d1<=I_y;
            if (I_sample_valid) begin
                if (I_x_grp==0) extent_history<={1'b0,extent_raw};
                else extent_history<={extent_history[0],extent_raw};
            end
            if (extent_hit_d1) begin
                if (extent_count!=8'hff) extent_count<=extent_count+8'd1;
                if (!extent_seen) begin
                    extent_seen<=1;
                    extent_xmin<=extent_start_d1; extent_xmax<=extent_x_d1;
                    extent_ymin<=extent_y_d1; extent_ymax<=extent_y_d1;
                end else begin
                    if (extent_start_d1<extent_xmin) extent_xmin<=extent_start_d1;
                    if (extent_x_d1>extent_xmax) extent_xmax<=extent_x_d1;
                    if (extent_y_d1<extent_ymin) extent_ymin<=extent_y_d1;
                    if (extent_y_d1>extent_ymax) extent_ymax<=extent_y_d1;
                end
            end
            if (extent_done_d1) begin
                extent_box_valid<=extent_seen && extent_count>=8'd8 &&
                    extent_ymax>=extent_ymin+10'd8;
                extent_box_xmin<=extent_xmin; extent_box_xmax<=extent_xmax;
                extent_box_ymin<=extent_ymin;
                extent_history<=0; extent_seen<=0; extent_count<=0;
            end
        end
    end
    wire [9:0] result_xmin = qualified_coherent_open ? coherent_box_xmin :
        (qualified_open_hint ? open_box_xmin : xmin);
    wire [9:0] result_xmax = qualified_coherent_open ? coherent_box_xmax :
        (qualified_open_hint ? open_box_xmax : xmax);
    wire [9:0] result_ymin = qualified_coherent_open ? coherent_box_ymin :
        (qualified_open_hint ? open_box_ymin : ymin);
    wire use_extent = DYNAMIC_ROI != 0 && extent_box_valid &&
                      (classified==POINT || classified==OPEN);
    wire loc_raw_hit = I_sample_valid && foreground_gate && warm;
    wire loc_hit = loc_raw_hit && (&loc_history) && I_x_grp >= 10'd2;
    wire upper_hit = loc_hit && warm_profile && chroma_rg >= 11'd64 &&
                     I_x_grp >= roi_x0 && I_x_grp < roi_x0 + ROI_W &&
                     I_y < roi_y0 && I_y + ROI_H/2 >= roi_y0;
    wire [9:0] loc_run_len_next = loc_hit ?
        ((loc_run_len == 0) ? 10'd3 : loc_run_len + 10'd1) : loc_run_len;
    wire [9:0] loc_run_start_next = (loc_hit && loc_run_len == 0) ?
        (I_x_grp - 10'd2) : loc_run_start;
    wire loc_run_complete = (!loc_hit && loc_run_len >= OPEN_RUN_MIN) ||
                            (loc_hit && I_x_grp == IMG_W_GRP-1 && loc_run_len_next >= OPEN_RUN_MIN);
    wire finger_run_complete = (!loc_hit && loc_run_len >= FINGER_RUN_MIN) ||
        (loc_hit && I_x_grp == IMG_W_GRP-1 && loc_run_len_next >= FINGER_RUN_MIN);
    wire [9:0] loc_complete_start = loc_hit ? loc_run_start_next : loc_run_start;
    wire [9:0] loc_complete_end = loc_hit ? I_x_grp : (loc_run_start + loc_run_len - 10'd1);
    wire [7:0] loc_row_runs_end = loc_row_runs + {7'd0,loc_run_complete};
    wire [9:0] loc_row_first_end = (loc_row_runs == 0 && loc_run_complete) ?
                                   loc_complete_start : loc_row_first;
    wire [9:0] loc_row_last_end = loc_run_complete ? loc_complete_end : loc_row_last;
    wire loc_close_triplet = loc_run_complete && loc_row_runs >= 8'd2 &&
                             loc_complete_end - loc_prev2_start <= OPEN_SPAN_MAX;
    wire loc_row_close_end = loc_row_close || loc_close_triplet;
    wire [10:0] loc_close_center = ({1'b0,loc_prev2_start} +
                                    {1'b0,loc_complete_end}) >> 1;
    wire loc_close_near = loc_close_triplet && loc_seen &&
                          loc_close_center + 11'd5 >= loc_xmin &&
                          loc_close_center <= {1'b0,loc_xmax} + 11'd5;
    localparam integer COHERENT_ROWS_MIN = (IMG_HEIGHT >= 512) ? 3 : 2;
    // This is the counted run length, not a redundant add/subtract of ends.
    wire [9:0] loc_complete_len = loc_run_len_next;
    wire [9:0] finger_min_len12 = (loc_prev1_len < loc_prev2_len) ? loc_prev1_len : loc_prev2_len;
    wire [9:0] finger_max_len12 = (loc_prev1_len > loc_prev2_len) ? loc_prev1_len : loc_prev2_len;
    wire [9:0] finger_min_len = (loc_complete_len < finger_min_len12) ? loc_complete_len : finger_min_len12;
    wire [9:0] finger_max_len = (loc_complete_len > finger_max_len12) ? loc_complete_len : finger_max_len12;
    // Three similarly sized digit runs, close in space, ABOVE the previous
    // palm band. This rejects unrelated rows elsewhere in the full frame.
    wire [10:0] finger_center = ({1'b0,finger_prev2_start}+{1'b0,loc_complete_end}) >> 1;
    wire finger_triplet = I_sample_valid && I_x_grp!=0 &&
        finger_run_complete && finger_row_run_count>=2 && loc_seen &&
        loc_complete_end-finger_prev2_start<=OPEN_SPAN_MAX &&
        finger_center+11'd5>={1'b0,loc_xmin} && finger_center<={1'b0,loc_xmax}+11'd5 &&
        {1'b0,finger_max_len} <= {finger_min_len,1'b0} &&
        (finger_prev1_start-loc_prev2_end-10'd1) <= {finger_max_len,1'b0} &&
        (loc_complete_start-loc_prev1_end-10'd1) <= {finger_max_len,1'b0} &&
        I_y < loc_ymin && {1'b0,I_y}+ROI_H >= {1'b0,loc_ymin};
    wire finger_row_end_seen = finger_row_seen || finger_triplet;
    wire finger_choose_now = finger_triplet && (!finger_row_seen ||
        loc_complete_end-finger_prev2_start < finger_row_xmax-finger_row_xmin);
    wire [9:0] finger_row_end_xmin = finger_choose_now ? finger_prev2_start : finger_row_xmin;
    wire [9:0] finger_row_end_xmax = finger_choose_now ? loc_complete_end : finger_row_xmax;
    wire [9:0] finger_union_xmin = finger_chain_xmin < coherent_s1_xmin ? finger_chain_xmin : coherent_s1_xmin;
    wire [9:0] finger_union_xmax = finger_chain_xmax > coherent_s1_xmax ? finger_chain_xmax : coherent_s1_xmax;
    wire [9:0] finger_union_span = finger_union_xmax-finger_union_xmin;
    wire finger_chain_continue = finger_chain_rows != 0 &&
        finger_union_span <= OPEN_SPAN_MAX &&
        coherent_s1_y <= finger_chain_ymax + SAMPLE_STEP*3 &&
        {1'b0,coherent_s1_xmin} <= {1'b0,finger_chain_xmax}+11'd5 &&
        {1'b0,coherent_s1_xmax}+11'd5 >= {1'b0,finger_chain_xmin};
    wire [7:0] finger_chain_next_rows = finger_chain_continue ?
        ((finger_chain_rows == 8'hff) ? 8'hff : finger_chain_rows+8'd1) : 8'd1;
    wire [9:0] finger_chain_next_xmin = finger_chain_continue ? finger_union_xmin : coherent_s1_xmin;
    wire [9:0] finger_chain_next_xmax = finger_chain_continue ? finger_union_xmax : coherent_s1_xmax;
    wire [9:0] finger_best_width = finger_best_xmax-finger_best_xmin+10'd1;
    wire [10:0] palm_line_center = ({1'b0,coherent_s1_palm_start}+{1'b0,coherent_s1_palm_end}) >> 1;
    wire palm_bridge_hit = finger_best_rows >= COHERENT_ROWS_MIN &&
        coherent_s1_y > finger_best_ymax && coherent_s1_y <= finger_best_ymax+ROI_H &&
        coherent_s1_palm_len >= (finger_best_width >> 1) &&
        {1'b0,coherent_s1_palm_len} <= {finger_best_width,1'b0} &&
        palm_line_center >= {1'b0,finger_best_xmin} &&
        palm_line_center <= {1'b0,finger_best_xmax};
    wire loc_use_close_box = loc_open_rows < OPEN_ROWS_MIN && loc_close_seen;
    wire [9:0] loc_box_top = loc_use_close_box ? loc_close_ymin : loc_open_ymin;
    wire [9:0] loc_box_bottom = loc_use_close_box ? loc_close_ymax : loc_open_ymax;
    wire [9:0] loc_palm_bottom = (((loc_best_bin+1) << LOC_BIN_SHIFT) > IMG_HEIGHT) ?
                                 IMG_HEIGHT-1 : ((loc_best_bin+1) << LOC_BIN_SHIFT)-1;
    wire [10:0] loc_box_bottom_padded =
        {1'b0,(loc_box_bottom > loc_palm_bottom ? loc_box_bottom : loc_palm_bottom)} + ROI_H/6;
    wire loc_choose_run = loc_run_len_next > loc_row_best_len;
    wire [9:0] loc_line_best_len = loc_choose_run ?
        loc_run_len_next : loc_row_best_len;
    wire [9:0] loc_line_best_start = loc_choose_run ?
        loc_run_start_next : loc_row_best_start;
    wire [9:0] loc_line_best_xmax = loc_line_best_start + loc_line_best_len - 10'd1;
    wire [9:0] loc_bin_index = I_y >> LOC_BIN_SHIFT;
    integer loc_max_i;
    integer loc_reset_i;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            coherent_s1_valid<=0; coherent_s1_seen<=0;
            coherent_s1_xmin<=0; coherent_s1_xmax<=0; coherent_s1_y<=0;
            coherent_s1_palm_start<=0; coherent_s1_palm_end<=0; coherent_s1_palm_len<=0;
            coherent_s2_valid<=0; coherent_s2_best<=0; coherent_s2_palm<=0; coherent_s2_rows<=0;
            coherent_s2_xmin<=0; coherent_s2_xmax<=0; coherent_s2_ymin<=0; coherent_s2_ymax<=0;
            coherent_s2_palm_start<=0; coherent_s2_palm_end<=0; coherent_done_pipe<=0;
            loc_prev1_len<=0; loc_prev2_len<=0; loc_prev1_end<=0; loc_prev2_end<=0;
            finger_row_seen<=0; finger_row_xmin<=0; finger_row_xmax<=0;
            finger_chain_rows<=0; finger_best_rows<=0;
            finger_chain_xmin<=0; finger_chain_xmax<=0;
            finger_chain_ymin<=0; finger_chain_ymax<=0;
            finger_best_xmin<=0; finger_best_xmax<=0;
            finger_best_ymin<=0; finger_best_ymax<=0;
            palm_bridge_seen<=0; palm_bridge_xmin<=0; palm_bridge_xmax<=0; palm_bridge_ymax<=0;
            coherent_open_hint<=0;
            coherent_finger_long<=0;
            finger_row_run_count<=0; finger_prev1_start<=0; finger_prev2_start<=0;
            coherent_box_xmin<=0; coherent_box_xmax<=0; coherent_box_ymin<=0; coherent_box_ymax<=0;
        end else if (I_clear) begin
            coherent_s1_valid<=0; coherent_s2_valid<=0; coherent_done_pipe<=0;
            finger_chain_rows<=0; finger_best_rows<=0; finger_row_seen<=0;
            palm_bridge_seen<=0; coherent_open_hint<=0;
            coherent_finger_long<=0;
            finger_row_run_count<=0; finger_prev1_start<=0; finger_prev2_start<=0;
            loc_prev1_len<=0; loc_prev2_len<=0; loc_prev1_end<=0; loc_prev2_end<=0;
        end else if (DYNAMIC_ROI != 0) begin
            coherent_s1_valid<=0;
            coherent_s2_valid<=coherent_s1_valid;
            coherent_done_pipe<={coherent_done_pipe[1:0],I_frame_done};
            if (I_sample_valid) begin
                if (I_x_grp==0) begin
                    finger_row_seen<=0;
                    finger_row_run_count<=0; finger_prev1_start<=0; finger_prev2_start<=0;
                    loc_prev1_len<=0; loc_prev2_len<=0; loc_prev1_end<=0; loc_prev2_end<=0;
                end else if (finger_run_complete) begin
                    if (finger_row_run_count!=2'd3) finger_row_run_count<=finger_row_run_count+2'd1;
                    finger_prev2_start<=finger_prev1_start; finger_prev1_start<=loc_complete_start;
                    loc_prev2_len<=loc_prev1_len; loc_prev1_len<=loc_complete_len;
                    loc_prev2_end<=loc_prev1_end; loc_prev1_end<=loc_complete_end;
                end
                if (finger_choose_now) begin
                    finger_row_seen<=1;
                    finger_row_xmin<=finger_prev2_start; finger_row_xmax<=loc_complete_end;
                end
                if (I_x_grp==IMG_W_GRP-1) begin
                    coherent_s1_valid<=1; coherent_s1_seen<=finger_row_end_seen;
                    coherent_s1_xmin<=finger_row_end_xmin; coherent_s1_xmax<=finger_row_end_xmax;
                    coherent_s1_y<=I_y;
                    coherent_s1_palm_start<=loc_line_best_start;
                    coherent_s1_palm_end<=loc_line_best_xmax;
                    coherent_s1_palm_len<=loc_line_best_len;
                end
            end
            if (coherent_s1_valid) begin
                coherent_s2_best<=coherent_s1_seen && finger_chain_next_rows>finger_best_rows;
                coherent_s2_palm<=palm_bridge_hit && !(coherent_s1_seen && finger_chain_next_rows>finger_best_rows);
                coherent_s2_rows<=finger_chain_next_rows;
                coherent_s2_xmin<=finger_chain_next_xmin; coherent_s2_xmax<=finger_chain_next_xmax;
                coherent_s2_ymin<=finger_chain_continue ? finger_chain_ymin : coherent_s1_y;
                coherent_s2_ymax<=coherent_s1_y;
                coherent_s2_palm_start<=coherent_s1_palm_start; coherent_s2_palm_end<=coherent_s1_palm_end;
                if (coherent_s1_seen) begin
                    finger_chain_rows<=finger_chain_next_rows;
                    finger_chain_xmin<=finger_chain_next_xmin; finger_chain_xmax<=finger_chain_next_xmax;
                    if (!finger_chain_continue) finger_chain_ymin<=coherent_s1_y;
                    finger_chain_ymax<=coherent_s1_y;
                end
            end
            if (coherent_s2_valid) begin
                if (coherent_s2_best) begin
                    finger_best_rows<=coherent_s2_rows;
                    finger_best_xmin<=coherent_s2_xmin; finger_best_xmax<=coherent_s2_xmax;
                    finger_best_ymin<=coherent_s2_ymin; finger_best_ymax<=coherent_s2_ymax;
                    palm_bridge_seen<=0;
                end else if (coherent_s2_palm) begin
                    if (!palm_bridge_seen) begin
                        palm_bridge_xmin<=coherent_s2_palm_start; palm_bridge_xmax<=coherent_s2_palm_end;
                    end else begin
                        if (coherent_s2_palm_start<palm_bridge_xmin) palm_bridge_xmin<=coherent_s2_palm_start;
                        if (coherent_s2_palm_end>palm_bridge_xmax) palm_bridge_xmax<=coherent_s2_palm_end;
                    end
                    palm_bridge_seen<=1; palm_bridge_ymax<=coherent_s2_ymax;
                end
            end
            if (coherent_done_pipe[2]) begin
                coherent_open_hint<=finger_best_rows>=COHERENT_ROWS_MIN && palm_bridge_seen &&
                    finger_best_xmax-finger_best_xmin<=OPEN_SPAN_MAX &&
                    finger_best_ymax-finger_best_ymin<=ROI_H/2;
                coherent_finger_long<=finger_best_rows>=8 &&
                    finger_best_ymax>=finger_best_ymin+ROI_H/12;
                coherent_box_xmin<=palm_bridge_xmin<finger_best_xmin ? palm_bridge_xmin : finger_best_xmin;
                coherent_box_xmax<=palm_bridge_xmax>finger_best_xmax ? palm_bridge_xmax : finger_best_xmax;
                coherent_box_ymin<=finger_best_ymin;
                coherent_box_ymax<=palm_bridge_ymax;
                finger_chain_rows<=0; finger_best_rows<=0; finger_row_seen<=0; palm_bridge_seen<=0;
            end
        end
    end
    always @* begin
        loc_best_area = 18'd0;
        loc_best_bin = 8'd0;
        loc_best_xmin = 10'd0;
        loc_best_xmax = 10'd0;
        for (loc_max_i=0; loc_max_i<LOC_BIN_COUNT; loc_max_i=loc_max_i+1) begin
            if (loc_bin_area[loc_max_i] > loc_best_area) begin
                loc_best_area = loc_bin_area[loc_max_i];
                loc_best_bin = loc_max_i;
                loc_best_xmin = loc_bin_xmin[loc_max_i];
                loc_best_xmax = loc_bin_xmax[loc_max_i];
            end
        end
        loc_best_center_y = (loc_best_bin << LOC_BIN_SHIFT) +
                            (1 << (LOC_BIN_SHIFT-1));
    end
    wire [10:0] loc_cx = ({1'b0,loc_best_xmin} + {1'b0,loc_best_xmax}) >> 1;
    wire [10:0] loc_cy = {1'b0,loc_best_center_y};
    wire [10:0] roi_x0_candidate =
        (loc_cx <= ROI_W/2) ? 11'd0 :
        (loc_cx >= MAX_X0 + ROI_W/2) ? MAX_X0 : loc_cx - ROI_W/2;
    wire [10:0] roi_y0_candidate =
        (loc_cy <= ROI_H/2) ? 11'd0 :
        (loc_cy >= MAX_Y0 + ROI_H/2) ? MAX_Y0 : loc_cy - ROI_H/2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            loc_seen <= 1'b0; loc_history <= 2'b0; loc_area <= 18'd0;
            loc_xmin <= 10'd0; loc_xmax <= 10'd0;
            loc_ymin <= 10'd0; loc_ymax <= 10'd0;
            loc_run_len <= 10'd0; loc_run_start <= 10'd0;
            loc_row_best_len <= 10'd0; loc_row_best_start <= 10'd0;
            loc_row_runs <= 0; loc_row_first <= 0; loc_row_last <= 0;
            loc_prev1_start <= 0; loc_prev2_start <= 0; loc_row_close <= 0;
            loc_open_rows <= 0; loc_three_rows <= 0; loc_close_rows <= 0;
            loc_open_seen <= 0; open_hint <= 0;
            loc_open_xmin <= 0; loc_open_xmax <= 0;
            loc_open_ymin <= 0; loc_open_ymax <= 0;
            loc_close_seen <= 0;
            loc_close_xmin <= 0; loc_close_xmax <= 0;
            loc_close_ymin <= 0; loc_close_ymax <= 0;
            open_box_xmin <= 0; open_box_xmax <= 0;
            open_box_ymin <= 0; open_box_ymax <= 0;
            upper_row_seen <= 0; upper_rows <= 0; upper_evidence <= 0;
            roi_x0_r <= ROI_X0_GRP; roi_y0_r <= ROI_Y0;
            roi_valid_r <= (DYNAMIC_ROI == 0);
            roi_misses <= 0;
            for (loc_reset_i=0; loc_reset_i<LOC_BIN_COUNT; loc_reset_i=loc_reset_i+1) begin
                loc_bin_area[loc_reset_i] <= 18'd0;
                loc_bin_xmin[loc_reset_i] <= 10'd0;
                loc_bin_xmax[loc_reset_i] <= 10'd0;
            end
        end else if (I_clear) begin
            loc_seen <= 1'b0; loc_history <= 2'b0; loc_area <= 18'd0;
            loc_run_len <= 10'd0; loc_run_start <= 10'd0;
            loc_row_best_len <= 10'd0; loc_row_best_start <= 10'd0;
            loc_row_runs <= 0; loc_row_first <= 0; loc_row_last <= 0;
            loc_prev1_start <= 0; loc_prev2_start <= 0; loc_row_close <= 0;
            loc_open_rows <= 0; loc_three_rows <= 0; loc_close_rows <= 0;
            loc_open_seen <= 0; open_hint <= 0;
            loc_close_seen <= 0;
            upper_row_seen <= 0; upper_rows <= 0; upper_evidence <= 0;
            roi_valid_r <= (DYNAMIC_ROI == 0);
            roi_misses <= 0;
            for (loc_reset_i=0; loc_reset_i<LOC_BIN_COUNT; loc_reset_i=loc_reset_i+1) begin
                loc_bin_area[loc_reset_i] <= 18'd0;
                loc_bin_xmin[loc_reset_i] <= 10'd0;
                loc_bin_xmax[loc_reset_i] <= 10'd0;
            end
        end else if (DYNAMIC_ROI != 0) begin
            if (I_sample_valid) begin
                if (I_x_grp == 10'd0) loc_history <= {1'b0,loc_raw_hit};
                else loc_history <= {loc_history[0],loc_raw_hit};
                if (I_x_grp == 10'd0) begin
                    loc_run_len <= 10'd0;
                    loc_run_start <= 10'd0;
                    loc_row_best_len <= 10'd0;
                    loc_row_best_start <= 10'd0;
                    loc_row_runs <= 0;
                    loc_row_first <= 0;
                    loc_row_last <= 0;
                    loc_prev1_start <= 0;
                    loc_prev2_start <= 0;
                    loc_row_close <= 0;
                    upper_row_seen <= 0;
                end else if (loc_hit) begin
                    loc_run_len <= loc_run_len_next;
                    loc_run_start <= loc_run_start_next;
                end else begin
                    if (loc_run_len > loc_row_best_len) begin
                        loc_row_best_len <= loc_run_len;
                        loc_row_best_start <= loc_run_start;
                    end
                    loc_run_len <= 10'd0;
                end
                if (upper_hit) upper_row_seen <= 1'b1;
                if (I_x_grp == IMG_W_GRP-1 && (upper_row_seen || upper_hit) &&
                    upper_rows != 8'hff) upper_rows <= upper_rows + 8'd1;
                if (I_x_grp != 0 && loc_run_complete) begin
                    if (loc_row_runs != 8'hff) loc_row_runs <= loc_row_runs + 8'd1;
                    if (loc_row_runs == 0) loc_row_first <= loc_complete_start;
                    loc_row_last <= loc_complete_end;
                    loc_prev2_start <= loc_prev1_start;
                    loc_prev1_start <= loc_complete_start;
                    if (loc_close_triplet) loc_row_close <= 1'b1;
                end
                if (loc_close_near) begin
                    if (!loc_close_seen) begin
                        loc_close_seen <= 1'b1;
                        loc_close_xmin <= loc_prev2_start;
                        loc_close_xmax <= loc_complete_end;
                        loc_close_ymin <= I_y;
                        loc_close_ymax <= I_y;
                    end else begin
                        if (loc_prev2_start < loc_close_xmin)
                            loc_close_xmin <= loc_prev2_start;
                        if (loc_complete_end > loc_close_xmax)
                            loc_close_xmax <= loc_complete_end;
                        loc_close_ymax <= I_y;
                    end
                end
                if (I_x_grp == IMG_W_GRP-1 && loc_row_runs_end >= 8'd3) begin
                    if (loc_three_rows != 8'hff) loc_three_rows <= loc_three_rows + 8'd1;
                    if (loc_row_close_end && loc_close_rows != 8'hff)
                        loc_close_rows <= loc_close_rows + 8'd1;
                    if (loc_row_runs_end >= 8'd4 && loc_open_rows != 8'hff)
                        loc_open_rows <= loc_open_rows + 8'd1;
                    if (!loc_open_seen) begin
                        loc_open_seen <= 1'b1;
                        loc_open_xmin <= loc_row_first_end;
                        loc_open_xmax <= loc_row_last_end;
                        loc_open_ymin <= I_y;
                        loc_open_ymax <= I_y;
                    end else begin
                        if (loc_row_first_end < loc_open_xmin) loc_open_xmin <= loc_row_first_end;
                        if (loc_row_last_end > loc_open_xmax) loc_open_xmax <= loc_row_last_end;
                        loc_open_ymax <= I_y;
                    end
                end
                if ((I_x_grp == IMG_W_GRP-1) && (loc_line_best_len >= 10'd3) &&
                    (loc_bin_index < LOC_BIN_COUNT)) begin
                    loc_bin_area[loc_bin_index] <=
                        loc_bin_area[loc_bin_index] + loc_line_best_len;
                    if (loc_bin_area[loc_bin_index] == 0) begin
                        loc_bin_xmin[loc_bin_index] <= loc_line_best_start;
                        loc_bin_xmax[loc_bin_index] <= loc_line_best_xmax;
                    end else begin
                        if (loc_line_best_start < loc_bin_xmin[loc_bin_index])
                            loc_bin_xmin[loc_bin_index] <= loc_line_best_start;
                        if (loc_line_best_xmax > loc_bin_xmax[loc_bin_index])
                            loc_bin_xmax[loc_bin_index] <= loc_line_best_xmax;
                    end
                    loc_row_best_len <= 10'd0;
                    loc_row_best_start <= 10'd0;
                end
            end
            if (I_frame_done) begin
                upper_evidence <= upper_rows >= ((IMG_HEIGHT >= 512) ? 16 : 4);
                open_hint <= loc_open_seen &&
                             (loc_open_rows >= OPEN_ROWS_MIN ||
                              (loc_three_rows >= (dim_scene ? DIM_OPEN_THREE_ROWS_MIN :
                                                            OPEN_THREE_ROWS_MIN) &&
                               loc_close_rows >= OPEN_CLOSE_ROWS_MIN)) &&
                             loc_best_area >= LOC_MIN_AREA;
                open_box_xmin <= loc_use_close_box ? loc_close_xmin : loc_open_xmin;
                open_box_xmax <= loc_use_close_box ? loc_close_xmax : loc_open_xmax;
                open_box_ymin <= (loc_box_top > ROI_H/2) ?
                                 loc_box_top - ROI_H/2 : 10'd0;
                open_box_ymax <= (loc_box_bottom_padded >= IMG_HEIGHT) ?
                                 IMG_HEIGHT-1 : loc_box_bottom_padded[9:0];
                loc_area <= loc_best_area;
                loc_seen <= (loc_best_area != 0);
                loc_xmin <= loc_best_xmin;
                loc_xmax <= loc_best_xmax;
                loc_ymin <= loc_best_center_y - (1 << (LOC_BIN_SHIFT-1));
                loc_ymax <= loc_best_center_y + (1 << (LOC_BIN_SHIFT-1)) - 1;
                if (loc_best_area >= LOC_MIN_AREA) begin
                    roi_x0_r <= roi_x0_candidate[9:0];
                    roi_y0_r <= roi_y0_candidate[9:0];
                    roi_valid_r <= 1'b1;
                    roi_misses <= 0;
                end else if (TEMPORAL_RECOVERY != 0 && roi_valid_r && roi_misses < 2) begin
                    roi_misses <= roi_misses + 1'b1;
                end else begin
                    roi_valid_r <= 1'b0;
                    roi_misses <= 2;
                end
                loc_history <= 2'b0;
                loc_run_len <= 10'd0;
                loc_row_best_len <= 10'd0;
                loc_row_runs <= 0;
                loc_open_rows <= 0;
                loc_three_rows <= 0;
                loc_close_rows <= 0;
                loc_row_close <= 0;
                loc_open_seen <= 0;
                loc_close_seen <= 0;
                upper_row_seen <= 0;
                upper_rows <= 0;
                for (loc_reset_i=0; loc_reset_i<LOC_BIN_COUNT; loc_reset_i=loc_reset_i+1) begin
                    loc_bin_area[loc_reset_i] <= 18'd0;
                    loc_bin_xmin[loc_reset_i] <= 10'd0;
                    loc_bin_xmax[loc_reset_i] <= 10'd0;
                end
            end
        end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            history <= 0; seen <= 0;
            area <= 0; box_area <= 0; columns <= 0; target <= 0;
            idx <= 0; run_width <= 0; bbox_seen <= 0;
            xmin <= 0; xmax <= 0; ymin <= 0; ymax <= 0;
            box_height <= 0; baseline <= 0; tip_threshold <= 0;
            cumulative <= 0; peaks <= 0; final_peaks <= 0;
            first_tip_start <= 0; first_tip_end <= 0;
            shoulder_count <= 0; state <= CAPTURE; guard_wait <= 0;
            pending <= NONE; pending_once <= 0;
            miss_count <= 0;
            O_result_valid <= 0; O_id <= NONE; O_tip_count <= 0;
            capture_roi_valid <= 1'b0; class_roi_x0 <= ROI_X0_GRP;
            O_box_valid <= 1'b0;
            O_box_xmin <= 0; O_box_xmax <= 0;
            O_box_ymin <= 0; O_box_ymax <= 0;
            for (i=0; i<HIST_BINS; i=i+1) hist[i] <= 0;
            for (i=0; i<ROI_W; i=i+1) begin
                seen[i] <= 1'b0;
            end
        end else begin
            O_result_valid <= 1'b0;
            if (I_clear) begin
                O_result_valid <= 1'b1;
                O_id <= NONE;
                O_tip_count <= 0;
                O_box_valid <= 1'b0;
                pending <= NONE;
                pending_once <= 1'b0;
                miss_count <= 0;
                idx <= 0;
                state <= CLEAR; guard_wait <= 0;
            end
            if (I_sample_valid && inside) begin
                if (I_x_grp == roi_x0) history <= {1'b0,raw_hit};
                else history <= {history[0],raw_hit};
            end
            if (!I_clear) case (state)
                CAPTURE: begin
                    if (first_sample) begin
                        area <= 0; columns <= 0; bbox_seen <= 0;
                    end
                    if (I_sample_valid && inside) begin
                        if (I_y == first_y) seen[col] <= hit;
                        if (hit) begin
                            area <= area + 16'd1;
                            if (!bbox_seen) begin
                                bbox_seen <= 1'b1;
                                xmin <= I_x_grp; xmax <= I_x_grp;
                                ymin <= I_y; ymax <= I_y;
                            end else begin
                                if (I_x_grp < xmin) xmin <= I_x_grp;
                                if (I_x_grp > xmax) xmax <= I_x_grp;
                                if (I_y < ymin) ymin <= I_y;
                                if (I_y > ymax) ymax <= I_y;
                            end
                            if (I_y == first_y || !seen[col]) begin
                                seen[col] <= 1'b1;
                                columns <= columns + 8'd1;
                                hist[bin] <= hist[bin] + 8'd1;
                            end
                        end
                    end
                    if (I_frame_done) begin
                        capture_roi_valid <= roi_valid_r;
                        class_roi_x0 <= roi_x0;
                        box_area <= box_width_next * box_rows_next;
                        box_height <= ymax - ymin + 10'd1;
                        target <= (columns >> 2) + (columns >> 3);
                        guard_wait <= (DYNAMIC_ROI != 0) ? 3'd3 : 3'd0;
                        state <= GUARD;
                    end
                end
                GUARD: begin
                    if (guard_wait != 0) guard_wait <= guard_wait - 3'd1;
                    else if (qualified_open_hint && !I_clear) begin
                        final_peaks <= 4'd4;
                        state <= COMMIT;
                    end else if (!geometry_ok || I_clear) begin
                        O_result_valid <= 1'b1; O_tip_count <= 0;
                        // Preserve one missing frame between two matching
                        // candidates; sustained failures still revoke it.
                        if (TEMPORAL_RECOVERY == 0 || miss_count != 0) begin
                            pending <= NONE; pending_once <= 1'b0;
                        end
                        if (miss_count >= 3'd4) begin
                            O_id <= NONE;
                            O_box_valid <= 1'b0;
                            miss_count <= 0;
                        end else miss_count <= miss_count + 1'b1;
                        idx <= 0; state <= CLEAR;
                    end else begin
                        idx <= 0; cumulative <= 0;
                        tip_threshold <= (box_height >> 3) > 10'd12 ?
                                         (box_height >> 3) : 10'd12;
                        state <= HIST;
                    end
                end
                HIST: begin
                    if (cumulative + {1'b0,hist[idx]} >= {1'b0,target}) begin
                        baseline <= {idx[5:0],4'b1000};
                        idx <= 0; peaks <= 0; run_width <= 0;
                        state <= PROFILE;
                    end else if (idx == HIST_BINS-1) begin
                        O_result_valid <= 1'b1; O_id <= NONE; O_tip_count <= 0;
                        pending <= NONE; pending_once <= 1'b0;
                        idx <= 0; state <= CLEAR;
                    end else begin
                        cumulative <= cumulative + {1'b0,hist[idx]};
                        idx <= idx + 8'd1;
                    end
                end
                PROFILE: begin
                    if (tip) run_width <= run_width + 8'd1;
                    else begin
                        run_width <= 0;
                        if (run_width >= 8'd2 && peaks < 3'd7) begin
                            peaks <= peaks + 3'd1;
                            if (peaks == 0) begin
                                first_tip_start <= idx - run_width;
                                first_tip_end <= idx - 8'd1;
                            end
                        end
                    end
                    if (idx == ROI_W-1) begin
                        final_peaks <= completed_peaks;
                        if (tip && peaks == 0) begin
                            first_tip_start <= idx - run_width;
                            first_tip_end <= idx;
                        end
                        shoulder_count <= 0;
                        idx <= 0;
                        state <= (completed_peaks == 4'd1 || completed_peaks == 4'd2) ?
                                 SHOULDER : COMMIT;
                    end else idx <= idx + 8'd1;
                end
                SHOULDER: begin
                    if (shoulder_hit && shoulder_count < 2'd2)
                        shoulder_count <= shoulder_count + 2'd1;
                    if (idx == ROI_W-1) state <= COMMIT;
                    else idx <= idx + 8'd1;
                end
                COMMIT: begin
                    O_result_valid <= 1'b1;
                    O_tip_count <= qualified_open_hint ? 3'd4 :
                        (final_peaks > 4'd7 ? 3'd7 : final_peaks[2:0]);
                    if (classified == NONE) begin
                        if (TEMPORAL_RECOVERY == 0 || miss_count != 0) begin
                            pending <= NONE; pending_once <= 1'b0;
                        end
                        if (miss_count >= 3'd4) begin
                            O_id <= NONE;
                            O_box_valid <= 1'b0;
                            miss_count <= 0;
                        end else miss_count <= miss_count + 1'b1;
                    end else if (pending_once && pending == classified)
                        begin
                            miss_count <= 0;
                            O_id <= classified;
                            O_box_valid <= 1'b1;
                            O_box_xmin <= use_extent && extent_box_xmin<result_xmin ?
                                extent_box_xmin : result_xmin;
                            O_box_xmax <= use_extent && extent_box_xmax>result_xmax ?
                                extent_box_xmax : result_xmax;
                            O_box_ymin <= use_extent && extent_box_ymin<result_ymin ?
                                extent_box_ymin : result_ymin;
                            O_box_ymax <= qualified_coherent_open ? coherent_box_ymax :
                                (qualified_open_hint ? open_box_ymax : ymax);
                        end
                    else begin
                        miss_count <= 0;
                        pending <= classified; pending_once <= 1'b1;
                    end
                    idx <= 0; state <= CLEAR;
                end
                CLEAR: begin
                    if (idx < HIST_BINS) hist[idx] <= 0;
                    if (idx < ROI_W) begin
                        seen[idx] <= 1'b0;
                    end
                    if (idx == CLEAR_COUNT-1) begin
                        idx <= 0; state <= CAPTURE;
                    end else idx <= idx + 8'd1;
                end
                default: state <= CAPTURE;
            endcase
        end
    end
endmodule
