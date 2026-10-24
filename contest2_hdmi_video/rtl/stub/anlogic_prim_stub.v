// anlogic_prim_stub.v — 安路原语行为级替身 (加密仿真模型无法在第三方 ModelSim 解密)
// 覆盖: PH1P_LOGIC_ERAM / PH1_LOGIC_ERAM (SDP 双口 RAM 用法) + PHY_GSR 全局复位
// 用法: 编译进独立库, 放在 ph1p_sim 之前覆盖搜索顺序; 综合时不用本文件.
`timescale 1ps/1ps

module PH1P_PHY_GSR (GSR, GSR_TRI, IN_N, IN_P, OUT_N, OUT_P);
    input  GSR_TRI, IN_N, IN_P;
    output GSR, OUT_N, OUT_P;
    reg gsr_r = 1'b1;
    initial begin #100; gsr_r = 1'b0; end
    assign GSR = gsr_r;
    assign OUT_N = IN_N;
    assign OUT_P = IN_P;
endmodule

module PH1_PHY_GSR (GSR, GSR_TRI, IN_N, IN_P, OUT_N, OUT_P);
    input  GSR_TRI, IN_N, IN_P;
    output GSR, OUT_N, OUT_P;
    reg gsr_r = 1'b1;
    initial begin #100; gsr_r = 1'b0; end
    assign GSR = gsr_r;
    assign OUT_N = IN_N;
    assign OUT_P = IN_P;
endmodule

module PH1P_LOGIC_ERAM #(
    parameter DATA_WIDTH_A = 20,
    parameter DATA_WIDTH_B = DATA_WIDTH_A,
    parameter ADDR_WIDTH_A = 10,
    parameter ADDR_WIDTH_B = ADDR_WIDTH_A,
    parameter DATA_DEPTH_A = (1 << ADDR_WIDTH_A),
    parameter DATA_DEPTH_B = (1 << ADDR_WIDTH_B),
    parameter BYTE_ENABLE  = 0,
    parameter REGMODE_A = "NOREG",
    parameter REGMODE_B = "NOREG",
    parameter WRITEMODE_A = "NORMAL",
    parameter WRITEMODE_B = "NORMAL",
    parameter RESETMODE_A = "SYNC",
    parameter RESETMODE_B = "SYNC",
    parameter ASYNC_RESET_RELEASE_A = "ASYNC",
    parameter ASYNC_RESET_RELEASE_B = "ASYNC",
    parameter INIT_FILE = "",
    parameter FILL_ALL = "ZERO",
    parameter ECC_ENCODE = "DISABLE",
    parameter ECC_DECODE = "DISABLE",
    parameter CLKMODE = "ASYNC",
    parameter SSROVERCE = "DISABLE",
    parameter OREGSET_A = "RESET",
    parameter OREGSET_B = "RESET",
    parameter IMPLEMENT = "20K(FAST)",
    parameter MODE = "SDP",
    parameter BYTE_SIZE = 8,
    parameter USE_BYTE_WEA = 0,
    parameter USE_BYTE_WEB = 0
)(
    output ecc_sbiterr,
    output ecc_dbiterr,
    output [DATA_WIDTH_A-1:0] doa,
    output [DATA_WIDTH_B-1:0] dob,
    input  [DATA_WIDTH_A-1:0] dia,
    input  [DATA_WIDTH_B-1:0] dib,
    input  ecc_sbiterrinj, ecc_dbiterrinj,
    input  cea, ocea, clka, wea, rsta,
    input  ceb, oceb, clkb, web, rstb,
    input  [(BYTE_ENABLE==0 ? 1 : DATA_WIDTH_A/BYTE_ENABLE)-1:0] bea,
    input  [(BYTE_ENABLE==0 ? 1 : DATA_WIDTH_B/BYTE_ENABLE)-1:0] beb,
    input  [ADDR_WIDTH_A-1:0] addra,
    input  [ADDR_WIDTH_B-1:0] addrb
);
    reg [DATA_WIDTH_A-1:0] mem [0:DATA_DEPTH_A-1];
    integer i;
    initial begin
        for (i = 0; i < DATA_DEPTH_A; i = i + 1) mem[i] = {DATA_WIDTH_A{1'b0}};
    end

    // A 口: 写 + 读 (NORMAL 模式, 同步)
    //  (修复) 真实 ERAM 读延迟: NOREG=1拍(块原生同步读), OUTREG=2拍。
    //   替身必须与硬件一致, 否则 TB 假通过而硬件错位 (motion 帧差对齐根因)
    reg [DATA_WIDTH_A-1:0] doa_r1, doa_r2;
    always @(posedge clka or posedge rsta) begin
        if (rsta) begin doa_r1 <= 0; doa_r2 <= 0; end
        else if (cea) begin
            if (wea) mem[addra] <= dia;
            doa_r1 <= mem[addra];
            doa_r2 <= doa_r1;
        end
    end
    assign doa = (REGMODE_A == "OUTREG") ? doa_r2 : doa_r1;

    // B 口: 读 (NOREG=1拍, OUTREG=2拍)
    reg [DATA_WIDTH_B-1:0] dob_r1, dob_r2;
    always @(posedge clkb or posedge rstb) begin
        if (rstb) begin dob_r1 <= 0; dob_r2 <= 0; end
        else if (ceb) begin
            dob_r1 <= mem[addrb];
            dob_r2 <= dob_r1;
        end
    end
    assign dob = (REGMODE_B == "OUTREG") ? dob_r2 : dob_r1;

    assign ecc_sbiterr = 1'b0;
    assign ecc_dbiterr = 1'b0;
endmodule

module PH1_LOGIC_ERAM #(
    parameter DATA_WIDTH_A = 20,
    parameter DATA_WIDTH_B = DATA_WIDTH_A,
    parameter ADDR_WIDTH_A = 10,
    parameter ADDR_WIDTH_B = ADDR_WIDTH_A,
    parameter DATA_DEPTH_A = (1 << ADDR_WIDTH_A),
    parameter DATA_DEPTH_B = (1 << ADDR_WIDTH_B),
    parameter BYTE_ENABLE  = 0,
    parameter REGMODE_A = "NOREG",
    parameter REGMODE_B = "NOREG",
    parameter WRITEMODE_A = "NORMAL",
    parameter WRITEMODE_B = "NORMAL",
    parameter RESETMODE_A = "SYNC",
    parameter RESETMODE_B = "SYNC",
    parameter ASYNC_RESET_RELEASE_A = "ASYNC",
    parameter ASYNC_RESET_RELEASE_B = "ASYNC",
    parameter INIT_FILE = "",
    parameter FILL_ALL = "ZERO",
    parameter ECC_ENCODE = "DISABLE",
    parameter ECC_DECODE = "DISABLE",
    parameter CLKMODE = "ASYNC",
    parameter SSROVERCE = "DISABLE",
    parameter OREGSET_A = "RESET",
    parameter OREGSET_B = "RESET",
    parameter IMPLEMENT = "20K(FAST)",
    parameter MODE = "SDP",
    parameter BYTE_SIZE = 8,
    parameter USE_BYTE_WEA = 0,
    parameter USE_BYTE_WEB = 0
)(
    output ecc_sbiterr,
    output ecc_dbiterr,
    output [DATA_WIDTH_A-1:0] doa,
    output [DATA_WIDTH_B-1:0] dob,
    input  [DATA_WIDTH_A-1:0] dia,
    input  [DATA_WIDTH_B-1:0] dib,
    input  ecc_sbiterrinj, ecc_dbiterrinj,
    input  cea, ocea, clka, wea, rsta,
    input  ceb, oceb, clkb, web, rstb,
    input  [(BYTE_ENABLE==0 ? 1 : DATA_WIDTH_A/BYTE_ENABLE)-1:0] bea,
    input  [(BYTE_ENABLE==0 ? 1 : DATA_WIDTH_B/BYTE_ENABLE)-1:0] beb,
    input  [ADDR_WIDTH_A-1:0] addra,
    input  [ADDR_WIDTH_B-1:0] addrb
);
    reg [DATA_WIDTH_A-1:0] mem [0:DATA_DEPTH_A-1];
    integer i;
    initial begin
        for (i = 0; i < DATA_DEPTH_A; i = i + 1) mem[i] = {DATA_WIDTH_A{1'b0}};
    end

    // (修复#21 同 PH1P) 真实 ERAM 读延迟: NOREG=1拍, OUTREG=2拍
    reg [DATA_WIDTH_A-1:0] doa_r1, doa_r2;
    always @(posedge clka or posedge rsta) begin
        if (rsta) begin doa_r1 <= 0; doa_r2 <= 0; end
        else if (cea) begin
            if (wea) mem[addra] <= dia;
            doa_r1 <= mem[addra];
            doa_r2 <= doa_r1;
        end
    end
    assign doa = (REGMODE_A == "OUTREG") ? doa_r2 : doa_r1;

    reg [DATA_WIDTH_B-1:0] dob_r1, dob_r2;
    always @(posedge clkb or posedge rstb) begin
        if (rstb) begin dob_r1 <= 0; dob_r2 <= 0; end
        else if (ceb) begin
            dob_r1 <= mem[addrb];
            dob_r2 <= dob_r1;
        end
    end
    assign dob = (REGMODE_B == "OUTREG") ? dob_r2 : dob_r1;

    assign ecc_sbiterr = 1'b0;
    assign ecc_dbiterr = 1'b0;
endmodule

// AL_DFF_X — 安路 DFF 原语 (divider IP 用), 端口由例化反推
module AL_DFF_X (
    input  wire ar, as, clk, d, en, sr, ss,
    output reg  q
);
    always @(posedge clk or posedge ar or posedge as or posedge sr or posedge ss) begin
        if (ar || sr) q <= 1'b0;
        else if (as || ss) q <= 1'b1;
        else if (en) q <= d;
    end
endmodule
