`include "../../../rtl/user/ua_hand_scratch_ram.v"
`include "../../../rtl/user/ua_hand_product_serial.v"
`include "../../../rtl/user/ua_hand_integer_math.v"
`include "../../../rtl/user/ua_hand_component_mask.v"
`include "../../../rtl/user/ua_hand_temporal_vote.v"
`include "../../../rtl/user/ua_hand_mask_frame.v"
`include "../../../rtl/user/ua_hand_blob_scan.v"
`include "../../../rtl/user/ua_hand_binary_shape.v"
`include "../../../rtl/user/ua_hand_binary_native.v"
module hand_binary_native_micro(
 input clk,rst,clear,valid,frame_done,input[9:0]x,y,input[95:0]rgb,
 output[7:0]status,output[23:0]checksum
);
wire[2:0]tips;wire[7:0]bx,bw;wire[6:0]by,bh;wire[31:0]cycles;
ua_hand_binary_native core(clk,rst,clear,valid,frame_done,x,y,rgb,
 status[7],status[6:5],status[4:3],tips,status[2],bx,bw,by,bh,status[1],status[0],cycles);
assign checksum=cycles[23:0]^{cycles[31:24],bx,bw}^{10'd0,by,bh}^{21'd0,tips};
endmodule
