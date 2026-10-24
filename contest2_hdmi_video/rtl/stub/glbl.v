// glbl.v — 全局信号 (安路仿真库 al_map_* 需要 glbl.gsrn / glbl.done_gwe)
`timescale 1ns/1ps
module glbl;
    reg GSR = 1'b0;      // global set/reset
    reg GTS = 1'b0;
    reg gsrn = 1'b0;     // 0=复位态, 上电后拉高
    reg done_gwe = 1'b0; // 写使能 done
    reg PUPY = 1'b0;

    initial begin
        #100;
        gsrn = 1'b1;
        done_gwe = 1'b1;
    end
endmodule
