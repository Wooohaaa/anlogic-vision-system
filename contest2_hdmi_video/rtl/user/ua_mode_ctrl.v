// ua_mode_ctrl.v — 四键控制器 (10ms 消抖)
//
// 板卡 8_key_sw 示例把四个瞬时按键接到 D5/A9/B9/C7，并且按键为
// 上拉、按下为低电平。本模块在 100MHz 控制域完成 2FF 同步和稳定采样：
//   I_button[0] / KEY1(D5): 图像处理模式下一个 (0→1→…→6→0)
//   I_button[1] / KEY2(A9): 图像处理模式上一个 (0←1←…←6←0)
//   I_button[2] / KEY3(B9): 顶层使用稳定状态切换自动白平衡
//   I_button[3] / KEY4(C7): 顶层使用稳定状态切换自动曝光/模拟增益
// 兼容保留 O_exposure_inc/dec 脉冲接口。
//
// O_button_state 是消抖后的“按下有效高电平”状态，供 24MHz 相机配置域
// 做两级同步并检测边沿；四个 pulse 输出只在一次稳定按下时出现一拍。
// 白平衡仍由 ISP 的 AWB 自动完成，本模块不直接写白平衡寄存器。
`timescale 1ns/1ps
module ua_mode_ctrl #(
    // 按键控制器在稳定的 100MHz 系统控制时钟域运行。
    // 10ms @ 100MHz = 1,000,000 拍；21bit 足够覆盖该计数范围。
    parameter DEBOUNCE_CYCLES = 21'd1000000,  // 10ms @ 100MHz
    parameter [2:0] INITIAL_MODE = 3'd0,     // 复位后生效的默认算法模式
    parameter integer KEY2_TRACKING = 0    // 1: KEY2 reserved for MCU tracking
)(
    input  wire       I_clk,        // 稳定的系统控制域时钟（建议 100MHz）
    input  wire       I_rst_n,
    input  wire [3:0] I_button,     // 低有效 KEY1..KEY4 (本模块内 2FF 同步)
    output reg  [2:0] O_algo_mode,
    output reg        O_mode_changed,
    output reg        O_mode_next,
    output reg        O_mode_prev,
    output reg        O_exposure_inc,
    output reg        O_exposure_dec,
    output reg  [3:0] O_button_state // 消抖后的按下状态，高=按下
);
    // ---- 2FF 同步 (按键为异步输入) ----
    reg [3:0] s0, s1;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            s0 <= 4'b1111;
            s1 <= 4'b1111;
        end else begin
            s0 <= I_button;
            s1 <= s0;
        end
    end

    // ---- 完整四键稳定采样 ----
    // 只有同步后的整组输入连续保持 DEBOUNCE_CYCLES 拍才提交，既能消除
    // 机械抖动，也避免一个按键动作期间产生多个模式步进。
    reg [3:0] key_candidate;                  // 正在等待确认的原始电平
    reg [3:0] key_stable;                     // 消抖后稳定电平 (高=释放)
    reg [31:0] debounce_cnt;
    localparam [31:0] DEBOUNCE_LIMIT =
        (DEBOUNCE_CYCLES < 1) ? 32'd0 : DEBOUNCE_CYCLES - 1;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_algo_mode <= INITIAL_MODE;
            O_mode_changed <= 1'b0;
            O_mode_next <= 1'b0;
            O_mode_prev <= 1'b0;
            O_exposure_inc <= 1'b0;
            O_exposure_dec <= 1'b0;
            O_button_state <= 4'b0000;
            key_candidate <= 4'b1111;
            key_stable <= 4'b1111;
            debounce_cnt <= 32'd0;
        end else begin
            O_mode_changed <= 1'b0;
            O_mode_next <= 1'b0;
            O_mode_prev <= 1'b0;
            O_exposure_inc <= 1'b0;
            O_exposure_dec <= 1'b0;

            if (s1 != key_candidate) begin
                key_candidate <= s1;
                debounce_cnt <= 32'd0;
            end else if (debounce_cnt < DEBOUNCE_LIMIT) begin
                debounce_cnt <= debounce_cnt + 32'd1;
            end else if (key_candidate != key_stable) begin
                // 仅对“释放→按下”(1→0) 产生一次动作；释放只更新状态。
                if (key_stable[0] && !key_candidate[0])
                    O_mode_next <= 1'b1;
                if (KEY2_TRACKING == 0 && key_stable[1] && !key_candidate[1])
                    O_mode_prev <= 1'b1;
                if (key_stable[2] && !key_candidate[2])
                    O_exposure_inc <= 1'b1;
                if (key_stable[3] && !key_candidate[3])
                    O_exposure_dec <= 1'b1;

                // 同时按下 KEY1/KEY2 时不改变模式，避免方向不确定；单键
                // 则按 0..6 环形计数，保持七种图像处理模式的定义不变。
                if (key_stable[0] && !key_candidate[0] &&
                    (KEY2_TRACKING != 0 || !(key_stable[1] && !key_candidate[1]))) begin
                    if (O_algo_mode >= 3'd6)
                        O_algo_mode <= 3'd0;
                    else
                        O_algo_mode <= O_algo_mode + 3'd1;
                    O_mode_changed <= 1'b1;
                end else if (KEY2_TRACKING == 0 && key_stable[1] && !key_candidate[1] &&
                             !(key_stable[0] && !key_candidate[0])) begin
                    if (O_algo_mode == 3'd0)
                        O_algo_mode <= 3'd6;
                    else
                        O_algo_mode <= O_algo_mode - 3'd1;
                    O_mode_changed <= 1'b1;
                end

                key_stable <= key_candidate;
                O_button_state <= ~key_candidate;
            end
        end
    end
endmodule

// --------------------------------------------------------------------------
// TD 6.2.1 compatibility fallback
//
// Some GUI-created syn_1 projects omit the last-added source-list member.
// Keep the legacy module name in this established source file so an older
// cached design_top_user (which still instantiates ua_detect_switch_ctrl)
// cannot elaborate it as a black box.  The standalone source uses the same
// guard, therefore a regenerated project that compiles both files still has
// exactly one definition.
// --------------------------------------------------------------------------
`ifndef UA_DETECT_SWITCH_CTRL_V
`define UA_DETECT_SWITCH_CTRL_V
module ua_detect_switch_ctrl #(
    parameter integer WIDTH = 6,
    parameter integer DEBOUNCE_CYCLES = 100000,
    parameter integer SW_ACTIVE_LOW = 1
)(
    input  wire             I_clk,
    input  wire             I_rst_n,
    input  wire [WIDTH-1:0] I_switch,
    output reg  [WIDTH-1:0] O_enable
);
    localparam [WIDTH-1:0] RELEASED_VALUE =
        (SW_ACTIVE_LOW != 0) ? {WIDTH{1'b1}} : {WIDTH{1'b0}};

    reg [WIDTH-1:0] switch_sync0;
    reg [WIDTH-1:0] switch_sync1;
    reg [WIDTH-1:0] candidate;
    reg [31:0]      stable_count;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            switch_sync0 <= RELEASED_VALUE;
            switch_sync1 <= RELEASED_VALUE;
        end else begin
            switch_sync0 <= I_switch;
            switch_sync1 <= switch_sync0;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            candidate    <= RELEASED_VALUE;
            stable_count <= 32'd0;
            O_enable     <= {WIDTH{1'b0}};
        end else if (switch_sync1 != candidate) begin
            candidate    <= switch_sync1;
            stable_count <= 32'd0;
        end else if (stable_count < DEBOUNCE_CYCLES - 1) begin
            stable_count <= stable_count + 32'd1;
        end else if (SW_ACTIVE_LOW != 0) begin
            O_enable <= ~candidate;
        end else begin
            O_enable <= candidate;
        end
    end
endmodule
`endif
