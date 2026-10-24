`include "../../../rtl/user/ua_hand_integer_math.v"
`include "../../../rtl/user/ua_hand_product_serial.v"
`include "../../../rtl/user/ua_hand_frame_policy.v"
module hand_frame_policy_micro(
 input clk,rst,clear,start,cv,finish,input[98:0]candidate,input[13:0]bright,
 output[6:0]status,output[23:0]checksum
);
wire[1:0]raw;wire[2:0]tips;wire[7:0]x,w,cx;wire[6:0]y,h,cy;
wire[13:0]area;wire[10:0]radius;wire[9:0]mean;wire[26:0]score;
wire[31:0]fold;
ua_hand_frame_policy core(clk,rst,clear,start,cv,finish,
 candidate[98:91],candidate[90:83],candidate[82:75],candidate[74:68],candidate[67:61],candidate[60:54],
 candidate[53:40],candidate[39:16],candidate[15:5],candidate[4:3],candidate[2:0],bright,
 status[6],status[5],status[4],status[3],status[2],status[1],status[0],raw,tips,x,w,cx,y,h,cy,area,radius,mean,score);
assign fold={x,w,cx,raw,tips,3'd0}^{y,h,cy,radius}^{area,mean,8'd0}^{score,5'd0};
assign checksum=fold[23:0]^{16'd0,fold[31:24]};
endmodule
