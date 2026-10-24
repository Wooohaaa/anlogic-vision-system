// Frozen verified v47 baseline. Test-only; not a production compilation unit.
`timescale 1ns/1ps
// One owner at a time, one-cycle synchronous read, no storage/output reset.
// Queue -> distance -> hull may reuse addresses only after the previous
// owner's final read. Contents are initialized by the owning algorithm.
module v47_ua_hand_scratch_ram #(parameter WORDS=14400)(
 input I_clk,I_read,I_write,
 input[13:0]I_address,
 input[15:0]I_data,
 output reg[15:0]O_data
);
/* fehdl force_ram=1, ram_style="bram" */ reg[15:0]memory[0:WORDS-1];
always @(posedge I_clk)begin
 if(I_read)O_data<=memory[I_address];
 if(I_write)memory[I_address]<=I_data;
end
endmodule
