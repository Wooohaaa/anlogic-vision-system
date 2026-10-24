// Exact-depth motion reference memory. Same-clock synchronous old-data read
// and independent write enable. Contents are intentionally not reset: the
// caller completes background capture before consuming reference samples.
module ua_motion_ref_ram #(
    parameter DEPTH=57600, ADDR_W=16
)(
    input I_clk,I_write,I_read,
    input [ADDR_W-1:0] I_write_addr,I_read_addr,
    input [7:0] I_data,
    output reg [7:0] O_data
);
/* fehdl force_ram=1, ram_style="bram" */ reg [7:0] memory[0:DEPTH-1];
always @(posedge I_clk)begin
    if(I_read)O_data<=memory[I_read_addr];
    if(I_write)memory[I_write_addr]<=I_data;
end
endmodule
