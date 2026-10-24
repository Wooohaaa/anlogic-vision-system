`timescale 1ns/1ps
// Exact-depth replacement for the 2048-word generated demosaic line RAMs.
// Only port A writes and port B reads; both original clocks are tied to I_clk by the
// maintained callers. One-cycle synchronous read, old data on same-address
// read/write. No reset of storage or output (same as the original NOREG IP).
// At 1280 pixels / 4 lanes, only addresses 0..319 are reachable.
module ua_demosaic_line_ram #(
    parameter DATA_WIDTH=33,
    parameter DEPTH=320
)(
    input I_clk, wea,
    input [10:0] addra,
    input [DATA_WIDTH-1:0] dia,
    input [10:0] addrb,
    output reg [DATA_WIDTH-1:0] dob
);
// Keep the physical depth native (512 for 320 used words). Otherwise TD
// inserts an out-of-range mux after the read register and falls back to LUT
// RAM. The callers wrap at DEPTH; assertions below enforce that contract.
localparam ADDR_W=DEPTH<=1 ? 1 : $clog2(DEPTH);
localparam PHYSICAL_DEPTH=1<<ADDR_W;
/* fehdl force_ram=1, ram_style="bram" */ reg [DATA_WIDTH-1:0] memory[0:PHYSICAL_DEPTH-1];
always @(posedge I_clk) begin
    dob<=memory[addrb[ADDR_W-1:0]];
    if(wea) memory[addra[ADDR_W-1:0]]<=dia;
end
`ifndef SYNTHESIS
initial if(DEPTH<1 || DEPTH>2048 || DATA_WIDTH<1)
    $fatal(1,"invalid demosaic line RAM geometry");
always @(posedge I_clk) if(wea && addra>=DEPTH)
    $fatal(1,"demosaic line write out of range");
always @(posedge I_clk) if(addrb>=DEPTH)
    $fatal(1,"demosaic line read out of range");
`endif
endmodule
