// w155_d512_fifo_fwft.sv — w155_d512_fifo 的 FWFT 行为级替身 (A3)
// 背景: 官方 ip_source 里的 soft_fifo 行为模型是 non-showahead (dout 滞后 re 一拍),
// 但 mc_to_user_interface 组合使用 dout (O_mc_app_en 与 S_fifo_rd_data 同拍),
// 上板可工作 ⇒ 真实 ERAM FIFO 为 show-ahead (FWFT)。仿真用本替身匹配真实行为。
// 仅用于仿真; 综合时仍用官方 ip_source。
`timescale 1ns/1ps
module w155_d512_fifo (
    input               rst,
    input               clk,
    input               we,
    input      [154:0]  di,
    input               re,
    output      [154:0] dout,
    output              valid,
    output              full_flag,
    output              empty_flag,
    output              afull,
    output              aempty,
    output      [8:0]   wrusedw,
    output      [8:0]   rdusedw
);
    reg [154:0] mem [0:511];
    reg [8:0]   waddr = 0, raddr = 0;
    wire [9:0]  count = waddr - raddr;          // 同时钟域 (mc 单时钟)

    assign empty_flag = (waddr == raddr);
    assign full_flag  = (count == 10'd512);
    assign afull      = (count >= 10'd500);
    assign aempty     = (count <= 10'd2);
    assign wrusedw    = count[8:0];
    assign rdusedw    = count[8:0];
    // FWFT: dout 组合读出队首, re 弹出
    assign dout  = mem[raddr];
    assign valid = !empty_flag;

    wire wr_ok = we  && !full_flag;
    wire rd_ok = re  && !empty_flag;

    always @(posedge clk or posedge rst) begin
        if (rst) waddr <= 0;
        else if (wr_ok) begin
            mem[waddr] <= di;
            waddr <= waddr + 1'b1;
        end
    end
    always @(posedge clk or posedge rst) begin
        if (rst) raddr <= 0;
        else if (rd_ok) raddr <= raddr + 1'b1;
    end
endmodule
