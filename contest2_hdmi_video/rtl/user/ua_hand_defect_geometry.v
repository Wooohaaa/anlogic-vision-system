`timescale 1ns/1ps
// Immutable seed/grown mask -> selected component -> palm/wrist/hull ->
// ordered convexity defects. All stages share geometry's 13-ERAM scratch;
// the selected bitmap uses one further ERAM. This is not a final classifier.
// Keep the source bank immutable until done. One source read outstanding;
// clear drains any external response before start_ready may rise again.
module ua_hand_defect_geometry #(parameter MAX_CYCLES=12000000)(
 input I_clk,I_rst_n,I_clear,I_start,I_mode,
 input[7:0]I_xmin,I_width,I_anchor_x,input[6:0]I_ymin,I_height,I_anchor_y,
 output O_start_ready,O_read,output[11:0]O_read_addr,input I_read_valid,input[17:0]I_read_data,
 output reg O_busy,O_done,O_fault,
 output O_has_palm,output[7:0]O_center_x,output[6:0]O_center_y,output[10:0]O_radius_q4,
 output[13:0]O_area,output signed[9:0]O_wrist_dx2,O_wrist_dy2,
 output O_edge_valid,input I_edge_ready,
 output[7:0]O_ax,O_bx,output[6:0]O_ay,O_by,
 output O_qualified,O_has_far,output[7:0]O_far_x,output[6:0]O_far_y,
 output[19:0]O_max_cross,output[9:0]O_edge_length,
 output reg[31:0]O_cycles,
 input I_probe,input[7:0]I_probe_x,input[6:0]I_probe_y,
 output O_probe_ready,O_probe_valid,O_probe_pixel,
 output O_hull_valid,input I_hull_ready,output[7:0]O_hull_x,output[6:0]O_hull_y,output O_hull_last,
 input I_client_read,I_client_write,input[13:0]I_client_address,input[15:0]I_client_data,
 output O_client_ready,output[15:0]O_client_data
);
localparam IDLE=0,LAUNCH=1,GEOMETRY=2,TRACE_START=3,TRACE=4,DEFECTS=5,FINISH=6,FAIL=7;
reg[2:0]state;
reg source_pending,mode;reg[7:0]xmin,width,anchor_x;reg[6:0]ymin,height,anchor_y;
wire abort=I_clear || state==FAIL;
wire geometry_ready,geometry_read,geometry_done,geometry_fault;
wire[11:0]geometry_address;
wire hull_valid,hull_last,hull_ready,scan_hull_ready;wire[7:0]hull_x;wire[6:0]hull_y;
wire memory_read,memory_write,memory_ready;wire[13:0]memory_address;wire[15:0]memory_data,memory_q;
wire contour_read,contour_valid,contour_done,contour_fault;wire[11:0]contour_address;
wire[7:0]contour_x;wire[6:0]contour_y;
wire scan_ready,scan_done,scan_fault,scan_edge_valid;
wire idle_probe=state==IDLE && !I_start && !abort;
wire geometry_probe_ready,geometry_probe_valid;
assign O_start_ready=state==IDLE && geometry_ready && !source_pending && I_rst_n && !I_clear;
assign O_read=I_rst_n && !abort && (state==TRACE ? contour_read : state==GEOMETRY ? geometry_read : 1'b0);
assign O_read_addr=state==TRACE ? contour_address : geometry_address;
assign O_edge_valid=scan_edge_valid && state==DEFECTS;
assign O_probe_ready=idle_probe && geometry_probe_ready;
assign O_probe_valid=idle_probe && geometry_probe_valid;
assign O_hull_valid=hull_valid && scan_hull_ready;
assign O_hull_x=hull_x;assign O_hull_y=hull_y;assign O_hull_last=hull_last;
assign hull_ready=scan_hull_ready && I_hull_ready;
wire scan_memory_access=memory_read || memory_write;
assign O_client_ready=memory_ready && !scan_memory_access && !abort && I_rst_n;
assign O_client_data=memory_q;
ua_hand_geometry_shared geometry(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(abort),.I_start(state==LAUNCH),.I_mode(mode),
 .I_xmin(xmin),.I_width(width),.I_anchor_x(anchor_x),.I_ymin(ymin),.I_height(height),.I_anchor_y(anchor_y),
 .O_start_ready(geometry_ready),.O_read(geometry_read),.O_read_addr(geometry_address),
 // Forward drain responses even after clear returns this wrapper to IDLE.
 // Geometry itself qualifies them with its outstanding-request flag.
 .I_read_valid(I_read_valid),.I_read_data(I_read_data),
 .O_busy(),.O_done(geometry_done),.O_fault(geometry_fault),.O_has_palm(O_has_palm),
 .O_center_x(O_center_x),.O_center_y(O_center_y),.O_radius_q4(O_radius_q4),.O_area(O_area),.O_lower_count(),
 .O_wrist_dx2(O_wrist_dx2),.O_wrist_dy2(O_wrist_dy2),
 .O_vertex_valid(hull_valid),.I_vertex_ready(hull_ready),.O_vertex_x(hull_x),.O_vertex_y(hull_y),
 .O_vertex_last(hull_last),.O_vertex_count(),.O_cycles(),
 .I_extra_read(memory_read || (O_client_ready && I_client_read)),
 .I_extra_write(memory_write || (O_client_ready && I_client_write)),
 .I_extra_address(scan_memory_access ? memory_address : I_client_address),
 .I_extra_data(scan_memory_access ? memory_data : I_client_data),
 .O_extra_ready(memory_ready),.O_extra_data(memory_q),
 .I_extra_probe(idle_probe && I_probe),.I_extra_probe_x(I_probe_x),.I_extra_probe_y(I_probe_y),
 .O_extra_probe_ready(geometry_probe_ready),.O_extra_probe_valid(geometry_probe_valid),.O_extra_probe_pixel(O_probe_pixel));
ua_hand_contour_trace #(.OPENCV_ORDER(1)) contour(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(abort),.I_start(state==TRACE_START),.I_mode(mode),
 .I_anchor_x(anchor_x),.I_anchor_y(anchor_y),.O_read(contour_read),.O_read_addr(contour_address),
 .I_read_valid(I_read_valid && source_pending && state==TRACE),.I_read_data(I_read_data),
 .O_busy(),.O_done(contour_done),.O_fault(contour_fault),.O_vertex_valid(contour_valid),
 .O_x(contour_x),.O_y(contour_y),.O_count());
ua_hand_defect_scan #(.EXTERNAL_MEMORY(1)) scan(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(abort),.I_start(state==LAUNCH),.I_radius_q4(O_radius_q4),
 .I_hull_valid(hull_valid && I_hull_ready),.I_hull_last(hull_last && hull_valid && I_hull_ready),
 .I_hull_x(hull_x),.I_hull_y(hull_y),.O_hull_ready(scan_hull_ready),
 .I_contour_valid(contour_valid && state==TRACE),.I_contour_last(contour_done && !contour_fault && state==TRACE),
 .I_contour_x(contour_x-xmin),.I_contour_y(contour_y-ymin),.O_contour_ready(scan_ready),
 .O_edge_valid(scan_edge_valid),.I_edge_ready(I_edge_ready && state==DEFECTS),
 .O_ax(O_ax),.O_bx(O_bx),.O_ay(O_ay),.O_by(O_by),.O_qualified(O_qualified),.O_has_far(O_has_far),
 .O_far_x(O_far_x),.O_far_y(O_far_y),.O_max_cross(O_max_cross),.O_edge_length(O_edge_length),
 .O_busy(),.O_done(scan_done),.O_fault(scan_fault),.O_hull_count(),.O_contour_count(),.O_cycles(),
 .O_memory_read(memory_read),.O_memory_write(memory_write),.O_memory_address(memory_address),
 .O_memory_data(memory_data),.I_memory_ready(memory_ready),.I_memory_data(memory_q));
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)source_pending<=0;
 else if(O_read)source_pending<=1;
 else if(I_read_valid)source_pending<=0;
end
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
  state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_cycles<=0;
  xmin<=0;ymin<=0;width<=0;height<=0;anchor_x<=0;anchor_y<=0;mode<=0;
 end else if(I_clear)begin state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_cycles<=0;end
 else begin
  O_done<=0;
  if(O_busy)O_cycles<=O_cycles+32'd1;
  if(O_busy && state!=FAIL && state!=FINISH && O_cycles>=MAX_CYCLES)state<=FAIL;
  else if(O_busy && state!=FAIL && ((scan_done && scan_fault) || (geometry_done && geometry_fault) ||
          (contour_done && contour_fault)))state<=FAIL;
  else case(state)
  IDLE:if(I_start && O_start_ready)begin
   xmin<=I_xmin;ymin<=I_ymin;width<=I_width;height<=I_height;anchor_x<=I_anchor_x;anchor_y<=I_anchor_y;mode<=I_mode;
   O_busy<=1;O_fault<=0;O_cycles<=0;state<=LAUNCH;
  end
  LAUNCH:state<=GEOMETRY;
  GEOMETRY:if(geometry_done)state<=TRACE_START;
  TRACE_START:state<=TRACE;
  TRACE:begin
   if(contour_valid && !scan_ready)state<=FAIL;
   else if(contour_done)state<=DEFECTS;
  end
  DEFECTS:if(scan_done)state<=FINISH;
  FINISH:begin O_done<=1;O_busy<=0;state<=IDLE;end
  FAIL:begin O_done<=1;O_busy<=0;O_fault<=1;state<=IDLE;end
  default:state<=FAIL;
  endcase
 end
end
endmodule
