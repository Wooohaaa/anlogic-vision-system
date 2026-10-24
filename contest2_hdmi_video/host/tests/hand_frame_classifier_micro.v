`include "../../../host/tests/hand_shape_classifier_micro.v"
`include "../../../rtl/user/ua_hand_frame_policy.v"
`include "../../../rtl/user/ua_hand_temporal_vote.v"
`include "../../../rtl/user/ua_hand_frame_classifier.v"
// All 123 input bits preserved, result observability folded to fit 160 IOs.
module hand_frame_classifier_micro(
 input clk,rst,clear,start,cv,finish,mode,input[44:0]roi,
 input[13:0]area,bright,input[23:0]redsum,input rv,input[17:0]rd,
 output[7:0]status,output[11:0]ra,output[15:0]checksum
);
wire[1:0]id,raw;wire[2:0]tips;wire[7:0]x,w;wire[6:0]y,h;wire[10:0]radius;wire[9:0]mean;
wire[63:0]payload;
ua_hand_frame_classifier core(clk,rst,clear,start,cv,finish,mode,
 roi[44:37],roi[36:29],roi[28:21],roi[20:14],roi[13:7],roi[6:0],area,redsum,bright,
 status[7],status[6],status[0],ra,rv,rd,status[5],status[4],status[3],id,raw,status[2],tips,x,w,y,h,radius,mean,status[1],
 1'b0,1'b0,14'd0,16'd0,,,);
assign payload={id,raw,tips,x,w,y,h,radius,mean,6'd0};
assign checksum=payload[15:0]^payload[31:16]^payload[47:32]^payload[63:48];
endmodule
