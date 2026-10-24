// ============================================================================
// ua_detect_switch_ctrl : 拨动开关同步、消抖与有效电平归一化
//
// 开关来自板外/板上异步 IO，不能直接送入 CSI 图像时钟域。这里先在
// 稳定的 100 MHz 系统时钟域完成两级同步和 1 ms 稳定判定，再由顶层用
// 两级寄存器跨到相机域。开发板 8_key_sw 例程的输入是低有效并带上拉，
// 所以默认 SW_ACTIVE_LOW=1：引脚读 0 表示拨到 ON，输出 enable=1。
//
// 位分配（I_switch[3:0] 对应板上 SW1..SW4）：
//   [0] motion + track：运动检测和颜色/形状识别共用 SW1
//   [1] ArUco 标记检测开关（独立给 MCU）
//   [2] 预留（手势识别已移除）
//   [3] digit   固定 ROI 数字识别
// ============================================================================
`ifndef UA_DETECT_SWITCH_CTRL_V
`define UA_DETECT_SWITCH_CTRL_V

`timescale 1ns/1ps

module ua_detect_switch_ctrl #(
    parameter integer WIDTH = 4,
    parameter integer DEBOUNCE_CYCLES = 100000, // 1 ms @ 100 MHz
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

    // Asynchronous input synchronizer.
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            switch_sync0 <= RELEASED_VALUE;
            switch_sync1 <= RELEASED_VALUE;
        end else begin
            switch_sync0 <= I_switch;
            switch_sync1 <= switch_sync0;
        end
    end

    // One shared debounce timer is sufficient for toggle switches: a change
    // in any bit restarts the timer and the whole switch bank is committed
    // atomically after all bits have been stable for the debounce interval.
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            candidate    <= RELEASED_VALUE;
            stable_count <= 32'd0;
            O_enable      <= {WIDTH{1'b0}};
        end else if (switch_sync1 != candidate) begin
            candidate     <= switch_sync1;
            stable_count  <= 32'd0;
        end else if (stable_count < DEBOUNCE_CYCLES - 1) begin
            stable_count <= stable_count + 32'd1;
        end else begin
            if (SW_ACTIVE_LOW != 0)
                O_enable <= ~candidate;
            else
                O_enable <= candidate;
        end
    end
endmodule

`endif
