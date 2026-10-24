// Run the measurement from tmp/v41; production source, not a copied ROM.
`include "../../rtl/user/osd_char_lib.v"
module font_micro(input clk,input [7:0] code,input [3:0] row,output [15:0] data);
 osd_char_lib #(.SYNC_READ(1)) font(clk,code,row,data);
endmodule
