// Conservative frame-rate automatic exposure / analogue-gain controller.
// 初学者提示：它不是逐像素调亮度，而是每帧读一次平均亮度，决定下一次 I2C
// 相机配置应使用的曝光时间(O_ae)和模拟增益(O_ag)，反应较慢但稳定。
//
// Luminance data comes from the CSI clock domain and remains stable for an
// entire frame.  The toggle is synchronized through three flip-flops so that
// the two-flop luminance bus has settled before it is consumed.
`timescale 1ns/1ps
module ua_auto_exposure #(
    parameter [7:0]  LUMA_LOW       = 8'd96,
    parameter [7:0]  LUMA_HIGH      = 8'd144,
    // SC500 720p60 official table: VTS=1000 and exposure is expressed in
    // half-line units.  1990 is the documented near-frame-period maximum.
    parameter [15:0] AE_DEFAULT     = 16'd1990,
    parameter [15:0] AE_MIN         = 16'd2,
    parameter [15:0] AE_MAX         = 16'd1990,
    parameter [15:0] AE_STEP        = 16'd16,
    parameter [15:0] AG_DEFAULT     = 16'd80,
    parameter [15:0] AG_MIN         = 16'd16,
    // I_ag is offset by 16 before the SC500 gain-table lookup.  The sensor
    // data sheet permits lookup codes 0..127 (1.0x..15.75x), hence the
    // controller's legal range is 16..143. The old limit 89 stopped at
    // register 0x0f29 (5.125x) and left the upper analogue-gain range unused.
    parameter [15:0] AG_MAX         = 16'd143,
    parameter integer CONFIRM_FRAMES = 2,
    parameter integer SETTLE_FRAMES  = 3,
    parameter integer FORCE_MAX      = 0,
    // Product mode can select one of sixteen deterministic exposure profiles.
    // Keep the default at zero so existing automatic-exposure unit tests and
    // integrations retain their frame-average behaviour.
    parameter integer MANUAL_LEVELS  = 0,
    parameter integer AUTO_START_WRITE = 0,
    parameter integer AUTO_FAST = 0,
    parameter integer RESTORE_ON_DISABLE = 0,
    parameter integer HIGHLIGHT_PROTECT = 0,
    parameter [7:0] SUBJECT_FLOOR = 8'd0
)(
    input             I_clk,
    input             I_rst_n,
    input      [7:0]  I_luma_mean,
    input             I_frame_toggle,
    input             I_cam_cfg_done,
    input             I_ae_cfg_done,
    // KEY4-controlled level: low holds the last sensor AE/AG target; high resumes.
    input             I_auto_enable,
    // 已在 100MHz 按键域消抖、再同步到本 24MHz 域的一拍脉冲。
    // MANUAL_LEVELS 模式下，inc/dec 各切换一个固定的 AE/AG 组合档位。
    input             I_manual_inc,
    input             I_manual_dec,
    output reg        O_ae_req,
    output reg [15:0] O_ae,
    output reg [15:0] O_ag,
    output     [7:0]  O_luma_dbg,
    // Current manual profile number, 0 (darkest) through 15 (brightest).
    // This is exported only for the board seven-segment status display.
    output     [3:0]  O_manual_level,
    output     [4:0]  O_gain_index,
    input      [1:0]  I_highlight
);
    // Keep controller arithmetic explicitly sized.  Generic integer
    // expressions otherwise make TD infer wide anonymous adders, and TD 6.2
    // can fail while packing those carry chains even though this block is
    // functionally very small.
    localparam [1:0]  CONFIRM_LIMIT = (CONFIRM_FRAMES <= 1) ? 2'd0 : 2'd1;
    localparam [2:0]  SETTLE_INIT   = (SETTLE_FRAMES > 7) ? 3'd7 : SETTLE_FRAMES[2:0];
    localparam [15:0] AE_MAX_STEP_FLOOR = AE_MAX - AE_STEP;
    localparam [15:0] AE_MIN_STEP_CEIL  = AE_MIN + AE_STEP;
    reg [7:0] luma_meta;
    reg [7:0] luma_sync;
    reg [1:0] highlight_meta,highlight_sync;
    // Subject-first policy: recover a very dark centre even with a bright
    // window. Between FLOOR and LOW, hold rather than chase either extreme.
    // FLOOR=0 preserves the legacy highlight-priority unit-test contract.
    wire protect_reduce=(HIGHLIGHT_PROTECT!=0)&&(highlight_sync>=2)&&
        ((SUBJECT_FLOOR==0)||(luma_sync>=LUMA_LOW));
    wire protect_hold=(HIGHLIGHT_PROTECT!=0)&&(highlight_sync!=0)&&
        ((SUBJECT_FLOOR==0)||(luma_sync>=SUBJECT_FLOOR));
    reg       toggle_meta;
    reg       toggle_sync;
    reg       toggle_sync_d;

    reg [1:0] dark_streak;
    reg [1:0] bright_streak;
    reg [2:0] settle_count;
    reg       pending_write;
    reg       force_max_pending;
    reg [3:0] manual_level;
    reg write_inflight;
    reg write_seen_busy;
    // Shift-only proportional steps: large errors converge quickly, while
    // small errors use gentle steps. No pixel-rate multiplier/divider needed.
    wire severe_error = ((HIGHLIGHT_PROTECT!=0)&&(highlight_sync==3)) || (luma_sync < (LUMA_LOW >> 1)) ||
                        (luma_sync > (LUMA_HIGH + ((8'd255-LUMA_HIGH) >> 1)));
    wire [15:0] proportional_step = severe_error ? (O_ae >> 2) : (O_ae >> 4);
    wire [15:0] exposure_step = (AUTO_FAST != 0 && proportional_step > AE_STEP) ? proportional_step : AE_STEP;
    wire [15:0] gain_step = protect_reduce ? 16'd8 : (AUTO_FAST != 0 && severe_error) ? 16'd4 : 16'd1;
    wire [16:0] exposure_up = {1'b0,O_ae} + {1'b0,exposure_step};
    wire [16:0] gain_up = {1'b0,O_ag} + {1'b0,gain_step};
    wire [15:0] exposure_down_floor = AE_MIN + exposure_step;
    wire [15:0] gain_down_floor = AG_MIN + gain_step;

    // Sixteen monotonic profiles.  AE is the SC500 integration-time code and
    // AG is the register-table input (16..143 is the legal range used here).
    // Level 15 is deliberately near the sensor's legal maximum and is also
    // the reset value, so a dark camera starts at the brightest profile.
    function [15:0] profile_ae;
        input [3:0] level;
        begin
            case (level)
                4'd0:  profile_ae = AE_MIN;
                4'd1:  profile_ae = 16'd16;
                4'd2:  profile_ae = 16'd32;
                4'd3:  profile_ae = 16'd64;
                4'd4:  profile_ae = 16'd96;
                4'd5:  profile_ae = 16'd128;
                4'd6:  profile_ae = 16'd192;
                4'd7:  profile_ae = 16'd256;
                4'd8:  profile_ae = 16'd384;
                4'd9:  profile_ae = 16'd512;
                4'd10: profile_ae = 16'd704;
                4'd11: profile_ae = 16'd960;
                4'd12: profile_ae = 16'd1200;
                4'd13: profile_ae = 16'd1440;
                4'd14: profile_ae = 16'd1728;
                default: profile_ae = AE_MAX;
            endcase
        end
    endfunction

    function [15:0] profile_ag;
        input [3:0] level;
        begin
            case (level)
                4'd0:  profile_ag = AG_MIN;
                4'd1:  profile_ag = AG_MIN;
                4'd2:  profile_ag = 16'd16;
                4'd3:  profile_ag = 16'd16;
                4'd4:  profile_ag = 16'd18;
                4'd5:  profile_ag = 16'd20;
                4'd6:  profile_ag = 16'd22;
                4'd7:  profile_ag = 16'd24;
                4'd8:  profile_ag = 16'd28;
                4'd9:  profile_ag = 16'd32;
                4'd10: profile_ag = 16'd40;
                4'd11: profile_ag = 16'd48;
                4'd12: profile_ag = 16'd64;
                4'd13: profile_ag = 16'd80;
                4'd14: profile_ag = 16'd112;
                default: profile_ag = AG_MAX;
            endcase
        end
    endfunction

    wire frame_event = toggle_sync ^ toggle_sync_d;
    // Monotonic control index, not a physical gain multiplier: 00..14 are
    // shutter bands, 15 is maximum shutter at unity AG, 16..31 add AG bands.
    assign O_gain_index = (O_ae < AE_MAX) ? {1'b0,O_manual_level} :
        (O_ag <= AG_MIN) ? 5'd15 :
        (O_ag >= AG_MAX) ? 5'd31 : 5'd16 + ((O_ag-AG_MIN-16'd1) >> 3);
    assign O_luma_dbg = luma_sync;
    // In automatic mode the display reports integration-time band, not a
    // manual brightness request. Gain is controlled separately.
    assign O_manual_level = (MANUAL_LEVELS != 0) ? manual_level :
        (O_ae < 16'd16) ? 4'd0 : (O_ae < 16'd32) ? 4'd1 :
        (O_ae < 16'd64) ? 4'd2 : (O_ae < 16'd96) ? 4'd3 :
        (O_ae < 16'd128) ? 4'd4 : (O_ae < 16'd192) ? 4'd5 :
        (O_ae < 16'd256) ? 4'd6 : (O_ae < 16'd384) ? 4'd7 :
        (O_ae < 16'd512) ? 4'd8 : (O_ae < 16'd704) ? 4'd9 :
        (O_ae < 16'd960) ? 4'd10 : (O_ae < 16'd1200) ? 4'd11 :
        (O_ae < 16'd1440) ? 4'd12 : (O_ae < 16'd1728) ? 4'd13 :
        (O_ae < AE_MAX) ? 4'd14 : 4'd15;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            luma_meta    <= 8'd0;
            luma_sync    <= 8'd0;
            highlight_meta<=0;highlight_sync<=0;
            toggle_meta  <= 1'b0;
            toggle_sync  <= 1'b0;
            toggle_sync_d <= 1'b0;
        end else begin
            luma_meta     <= I_luma_mean;
            luma_sync     <= luma_meta;
            highlight_meta<=I_highlight;highlight_sync<=highlight_meta;
            toggle_meta   <= I_frame_toggle;
            toggle_sync   <= toggle_meta;
            toggle_sync_d <= toggle_sync;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_ae          <= AE_DEFAULT;
            O_ag          <= AG_DEFAULT;
            O_ae_req      <= 1'b0;
            dark_streak   <= 2'd0;
            bright_streak <= 2'd0;
            settle_count  <= 3'd0;
            pending_write <= (AUTO_START_WRITE != 0);
            write_inflight <= 1'b0;
            write_seen_busy <= 1'b0;
            force_max_pending <= (FORCE_MAX != 0);
            manual_level <= 4'd15;
            if (MANUAL_LEVELS != 0) begin
                O_ae <= profile_ae(4'd15);
                O_ag <= profile_ag(4'd15);
                // 复位后的内部档位虽然已经是 15，但传感器仍可能保持
                // 初始化表中的旧 AE/AG。预置一次待写请求，等配置 I2C
                // 空闲后自动把最高档真正写进 SC500，无需用户先按键。
                pending_write <= 1'b1;
                force_max_pending <= 1'b0;
            end else if (FORCE_MAX != 0) begin
                O_ae <= AE_MAX;
                O_ag <= AG_MAX;
            end
        end else begin
            O_ae_req <= 1'b0;
            // Product mode: a key press selects one complete profile.  The
            // frame-average loop is intentionally bypassed so the requested
            // brightness remains visible instead of being immediately undone
            // by auto exposure.  The same pending_write/I2C handshake protects
            // the sensor configuration bus from direct asynchronous writes.
            if (MANUAL_LEVELS != 0) begin
                if (pending_write && I_cam_cfg_done && I_ae_cfg_done) begin
                    O_ae_req      <= 1'b1;
                    pending_write <= 1'b0;
                end
                // 只在配置引擎完全空闲时接受新档位。O_ae_req 发出后
                // pending_write 会先清零，但 I_ae_cfg_done 要等 5 个寄存器
                // 全部写完才恢复；这段时间禁止改 O_ae/O_ag，避免同一笔
                // I2C 表的前后寄存器来自两个不同档位。
                if ((I_manual_inc ^ I_manual_dec) && !pending_write &&
                    I_cam_cfg_done && I_ae_cfg_done) begin
                    dark_streak   <= 2'd0;
                    bright_streak <= 2'd0;
                    if (I_manual_inc && (manual_level < 4'd15)) begin
                        manual_level <= manual_level + 4'd1;
                        O_ae <= profile_ae(manual_level + 4'd1);
                        O_ag <= profile_ag(manual_level + 4'd1);
                        pending_write <= 1'b1;
                    end else if (I_manual_dec && (manual_level > 4'd0)) begin
                        manual_level <= manual_level - 4'd1;
                        O_ae <= profile_ae(manual_level - 4'd1);
                        O_ag <= profile_ag(manual_level - 4'd1);
                        pending_write <= 1'b1;
                    end
                end
            end else if (FORCE_MAX != 0) begin
                // Test mode: hold both sensor controls at their legal maxima.
                // The one-shot request is delayed until the init table is idle.
                O_ae <= AE_MAX;
                O_ag <= AG_MAX;
                if (force_max_pending && I_cam_cfg_done && I_ae_cfg_done) begin
                    O_ae_req <= 1'b1;
                    force_max_pending <= 1'b0;
                end
            end else begin
                // A pending target is written only when the camera configuration
                // engine is idle.  O_ae/O_ag stay unchanged throughout the I2C
                // transaction, as required by uicfgcs500.
                if (pending_write && !write_inflight && I_cam_cfg_done && I_ae_cfg_done) begin
                    O_ae_req      <= 1'b1;
                    pending_write <= 1'b0;
                    write_inflight <= 1'b1;
                    write_seen_busy <= 1'b0;
                end

                // The sensor wrapper does not latch AE/AG: hold both until
                // busy has been observed and all five register writes finish.
                if (write_inflight) begin
                    if (!I_ae_cfg_done) write_seen_busy <= 1'b1;
                    if (write_seen_busy && I_ae_cfg_done) begin
                        write_inflight <= 1'b0;
                        settle_count <= SETTLE_INIT;
                        dark_streak <= 2'd0;
                        bright_streak <= 2'd0;
                    end
                end

                if (RESTORE_ON_DISABLE != 0 && !I_auto_enable &&
                    !write_inflight && !pending_write && !O_ae_req &&
                    I_cam_cfg_done && I_ae_cfg_done &&
                    (O_ae != AE_DEFAULT || O_ag != AG_DEFAULT)) begin
                    O_ae <= AE_DEFAULT;
                    O_ag <= AG_DEFAULT;
                    pending_write <= 1'b1;
                    dark_streak <= 0;bright_streak <= 0;
                end
                if (frame_event && !I_auto_enable) begin
                    // Do not carry a partial confirmation streak across pause.
                    dark_streak   <= 2'd0;
                    bright_streak <= 2'd0;
                end else if (frame_event && I_auto_enable &&
                             !write_inflight && !pending_write && !O_ae_req) begin
                if (settle_count != 0) begin
                    settle_count  <= settle_count - 3'd1;
                    dark_streak   <= 2'd0;
                    bright_streak <= 2'd0;
                end else if (!pending_write && I_cam_cfg_done && I_ae_cfg_done) begin
                    if (luma_sync < LUMA_LOW && !protect_hold) begin
                        bright_streak <= 2'd0;
                        if (dark_streak >= CONFIRM_LIMIT) begin
                            dark_streak <= 2'd0;
                            // Prefer exposure time over gain in dark scenes.
                            if (O_ae < AE_MAX) begin
                                if (exposure_up >= {1'b0,AE_MAX})
                                    O_ae <= AE_MAX;
                                else
                                    O_ae <= exposure_up[15:0];
                                pending_write <= 1'b1;
                            end else if (O_ag < AG_MAX) begin
                                O_ag <= (gain_up >= {1'b0,AG_MAX}) ? AG_MAX : gain_up[15:0];
                                pending_write <= 1'b1;
                            end
                        end else begin
                            dark_streak <= dark_streak + 2'd1;
                        end
                    end else if (luma_sync > LUMA_HIGH || protect_reduce) begin
                        dark_streak <= 2'd0;
                        if (bright_streak >= CONFIRM_LIMIT) begin
                            bright_streak <= 2'd0;
                            // Reduce gain first in bright scenes to preserve
                            // dynamic range, then shorten exposure if needed.
                            if (O_ag > AG_MIN) begin
                                O_ag <= (O_ag <= gain_down_floor) ? AG_MIN : O_ag - gain_step;
                                pending_write <= 1'b1;
                            end else if (O_ae > AE_MIN) begin
                                if (O_ae <= exposure_down_floor)
                                    O_ae <= AE_MIN;
                                else
                                    O_ae <= O_ae - exposure_step;
                                pending_write <= 1'b1;
                            end
                        end else begin
                            bright_streak <= bright_streak + 2'd1;
                        end
                    end else begin
                        dark_streak   <= 2'd0;
                        bright_streak <= 2'd0;
                    end
                end
                end
            end
        end
    end
endmodule
