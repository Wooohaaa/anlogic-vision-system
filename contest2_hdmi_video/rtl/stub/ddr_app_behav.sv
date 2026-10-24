// ddr_app_behav.sv — 行为级 DDR2 替身 (A3)
// 模拟 ph1p35_324_ddr_wrapper 用户侧 (app 口) 协议:
//   写: app_en && cmd[0]==0 && wdf_wren 同拍, 128bit
//   读: app_en && cmd[0]==1, 固定延迟 LAT 拍后 rd_valid+rd_data
//   app_rdy/wdf_rdy 带轻度随机反压 (官方注释: ready 拉低后仍可压 8 个)
// 地址单位: 16bit 字 (video_in 每拍 +8 => 128bit 对齐), mem 以 128bit 字索引
`timescale 1ns/1ps
module ddr_app_behav #(
    parameter LAT = 32
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        app_en,
    input  wire [2:0]  app_cmd,
    input  wire [24:0] app_addr,
    input  wire        wdf_wren,
    input  wire [127:0] wdf_data,
    input  wire        wdf_end,
    output reg         app_rdy,
    output reg         wdf_rdy,
    output reg         rd_valid,
    output wire [127:0] rd_data
);
    bit [127:0] mem [bit [21:0]];   // 128bit 字索引 = app_addr[24:3]

    // 读流水线 (固定延迟, 保序)
    bit [24:0] pipe_addr [0:LAT-1];
    bit        pipe_v    [0:LAT-1];
    reg [127:0] rd_data_r;
    assign rd_data = rd_data_r;

    // 轻度反压: 伪随机 occasional stall
    reg [15:0] lfsr = 16'hACE1;
    always @(posedge clk) lfsr <= {lfsr[14:0], lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
    wire stall = (lfsr[6:0] == 7'h2A);   // ~0.8% 概率

    wire accept = app_en && app_rdy && wdf_rdy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            app_rdy <= 1'b0;
            wdf_rdy <= 1'b0;
        end else begin
            app_rdy <= !stall;
            wdf_rdy <= !stall;
        end
    end

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < LAT; i = i + 1) begin
                pipe_v[i] <= 1'b0;
                pipe_addr[i] <= '0;
            end
            rd_valid <= 1'b0;
            rd_data_r <= '0;
        end else begin
            rd_valid <= 1'b0;
            // 流水推进
            for (i = LAT-1; i > 0; i = i - 1) begin
                pipe_v[i]    <= pipe_v[i-1];
                pipe_addr[i] <= pipe_addr[i-1];
            end
            pipe_v[0]    <= 1'b0;
            if (accept) begin
                if (!app_cmd[0]) begin
                    if (wdf_wren) begin
                        mem[app_addr[24:3]] = wdf_data;
                    end
                end else begin
                    pipe_v[0]    <= 1'b1;
                    pipe_addr[0] <= app_addr;
                end
            end
            // 出口
            if (pipe_v[LAT-1]) begin
                rd_valid  <= 1'b1;
                rd_data_r <= mem[pipe_addr[LAT-1][24:3]];
            end
        end
    end

    // 对齐检查
    always @(posedge clk) begin
        if (accept && !app_cmd[0] && app_addr[2:0] != 3'd0)
            $display("[%t] ERROR: ddr_app_behav 写地址未 128bit 对齐: %h", $time, app_addr);
    end

    // 计数器 (调试用)
    integer wr_accepts = 0, rd_accepts = 0;
    always @(posedge clk) begin
        if (accept && !app_cmd[0]) wr_accepts = wr_accepts + 1;
        if (accept &&  app_cmd[0]) rd_accepts = rd_accepts + 1;
    end
endmodule
