`include "../../../rtl/user/ua_hand_component_mask.v"
module hand_component_micro(
 input clk,rst,clear,start,mode,
 input[44:0]roi,input rv,input[17:0]rd,
 input probe,input[7:0]px,input[6:0]py,
 output read,output[11:0]ra,output[2:0]pixel,output[3:0]status,
 output[13:0]area,output[31:0]cycles,output[2:0]probe_out,
 input pixel_ready
);
 ua_hand_component_mask core(
 .I_clk(clk),.I_rst_n(rst),.I_clear(clear),.I_start(start),.I_mode(mode),
 .I_xmin(roi[44:37]),.I_width(roi[36:29]),.I_anchor_x(roi[28:21]),
 .I_ymin(roi[20:14]),.I_height(roi[13:7]),.I_anchor_y(roi[6:0]),
 .O_read(read),.O_read_addr(ra),.I_read_valid(rv),.I_read_data(rd),
 .O_pixel_valid(pixel[2]),.O_pixel(pixel[1]),.O_pixel_last(pixel[0]),.I_pixel_ready(pixel_ready),
 .O_busy(status[3]),.O_done(status[2]),.O_fault(status[1]),.O_overflow(status[0]),.O_area(area),.O_cycles(cycles),
 .O_scratch_read(),.O_scratch_write(),.O_scratch_address(),.O_scratch_data(),.I_scratch_data(16'd0),
 .I_probe(probe),.I_probe_x(px),.I_probe_y(py),.O_probe_ready(probe_out[2]),.O_probe_valid(probe_out[1]),.O_probe_pixel(probe_out[0]));
endmodule
