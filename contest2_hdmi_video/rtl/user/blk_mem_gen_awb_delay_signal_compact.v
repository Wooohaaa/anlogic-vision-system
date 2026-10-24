// Compact replacement for the generated AWB delay RAM.
//
// The vendor IP shipped with the contest project is fixed at 96x2048 words.
// At the active 1280x720 geometry, signal_delay addresses only 320 words per
// line. Keeping the same dual-port, one-cycle synchronous-read contract while
// exposing the real depth lets TD pack the memory into fewer ERAMs.
`timescale 1ns/1ps

module blk_mem_gen_awb_delay_signal_compact #(
    parameter integer DATA_WIDTH_A = 96,
    parameter integer ADDR_WIDTH_A = 9,
    parameter integer DATA_DEPTH_A = 512,
    parameter integer DATA_WIDTH_B = DATA_WIDTH_A,
    parameter integer ADDR_WIDTH_B = ADDR_WIDTH_A,
    parameter integer DATA_DEPTH_B = DATA_DEPTH_A
)(
    output wire [DATA_WIDTH_A-1:0] doa,
    input  wire [DATA_WIDTH_A-1:0] dia,
    input  wire [ADDR_WIDTH_A-1:0] addra,
    input  wire                     clka,
    input  wire                     wea,
    output wire [DATA_WIDTH_B-1:0] dob,
    input  wire [DATA_WIDTH_B-1:0] dib,
    input  wire [ADDR_WIDTH_B-1:0] addrb,
    input  wire                     clkb,
    input  wire                     web
);
    // TD rejects the vendor primitive for this legal-but-non-native width /
    // depth combination.  Canonical true-dual-port inference keeps the
    // original one-cycle synchronous-read contract and lets the mapper choose
    // ERAM tiles available in the target device.
    // Tang Dynasty accepts the Anlogic style name "bram" (not the Xilinx
    // spelling "block").  Keeping the hint vendor-native avoids a fallback
    // to LUT RAM while removing the SYN-5041 style warning.
    (* ram_style = "bram" *) reg [DATA_WIDTH_A-1:0] mem_a [0:DATA_DEPTH_A-1];
    reg [DATA_WIDTH_A-1:0] doa_r;
    reg [DATA_WIDTH_B-1:0] dob_r;

    always @(posedge clka) begin
        if (wea)
            mem_a[addra] <= dia;
        doa_r <= mem_a[addra];
    end

    always @(posedge clkb) begin
        if (web)
            mem_a[addrb] <= dib;
        dob_r <= mem_a[addrb];
    end

    assign doa = doa_r;
    assign dob = dob_r;
endmodule
