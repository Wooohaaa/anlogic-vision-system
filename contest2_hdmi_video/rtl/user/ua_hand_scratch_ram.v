`timescale 1ns/1ps
// One owner at a time, one-cycle synchronous read, no storage/output reset.
// Queue -> distance -> hull may reuse addresses only after the previous
// owner's final read. Contents are initialized by the owning algorithm.
module ua_hand_scratch_ram #(parameter WORDS=14400)(
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

// Binary hand path: external native R is 10 bits; the later flood-fill queue
// needs 15-bit coordinates. Both lifetimes are exclusive. Two true RAM ports
// store/read a queue entry in adjacent 10-bit words IN THE SAME CYCLE, retaining
// the original one-cycle read contract and avoiding a 14400x16 allocation.
module ua_hand_binary_scratch_ram(
 input I_clk,I_external,I_read,I_write,
 input[13:0]I_address,input[15:0]I_data,output[15:0]O_data
);
/* fehdl force_ram=1, ram_style="bram" */ reg[9:0]memory[0:14399];
wire[13:0]address_a=I_external ? I_address : {I_address[12:0],1'b0};
wire[13:0]address_b={I_address[12:0],1'b1};
reg[9:0]qa,qb;reg read_external;
always @(posedge I_clk)begin
 if(I_read)begin qa<=memory[address_a];read_external<=I_external;end
 if(I_write)memory[address_a]<=I_data[9:0];
end
always @(posedge I_clk)begin
 if(!I_external && I_read)qb<=memory[address_b];
 if(!I_external && I_write)memory[address_b]<={5'd0,I_data[14:10]};
end
assign O_data=read_external ? {6'd0,qa} : {1'b0,qb[4:0],qa};
`ifndef SYNTHESIS
always @(posedge I_clk)if(I_read || I_write)begin
 if((I_external && I_address>=14400) || (!I_external && I_address>=2500))$fatal(1,"Packed hand scratch address out of bounds");
 if(I_read && I_write)$fatal(1,"Packed scratch read/write collision");
 if(I_write && (I_external ? |I_data[15:10] : I_data[15]))$fatal(1,"Packed hand scratch data out of range");
end
`endif
endmodule
