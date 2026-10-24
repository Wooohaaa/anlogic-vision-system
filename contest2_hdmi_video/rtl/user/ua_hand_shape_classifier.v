`timescale 1ns/1ps
// Complete selected-component classifier. Source is the immutable frontend
// seed/grown bank; the caller supplies CCL bbox + true raster anchor.
// This core does NOT choose between components, compute RGB confidence,
// perform seed/grown fallback, temporal voting, OSD or cross clock domains.
// IDs match hand_fixed_classifier.py: 0 none/ambiguous,1 fist,2 point,3 open.
// No first-frame reference. Shared 14400x16 scratch includes candidate list;
// width probes read the retained selected bitmap (14 total geometry ERAM).
module ua_hand_shape_classifier #(parameter MAX_CYCLES=16000000,PARALLEL_COMPARE=0,EXTERNAL_SCRATCH=0)(
 input I_clk,I_rst_n,I_clear,I_start,I_mode,
 input[7:0]I_xmin,I_width,I_anchor_x,input[6:0]I_ymin,I_height,I_anchor_y,
 output O_start_ready,O_read,output[11:0]O_read_addr,input I_read_valid,input[17:0]I_read_data,
 output reg O_busy,O_done,O_fault,output reg[1:0]O_raw,output reg[2:0]O_tip_count,
 output[7:0]O_center_x,output[6:0]O_center_y,output[10:0]O_radius_q4,output[13:0]O_area,
 output reg[31:0]O_cycles,
 // Idle-only reuse of the existing 14400x16 geometry RAM. Read/write are
 // mutually exclusive; transfer at request && ready. Read-valid is one cycle
 // after acceptance and is cancelled by clear. Contents are NOT preserved
 // across classification. No extra storage and no asynchronous video access.
 input I_scratch_read,I_scratch_write,input[13:0]I_scratch_address,input[15:0]I_scratch_data,
 output O_scratch_ready,output O_scratch_valid,output[15:0]O_scratch_data
);
localparam IDLE=0,LAUNCH=1,GEOMETRY=2,CANDIDATES_START=3,GEOMETRY_WAIT=4,
 FILTER_START=5,FILTER_WAIT=6,FINISH=7,FAIL=8;
reg[3:0]state;reg[7:0]width,xmin,anchor_x;reg[6:0]height,ymin,anchor_y;reg mode;
reg candidates_finished,geometry_finished,probe_pending,drain_probe;
wire abort=I_clear || state==FAIL;
wire geometry_ready,geometry_done,geometry_fault,has_palm;
wire hull_valid,hull_ready,hull_last;wire[7:0]hx;wire[6:0]hy;
wire edge_valid,edge_ready,qualified;wire[7:0]ax,bx;wire[6:0]ay,by;
wire signed[9:0]wx,wy;
wire client_read,client_write,client_ready;wire[13:0]client_address;wire[15:0]client_data,client_q;
wire memory_ready;reg scratch_pending;
wire scratch_request=EXTERNAL_SCRATCH ? (I_scratch_read || I_scratch_write) : 1'b0;
wire scratch_idle=EXTERNAL_SCRATCH && state==IDLE && !abort && I_rst_n;
assign O_scratch_ready=scratch_idle && !scratch_pending && memory_ready && I_scratch_address<14400 &&
 !(I_scratch_read && I_scratch_write);
wire scratch_access=O_scratch_ready && scratch_request;
assign O_scratch_valid=scratch_idle && scratch_pending;
assign O_scratch_data=client_q;
assign client_ready=memory_ready && !scratch_idle;
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)scratch_pending<=0;
 else if(abort)scratch_pending<=0;
 else scratch_pending<=scratch_access && I_scratch_read;
end
wire candidate_valid,candidate_ready,candidate_last,candidate_done,candidate_fault;
wire[7:0]candidate_x;wire[6:0]candidate_y;wire[2:0]candidate_count;
wire filter_ready,filter_done,filter_fault;wire[1:0]filter_raw;wire[2:0]filter_count;
wire probe,probe_ready,probe_valid,probe_pixel;wire[7:0]px;wire[6:0]py;
assign O_start_ready=state==IDLE && geometry_ready && filter_ready && !abort && I_rst_n && !scratch_request && !scratch_pending;
ua_hand_defect_geometry geometry(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(abort),.I_start(state==LAUNCH),.I_mode(mode),
 .I_xmin(xmin),.I_width(width),.I_anchor_x(anchor_x),.I_ymin(ymin),.I_height(height),.I_anchor_y(anchor_y),
 .O_start_ready(geometry_ready),.O_read(O_read),.O_read_addr(O_read_addr),.I_read_valid(I_read_valid),.I_read_data(I_read_data),
 .O_busy(),.O_done(geometry_done),.O_fault(geometry_fault),.O_has_palm(has_palm),
 .O_center_x(O_center_x),.O_center_y(O_center_y),.O_radius_q4(O_radius_q4),.O_area(O_area),
 .O_wrist_dx2(wx),.O_wrist_dy2(wy),.O_edge_valid(edge_valid),.I_edge_ready(edge_ready),
 .O_ax(ax),.O_bx(bx),.O_ay(ay),.O_by(by),.O_qualified(qualified),.O_has_far(),
 .O_far_x(),.O_far_y(),.O_max_cross(),.O_edge_length(),.O_cycles(),
 .I_probe(probe),.I_probe_x(px),.I_probe_y(py),.O_probe_ready(probe_ready),.O_probe_valid(probe_valid),.O_probe_pixel(probe_pixel),
 .O_hull_valid(hull_valid),.I_hull_ready(hull_ready),.O_hull_x(hx),.O_hull_y(hy),.O_hull_last(hull_last),
 .I_client_read(scratch_idle ? (scratch_access && I_scratch_read) : client_read),
 .I_client_write(scratch_idle ? (scratch_access && I_scratch_write) : client_write),
 .I_client_address(scratch_idle ? I_scratch_address : client_address),
 .I_client_data(scratch_idle ? I_scratch_data : client_data),
 .O_client_ready(memory_ready),.O_client_data(client_q));
ua_hand_tip_candidates #(.EXTERNAL_MEMORY(1)) candidates(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(abort),.I_start(state==CANDIDATES_START),
 .I_center_x(O_center_x),.I_center_y(O_center_y),.I_radius_q4(O_radius_q4),.I_wrist_dx2(wx),.I_wrist_dy2(wy),
 .I_hull_valid(hull_valid),.I_hull_last(hull_last && hull_valid),.I_hull_x(hx),.I_hull_y(hy),.O_hull_ready(hull_ready),
 .I_edge_valid(edge_valid),.I_edge_qualified(qualified),.I_edges_end(geometry_finished && !geometry_fault),
 .I_ax(ax),.I_bx(bx),.I_ay(ay),.I_by(by),.O_edge_ready(edge_ready),
 .O_tip_valid(candidate_valid),.I_tip_ready(candidate_ready),.O_tip_x(candidate_x),.O_tip_y(candidate_y),.O_tip_last(candidate_last),
 .O_tip_count(candidate_count),.O_busy(),.O_done(candidate_done),.O_fault(candidate_fault),
 .O_memory_read(client_read),.O_memory_write(client_write),.O_memory_address(client_address),.O_memory_data(client_data),
 .I_memory_ready(client_ready),.I_memory_data(client_q));
// An accepted synchronous bitmap request may be cancelled by clear. Supply
// one drain-valid to the width core in that case, never reused as new pixels.
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin probe_pending<=0;drain_probe<=0;end
 else begin
  drain_probe<=abort && probe_pending && !probe_valid;
  if(probe && probe_ready)probe_pending<=1;
  else if(probe_valid || drain_probe)probe_pending<=0;
 end
end
ua_hand_tip_filter #(.PARALLEL_COMPARE(PARALLEL_COMPARE)) filter(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(abort),.I_start(state==FILTER_START),
 .I_width(width),.I_center_x(O_center_x),.I_height(height),.I_center_y(O_center_y),.I_radius_q4(O_radius_q4),
 .I_wrist_dx2(wx),.I_wrist_dy2(wy),.I_tip_valid(candidate_valid),
 .I_tip_end((candidate_valid && candidate_last) || (candidates_finished && candidate_count==0)),
 .I_tip_x(candidate_x),.I_tip_y(candidate_y),.O_start_ready(filter_ready),.O_tip_ready(candidate_ready),
 .O_probe(probe),.O_probe_x(px),.O_probe_y(py),.I_probe_ready(probe_ready),
 .I_probe_valid(probe_valid || drain_probe),.I_probe_pixel(probe_pixel),
 .O_busy(),.O_done(filter_done),.O_fault(filter_fault),.O_raw(filter_raw),.O_tip_count(filter_count));
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
  state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_raw<=0;O_tip_count<=0;O_cycles<=0;
  width<=0;height<=0;xmin<=0;ymin<=0;anchor_x<=0;anchor_y<=0;mode<=0;candidates_finished<=0;geometry_finished<=0;
 end else if(I_clear)begin state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_raw<=0;O_tip_count<=0;O_cycles<=0;end
 else begin
  O_done<=0;
  if(O_busy)O_cycles<=O_cycles+32'd1;
  if(candidate_done)candidates_finished<=1;
  if(geometry_done)geometry_finished<=1;
  if(O_busy && state!=FAIL && state!=FINISH && O_cycles>=MAX_CYCLES)state<=FAIL;
  else if(O_busy && state!=FAIL && ((geometry_done && geometry_fault) ||
          (candidate_done && candidate_fault) || (filter_done && filter_fault)))state<=FAIL;
  else case(state)
  IDLE:if(I_start && O_start_ready)begin
   O_busy<=1;O_fault<=0;O_raw<=0;O_tip_count<=0;O_cycles<=0;candidates_finished<=0;geometry_finished<=0;
   width<=I_width;height<=I_height;xmin<=I_xmin;ymin<=I_ymin;anchor_x<=I_anchor_x;anchor_y<=I_anchor_y;mode<=I_mode;state<=LAUNCH;
  end
  LAUNCH:state<=GEOMETRY;
  GEOMETRY:if(hull_valid)state<=CANDIDATES_START;
  CANDIDATES_START:state<=GEOMETRY_WAIT;
  GEOMETRY_WAIT:if(geometry_done)state<=FILTER_START;
  FILTER_START:if(filter_ready)state<=FILTER_WAIT;
  FILTER_WAIT:if(filter_done)begin
   O_raw<=has_palm ? filter_raw : 2'd0;O_tip_count<=has_palm ? filter_count : 3'd0;state<=FINISH;
  end
  FINISH:begin O_done<=1;O_busy<=0;state<=IDLE;end
  FAIL:begin O_done<=1;O_busy<=0;O_fault<=1;O_raw<=0;O_tip_count<=0;state<=IDLE;end
  default:state<=FAIL;
  endcase
 end
end
endmodule
