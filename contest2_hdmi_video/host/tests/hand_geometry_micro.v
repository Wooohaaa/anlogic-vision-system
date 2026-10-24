`include "../../../rtl/user/ua_hand_scratch_ram.v"
`include "../../../rtl/user/ua_hand_component_mask.v"
`include "../../../rtl/user/ua_hand_palm_distance.v"
`include "../../../rtl/user/ua_hand_wrist_median.v"
`include "../../../rtl/user/ua_hand_convex_hull.v"
`include "../../../rtl/user/ua_hand_geometry_shared.v"
// Fold only observability to stay within the device's 160 IOs. Every core
// output participates in checksum or status; no image/coordinate input folds.
module hand_geometry_micro #(parameter SHARED=1)(
 input clk,rst,clear,start,mode,
 input[44:0]roi,input rv,input[17:0]rd,input vertex_ready,
 output read,output[11:0]ra,output[4:0]status,output[31:0]checksum
);
 wire has,vl;wire[7:0]cx,vx;wire[6:0]cy,vy;wire[10:0]radius;
 wire[13:0]area,lower;wire signed[9:0]dx,dy;wire[8:0]vc;wire[31:0]cycles;
 ua_hand_geometry_shared #(.SHARED_MEMORY(SHARED)) core(
 .I_clk(clk),.I_rst_n(rst),.I_clear(clear),.I_start(start),.I_mode(mode),
 .I_xmin(roi[44:37]),.I_width(roi[36:29]),.I_anchor_x(roi[28:21]),
 .I_ymin(roi[20:14]),.I_height(roi[13:7]),.I_anchor_y(roi[6:0]),
 .O_start_ready(status[4]),.O_read(read),.O_read_addr(ra),.I_read_valid(rv),.I_read_data(rd),
 .O_busy(status[3]),.O_done(status[2]),.O_fault(status[1]),.O_has_palm(has),
 .O_center_x(cx),.O_center_y(cy),.O_radius_q4(radius),.O_area(area),.O_lower_count(lower),
 .O_wrist_dx2(dx),.O_wrist_dy2(dy),.O_vertex_valid(status[0]),.I_vertex_ready(vertex_ready),
 .O_vertex_x(vx),.O_vertex_y(vy),.O_vertex_last(vl),.O_vertex_count(vc),.O_cycles(cycles),
 .I_extra_read(1'b0),.I_extra_write(1'b0),.I_extra_address(14'd0),.I_extra_data(16'd0),
 .O_extra_ready(),.O_extra_data(),.I_extra_probe(1'b0),.I_extra_probe_x(8'd0),.I_extra_probe_y(7'd0),
 .O_extra_probe_ready(),.O_extra_probe_valid(),.O_extra_probe_pixel());
 assign checksum=cycles ^ {cx,cy,radius,has,5'd0} ^ {area,lower,4'd0} ^ {dx,dy,12'd0} ^ {vx,vy,vc,vl,7'd0};
endmodule
module hand_geometry_private_micro(
 input clk,rst,clear,start,mode,
 input[44:0]roi,input rv,input[17:0]rd,input vertex_ready,
 output read,output[11:0]ra,output[4:0]status,output[31:0]checksum
);
 hand_geometry_micro #(.SHARED(0)) core(clk,rst,clear,start,mode,roi,rv,rd,vertex_ready,read,ra,status,checksum);
endmodule
