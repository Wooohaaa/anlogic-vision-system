// Simulation-only model of the existing blk_mem_gen_zhenghe wrapper.
// The production wrapper specifies REGMODE_B=NOREG: one synchronous read.
// Not part of TD source lists; does not replace the hardware primitive.
module blk_mem_gen_zhenghe(
    input [31:0] dia,dib,input [10:0] addra,addrb,
    input wea,web,clka,clkb,output reg [31:0] dob,output [31:0] doa
);
    reg [31:0] mem[0:2047];
    always @(posedge clka) if(wea) mem[addra]<=dia;
    always @(posedge clkb) dob<=mem[addrb];
    assign doa=32'd0;
endmodule
