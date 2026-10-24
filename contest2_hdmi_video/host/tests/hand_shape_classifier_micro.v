`include "../../../rtl/user/ua_hand_scratch_ram.v"
`include "../../../rtl/user/ua_hand_component_mask.v"
`include "../../../rtl/user/ua_hand_palm_distance.v"
`include "../../../rtl/user/ua_hand_wrist_median.v"
`include "../../../rtl/user/ua_hand_convex_hull.v"
`include "../../../rtl/user/ua_hand_geometry_shared.v"
`include "../../../rtl/user/ua_hand_integer_math.v"
`include "../../../rtl/user/ua_hand_product_serial.v"
`include "../../../rtl/user/ua_hand_defect_edge.v"
`include "../../../rtl/user/ua_hand_defect_scan.v"
`include "../../../rtl/user/ua_hand_contour_trace.v"
`include "../../../rtl/user/ua_hand_defect_geometry.v"
`include "../../../rtl/user/ua_hand_tip_candidates.v"
`include "../../../rtl/user/ua_hand_tip_width.v"
`include "../../../rtl/user/ua_hand_tip_filter.v"
`include "../../../rtl/user/ua_hand_shape_classifier.v"
module hand_shape_classifier_micro #(parameter PARALLEL_COMPARE=0,EXTERNAL_SCRATCH=0)(
 input clk,rst,clear,start,mode,input[44:0]roi,input rv,input[17:0]rd,
 output ready,read,output[11:0]ra,output[7:0]status,output[31:0]checksum
);
wire[7:0]cx;wire[6:0]cy;wire[10:0]radius;wire[13:0]area;wire[31:0]cycles;
wire sr,sv;wire[15:0]sq;
ua_hand_shape_classifier #(.PARALLEL_COMPARE(PARALLEL_COMPARE),.EXTERNAL_SCRATCH(EXTERNAL_SCRATCH)) core(
 clk,rst,clear,start,mode,roi[44:37],roi[36:29],roi[28:21],roi[20:14],roi[13:7],roi[6:0],
 ready,read,ra,rv,rd,status[7],status[6],status[5],status[4:3],status[2:0],cx,cy,radius,area,cycles,
 EXTERNAL_SCRATCH && roi[44],EXTERNAL_SCRATCH && roi[43],roi[42:29],roi[28:13],sr,sv,sq);
assign checksum=cycles ^ {cx,cy,radius,6'd0} ^ {area,18'd0} ^
 (EXTERNAL_SCRATCH ? {14'd0,sr,sv,sq} : 32'd0);
endmodule
module hand_shape_classifier_scratch_micro(
 input clk,rst,clear,start,mode,input[44:0]roi,input rv,input[17:0]rd,
 output ready,read,output[11:0]ra,output[7:0]status,output[31:0]checksum
);
hand_shape_classifier_micro #(.EXTERNAL_SCRATCH(1)) core(clk,rst,clear,start,mode,roi,rv,rd,ready,read,ra,status,checksum);
endmodule
module hand_shape_classifier_parallel_micro(
 input clk,rst,clear,start,mode,input[44:0]roi,input rv,input[17:0]rd,
 output ready,read,output[11:0]ra,output[7:0]status,output[31:0]checksum
);
hand_shape_classifier_micro #(.PARALLEL_COMPARE(1)) core(clk,rst,clear,start,mode,roi,rv,rd,ready,read,ra,status,checksum);
endmodule
