`include "../../../rtl/user/ua_hand_label_map.v"
module hand_label_map_micro(
 input clk,rst,clear,start,mode,rv,input[17:0]rd,
 input memory_ready,input[15:0]memory_q,
 output ready,read,output[11:0]ra,output mr,mw,
 output[13:0]ma,output[15:0]md,output busy,done,fault,
 output[7:0]labels,output[31:0]cycles
);
ua_hand_label_map core(clk,rst,clear,start,mode,ready,read,ra,rv,rd,
 mr,mw,ma,md,memory_ready,memory_q,busy,done,fault,labels,cycles);
endmodule
