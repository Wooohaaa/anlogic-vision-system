`include "../../../rtl/user/ua_hand_associate.v"
module hand_associate_micro(
 input clk,rst,clear,start,dv,dm,mready,cready,
 input[6:0]root,input[95:0]descriptor,input[15:0]mq,
 output dready,ready,mr,cv,cm,busy,done,fault,
 output[13:0]ma,output[7:0]checksum
);
wire[95:0]data;wire[4:0]count;wire[31:0]cycles;
ua_hand_associate core(clk,rst,clear,start,dv,dm,root,descriptor,dready,ready,
 mr,ma,mready,mq,cv,cready,cm,data,busy,done,fault,count,cycles,
 1'b0,1'b0,7'd0,,,);
assign checksum=data[7:0]^data[15:8]^data[23:16]^data[31:24]^data[39:32]^data[47:40]^
 data[55:48]^data[63:56]^data[71:64]^data[79:72]^data[87:80]^data[95:88]^
 cycles[7:0]^cycles[15:8]^cycles[23:16]^cycles[31:24]^{3'd0,count};
endmodule
