// anlogic_enc_stub.v — 加密单元替身 (仅仿真用; 综合用官方 .enc 文件)
// 反推来源: 消费者例化处端口 (ph1p_mipiio_rx_wrapper.sv / hdmi_tx.v)
`timescale 1ps/1ps

// hs_detect: LP 状态检测 (替身: 简单差分比较)
module hs_detect (
    input  wire I_clk,
    input  wire I_rst_n,
    input  wire I_lp_p,
    input  wire I_lp_n,
    output reg  O_hs_en
);
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) O_hs_en <= 1'b0;
        else          O_hs_en <= ~I_lp_p & I_lp_n;   // LP-11 空闲态反相判定(占位)
    end
endmodule

// byte_aligner_wrapper: lane 字节对齐 (替身: 直通)
module byte_aligner_wrapper #(
    parameter LANE_NUM = 4,
    parameter BYTE_NUM = 1
)(
    input  wire                       I_clk,
    input  wire                       I_rst,
    input  wire                       I_hs_rx_valid,
    input  wire [LANE_NUM*BYTE_NUM*8-1:0] I_hs_rx_data,
    output wire                       O_byte_aligne_valid,
    output wire [LANE_NUM*BYTE_NUM*8-1:0] O_byte_aligne_data,
    output wire [LANE_NUM-1:0]        O_lane_error
);
    assign O_byte_aligne_valid = I_hs_rx_valid & ~I_rst;
    assign O_byte_aligne_data  = I_hs_rx_data;
    assign O_lane_error        = {LANE_NUM{1'b0}};
endmodule

// channel_aligner_wrapper: 通道间对齐 (替身: 直通)
module channel_aligner_wrapper #(
    parameter CH_NUM = 4,
    parameter DATA_WIDTH = 8
)(
    input  wire                   I_clk,
    input  wire                   I_rst_n,
    input  wire                   I_ch_valid,
    input  wire [CH_NUM*DATA_WIDTH-1:0] I_ch_data,
    output wire                   O_ch_aligner_valid,
    output wire [CH_NUM*DATA_WIDTH-1:0] O_ch_aligner_data
);
    assign O_ch_aligner_valid = I_ch_valid & I_rst_n;
    assign O_ch_aligner_data  = I_ch_data;
endmodule

// byte_aligner / channel_aligner 底层 (若被 wrapper 引用则占位; wrapper 已替身则不引用)
module byte_aligner (); endmodule
module channel_aligner (); endmodule

// hdmi_1_4b_transmitter_core_wrapper: HDMI 发送核替身 (行为: 接收 AXIS 24bit RGB,
// 原样输出 TMDS 占位数据; 不产生真实 TMDS 时序 — 输出链正确性靠上板验证)
module hdmi_1_4b_transmitter_core_wrapper #(
    parameter DEVICE = "PH1P",
    parameter HTOTAL = 1344,
    parameter HSA = 24,
    parameter HFP = 160,
    parameter HBP = 136,
    parameter HACTIVE = 1024,
    parameter VTOTAL = 635,
    parameter VSA = 2,
    parameter VFP = 12,
    parameter VBP = 21,
    parameter VACTIVE = 600,
    parameter VIDEO_VIC = 0,
    parameter VIDEO_TPG = "Disable",
    parameter VIDEO_FORMAT = "RGB",
    parameter AUDIO_SAMPLE_RATE = "48K",
    parameter IIC_SCL_DIV = 125
)(
    input  wire        I_pixel_clk,
    input  wire        I_rst,
    input  wire        I_edid_read_trig,
    output wire        O_edid_read_valid,
    output wire [7:0]  O_edid_read_data,
    input  wire        I_axis_s_user,
    input  wire        I_axis_s_valid,
    input  wire        I_axis_s_last,
    input  wire [23:0] I_axis_s_data,
    output wire        O_axis_s_ready,
    input  wire        I_audio_valid,
    input  wire        I_audio_left_data,
    input  wire        I_audio_right_data,
    input  wire        I_acr_valid,
    input  wire [19:0] I_acr_cts,
    input  wire [19:0] I_acr_n,
    output wire        O_video_locked,
    output wire        O_ddc_scl,
    inout  wire        IO_ddc_sda,
    output wire [7:0]  O_ch0_tmds_data,
    output wire [7:0]  O_ch1_tmds_data,
    output wire [7:0]  O_ch2_tmds_data,
    output wire [7:0]  O_clk_tmds_data
);
    assign O_axis_s_ready   = 1'b1;
    assign O_edid_read_valid = 1'b0;
    assign O_edid_read_data  = 8'd0;
    assign O_video_locked    = 1'b1;
    // TMDS 占位: 用像素数据低 8bit (仅为层次连通, 非真实编码)
    assign O_ch0_tmds_data = I_axis_s_data[7:0];
    assign O_ch1_tmds_data = I_axis_s_data[15:8];
    assign O_ch2_tmds_data = I_axis_s_data[23:16];
    assign O_clk_tmds_data = 8'h1E;  // 占位时钟图案
endmodule
