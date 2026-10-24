// anlogic_ip_stub.v — 物理层 IP 行为级替身 (elaboration 验证用)
// 替换官方 DDR IP 和 MIPI DPHY 整块, 避免编译 26+ 文件全链+加密体
// 端口精确匹配, 行为简单占位 (tb_elab 只验层次连通, 不跑数据)
`timescale 1ps/1ps

// ===== DDR2 IP 替身 =====
// 端口声明: ddr2.v 头部 (26 接口)
module ddr2 (
    input                     ref_clk,
    input                     sys_rst_n,
    input                     apb_pclk,
    input                     apb_prst_n,
    output                    apb_pready,
    input                     apb_psel,
    input                     apb_penable,
    input                     apb_pwrite,
    input  [15:0]             apb_paddr,
    input  [31:0]             apb_pwdata,
    output [31:0]             apb_prdata,
    output                    dhi_clk,
    output                    cfg_clk,
    output                    cfg_rst_n,
    output                    ddrphy_rst_n,
    output                    ddrphy_rdy,
    input  [24:0]             paxi_awaddr,
    input                     paxi_awvalid,
    output                    paxi_awready,
    input  [127:0]            paxi_wdata,
    input  [15:0]             paxi_wstrb,
    input                     paxi_wvalid,
    input                     paxi_wlast,
    output                    paxi_wready,
    input  [24:0]             paxi_araddr,
    input                     paxi_arvalid,
    output                    paxi_arready,
    output [127:0]            paxi_rdata,
    output                    paxi_rlast,
    output                    paxi_rvalid,
    input                     paxi_rready,
    output [0:0]              ddr_ck_p,
    output [0:0]              ddr_ck_n,
    output [0:0]              ddr_cke,
    output [0:0]              ddr_odt,
    output [0:0]              ddr_cs_n,
    output [0:0]              ddr_ras_n,
    output [0:0]              ddr_cas_n,
    output [0:0]              ddr_we_n,
    output [1:0]              ddr_ba,
    output [12:0]             ddr_addr,
    inout  [1:0]              ddr_dqs_p,
    inout  [1:0]              ddr_dqs_n,
    inout  [15:0]             ddr_dq,
    inout  [1:0]              ddr_dm
);
    reg [2:0] cnt;
    always @(posedge ref_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) cnt <= 0; else if (cnt < 5) cnt <= cnt + 1;
    end
    assign ddrphy_rdy   = (cnt >= 3);
    assign dhi_clk      = ref_clk;
    assign cfg_clk      = ref_clk;
    assign cfg_rst_n    = sys_rst_n;
    assign ddrphy_rst_n = sys_rst_n;
    assign paxi_awready = 1'b1;
    assign paxi_wready  = 1'b1;
    assign paxi_arready = 1'b1;
    assign paxi_rvalid  = 1'b0;
    assign paxi_rdata   = 128'd0;
    assign paxi_rlast   = 1'b0;
    assign apb_pready   = 1'b1;
    assign apb_prdata   = 32'd0;
    assign ddr_ck_p = 1'b0;  assign ddr_ck_n = 1'b1;
    assign ddr_cke = 1'b1;   assign ddr_odt = 1'b0;
    assign ddr_cs_n = 1'b0;  assign ddr_ras_n = 1'b1;
    assign ddr_cas_n = 1'b1; assign ddr_we_n = 1'b1;
    assign ddr_ba = 2'd0;    assign ddr_addr = 13'd0;
endmodule

// ===== MIPI DPHY RX wrapper 替身 =====
// 端口: design_top_user 例化处 (LANE_NUM=2, BYTE_NUM=1)
module mipi_dphy_rx_ph1p_mipiio_wrapper #(
    parameter DPHY_RX_LOCATION = "DPHY0",
    parameter HS_EQUALIZER     = "0dB",
    parameter HS_VGA_GAIN      = "0dB",
    parameter LANE_NUM = 4,
    parameter BYTE_NUM = 1
)(
    input  wire                    I_lp_clk,
    input  wire                    I_rst,
    input  wire [5:0]              I_clk_lane_in_delay,
    input  wire [5:0]              I_data_lane0_in_delay,
    input  wire [5:0]              I_data_lane1_in_delay,
    input  wire [5:0]              I_data_lane2_in_delay,
    input  wire [5:0]              I_data_lane3_in_delay,
    input  wire [LANE_NUM-1:0]     I_lane_invert,
    output wire                    O_hs_rx_clk,
    output wire                    O_hs_rx_valid,
    output wire [LANE_NUM*BYTE_NUM*8-1:0] O_hs_rx_data,
    output wire                    O_lp_rx_lane0_p,
    output wire                    O_lp_rx_lane0_n,
    input  wire                    I_lp_tx_en,
    input  wire                    I_lp_tx_lane0_p,
    input  wire                    I_lp_tx_lane0_n,
    output wire [LANE_NUM-1:0]     O_lane_match_error,
    output wire [LANE_NUM-1:0]     O_lane_error,
    inout  wire                    IO_rx_clk_pad_n,
    inout  wire                    IO_rx_clk_pad_p,
    inout  wire [3:0]              IO_rx_data_pad_n,
    inout  wire [3:0]              IO_rx_data_pad_p
);
    // 行为: 输出 HS 时钟 (固定频率片段), 有效拉低
    reg [3:0] cnt;
    always @(posedge I_lp_clk or posedge I_rst) begin
        if (I_rst) cnt <= 0; else cnt <= cnt + 1;
    end
    assign O_hs_rx_clk   = cnt[1];
    assign O_hs_rx_valid = 1'b0;
    assign O_hs_rx_data  = {LANE_NUM*BYTE_NUM*8{1'b0}};
    assign O_lp_rx_lane0_p = 1'b1;
    assign O_lp_rx_lane0_n = 1'b0;
    assign O_lane_match_error = {LANE_NUM{1'b0}};
    assign O_lane_error       = {LANE_NUM{1'b0}};
endmodule

// ===== PLL 整模块替身 ===== (接口同官方 PLL.v: refclk/reset → clk0/1/4/5 + lock)
// clk0=100M (÷2), clk1=24M (÷25), clk4=52M (÷25 from 2600M? 简化: 按比例), clk5=260M (÷1?)
// 仿真用途: 只验证层次, 频率精确性无关 — 输出反转时钟即可
module PLL (
    input  wire refclk,
    output wire clk0_out,
    output wire clk1_out,
    output wire clk4_out,
    output wire clk5_out,
    output wire lock,
    input  wire reset
);
    reg [3:0] div0;  reg [4:0] div1;  reg [4:0] div4;
    reg lock_r = 0;
    always @(posedge refclk or posedge reset) begin
        if (reset) begin div0 <= 0; div1 <= 0; div4 <= 0; lock_r <= 0; end
        else begin
            div0 <= div0 + 1; div1 <= div1 + 1; div4 <= div4 + 1;
            if (div1 == 5'd24) lock_r <= 1;
        end
    end
    assign clk0_out = div0[0];
    assign clk1_out = div1[4];
    assign clk4_out = div4[4];
    assign clk5_out = ~refclk;
    assign lock     = lock_r;
endmodule

// ===== ODDR 原语替身 (lane_lvds_10_1 用) =====
module PH1P_LOGIC_ODDR (
    input  wire clk, rst, d1, d0,
    output wire q
);
    // 简化行为: 高电平相位输出 d1, 低电平相位输出 d0 (单 always 仿真模型)
    reg q_r;
    always @(posedge clk or negedge clk or posedge rst) begin
        if (rst) q_r <= 1'b0;
        else     q_r <= clk ? d1 : d0;
    end
    assign q = q_r;
endmodule
module PH1_LOGIC_ODDR (
    input  wire clk, rst, d1, d0,
    output wire q
);
    PH1P_LOGIC_ODDR u ( .clk(clk), .rst(rst), .d1(d1), .d0(d0), .q(q) );
endmodule

// PH1P_LOGIC_HD_ODDR — HDIO(HD bank) 专用输出 DDR 替身 (design_top 摄像头 24MHz 转发用)
module PH1P_LOGIC_HD_ODDR (
    input  wire clk, rst, d1, d0,
    output wire q
);
    // HDIO is not the HRIO primitive: UG1310 section 36 assigns D0 to
    // the positive edge and D1 to the negative edge.
    reg q_r;
    always @(posedge clk or negedge clk or posedge rst) begin
        if (rst) q_r <= 1'b0;
        else q_r <= clk ? d0 : d1;
    end
    assign q = q_r;
endmodule

// divider — TD 除法器 IP 行为级替身 (官方是综合后门级网表, 依赖 AL_MAP_* 原语)
// 端口同官方 divider_gate.v: 迭代除法, 8 拍延迟
module divider #(
    parameter PIPLE = 50,
    parameter S_DEN = "UNSIGNED",
    parameter S_NUM = "UNSIGNED",
    parameter W_DEN = 32,
    parameter W_NUM = 48,
    parameter W_REM = 32
)(
    input  wire clk,
    input  wire [31:0] denominator,
    input  wire [47:0] numerator,
    input  wire rst,
    input  wire start,
    output reg  done,
    output reg  [47:0] quotient,
    output reg  [31:0] remainder
);
    reg [3:0] cnt;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cnt <= 0; done <= 0;
        end else if (start) begin
            cnt <= 1; done <= 0;
            if (denominator != 0) begin
                quotient  <= numerator / denominator;
                remainder <= numerator % denominator;
            end else begin
                quotient  <= 48'hFFFF_FFFF_FFFF;
                remainder <= 32'hFFFFFFFF;
            end
        end else if (cnt != 0) begin
            if (cnt == 4'd8) begin done <= 1; cnt <= 0; end
            else cnt <= cnt + 1;
        end
    end
endmodule
