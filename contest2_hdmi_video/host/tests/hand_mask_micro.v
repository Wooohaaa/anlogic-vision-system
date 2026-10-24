`include "../../rtl/user/ua_hand_mask_frame.v"
// Fold observability only: retain every core output without exceeding device IOs.
module hand_mask_micro(
 input wire clk,rst,clear,valid,done,release_mask,read,
 input wire[9:0] x,y,input wire[95:0] rgb,input wire[11:0] addr,
 output wire[17:0] checksum
);
 wire mv,bank,rv,drop,fault;wire[15:0]fid;wire[17:0]data;wire[31:0]cycles;
 wire unused_nv,unused_nb,unused_bright;wire[13:0]unused_na;wire[9:0]unused_nr;
 ua_hand_mask_frame core(clk,rst,clear,valid,done,x,y,rgb,mv,bank,fid,release_mask,read,addr,rv,data,drop,fault,cycles,
  1'b1,unused_nv,unused_nb,unused_bright,unused_na,unused_nr);
 assign checksum=data^{2'b0,fid}^cycles[17:0]^{4'b0,cycles[31:18]}^{13'b0,mv,bank,rv,drop,fault};
endmodule
