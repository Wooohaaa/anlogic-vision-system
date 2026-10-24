`include "../../../rtl/user/ua_hand_scratch_ram.v"
`include "../../../rtl/user/ua_hand_component_mask.v"
`include "../../../rtl/user/ua_hand_palm_distance.v"
`include "../../../rtl/user/ua_hand_wrist_median.v"
`include "../../../rtl/user/ua_hand_convex_hull.v"
`include "../../../rtl/user/ua_hand_geometry_shared.v"
`include "../../../rtl/user/ua_hand_integer_math.v"
`include "../../../rtl/user/ua_hand_defect_edge.v"
`include "../../../rtl/user/ua_hand_defect_scan.v"
`include "../../../rtl/user/ua_hand_contour_trace.v"
`include "../../../rtl/user/ua_hand_defect_geometry.v"
module hand_defect_geometry_micro(
 input clk,rst,clear,start,mode,input[44:0]roi,input rv,input[17:0]rd,input edge_ready,
 input probe,input[7:0]px,input[6:0]py,
 output read,output[11:0]ra,output[7:0]status,output[31:0]checksum
);
wire has,qual,far_valid;wire[7:0]cx,ax,bx,fx;wire[6:0]cy,ay,by,fy;
wire[10:0]radius;wire[13:0]area;wire signed[9:0]wx,wy;wire[19:0]cross_value;wire[9:0]length;wire[31:0]cycles;
wire unused_hv,unused_hl,unused_client_ready;wire[7:0]unused_hx;wire[6:0]unused_hy;wire[15:0]unused_client_data;
ua_hand_defect_geometry core(
 clk,rst,clear,start,mode,roi[44:37],roi[36:29],roi[28:21],roi[20:14],roi[13:7],roi[6:0],
 status[7],read,ra,rv,rd,status[6],status[5],status[4],has,cx,cy,radius,area,wx,wy,
 status[3],edge_ready,ax,bx,ay,by,qual,far_valid,fx,fy,cross_value,length,cycles,
 probe,px,py,status[2],status[1],status[0],unused_hv,1'b1,unused_hx,unused_hy,unused_hl,
 1'b0,1'b0,14'd0,16'd0,unused_client_ready,unused_client_data);
assign checksum=cycles ^ {cx,cy,radius,has,5'd0} ^ {area,wx,8'd0} ^ {wy,cross_value,qual,far_valid} ^
 {ax,bx,ay,by,2'd0} ^ {fx,fy,length,7'd0};
endmodule
