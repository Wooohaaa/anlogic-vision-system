`include "rtl/user/ua_track_detect.v"
module blob_resource_new(input clk,rst,valid,sof,eof,input [2:0]hit,input[9:0]x,y,
 input[11:0]pu,pv,input[13:0]pp,pq,output done,output[36:0]result);
 wire[332:0]all_result;
 ua_blob_bank3 #(.USE_ERAM(1)) core(clk,rst,valid,sof,eof,hit,x,y,pu,pv,pp,pq,done,all_result);
 assign result=all_result[36:0]^all_result[73:37]^all_result[110:74]^all_result[147:111]^
  all_result[184:148]^all_result[221:185]^all_result[258:222]^all_result[295:259]^all_result[332:296];
endmodule
module blob_resource_old(input clk,rst,valid,sof,eof,input [2:0]hit,input[9:0]x,y,
 input[11:0]pu,pv,input[13:0]pp,pq,output done,output[36:0]result);
 wire[332:0]all_result;
 ua_blob_bank3_legacy core(clk,rst,valid,sof,eof,hit,x,y,pu,pv,pp,pq,done,all_result);
 assign result=all_result[36:0]^all_result[73:37]^all_result[110:74]^all_result[147:111]^
  all_result[184:148]^all_result[221:185]^all_result[258:222]^all_result[295:259]^all_result[332:296];
endmodule
