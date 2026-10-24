`timescale 1ns/1ps
// Selected component -> palm -> wrist/hull, using one shared scratch RAM.
// This is geometry only, NOT the final gesture classifier. The original mask
// bank must remain immutable until done or clear. All logic uses I_clk.
// Source has one outstanding, variable-latency request. After clear, start is
// blocked until an outstanding source response drains (no stale response may
// be consumed by the next transaction). Vertex output may be stalled.
module ua_hand_geometry_shared #(parameter MAX_CYCLES=4000000, SHARED_MEMORY=1)(
 input I_clk,I_rst_n,I_clear,I_start,I_mode,
 input[7:0]I_xmin,I_width,I_anchor_x,
 input[6:0]I_ymin,I_height,I_anchor_y,
 output O_start_ready,O_read,output[11:0]O_read_addr,
 input I_read_valid,input[17:0]I_read_data,
 output reg O_busy,O_done,O_fault,
 output O_has_palm,output[7:0]O_center_x,output[6:0]O_center_y,
 output[10:0]O_radius_q4,output[13:0]O_area,O_lower_count,
 output signed[9:0]O_wrist_dx2,O_wrist_dy2,
 output O_vertex_valid,input I_vertex_ready,
 output[7:0]O_vertex_x,output[6:0]O_vertex_y,
 output O_vertex_last,output[8:0]O_vertex_count,
 output reg[31:0]O_cycles,
 // Shared scratch client: may store streamed hull vertices while the hull
 // core presents (not reads), then owns RAM after geometry completes.
 input I_extra_read,I_extra_write,input[13:0]I_extra_address,input[15:0]I_extra_data,
 output O_extra_ready,output[15:0]O_extra_data,
 // Retained selected-component bitmap, usable after geometry completes.
 input I_extra_probe,input[7:0]I_extra_probe_x,input[6:0]I_extra_probe_y,
 output O_extra_probe_ready,O_extra_probe_valid,O_extra_probe_pixel
);
localparam IDLE=0,LAUNCH=1,EXTRACT=2,PALM=3,GEOM_START=4,
           REPLAY_REQUEST=5,REPLAY_WAIT=6,REPLAY_PRESENT=7,
           WAIT_GEOMETRY=8,FINISH=9,FAIL=10;
reg[3:0]state;
reg mode,source_pending,wrist_finished,hull_finished,held_pixel;
reg[7:0]xmin,width,anchor_x,replay_x;
reg[6:0]ymin,height,anchor_y,replay_y;
wire abort=I_clear || state==FAIL;
wire launch=state==LAUNCH;
wire cc_busy,cc_done,cc_fault,cc_overflow,cc_valid,cc_pixel,cc_last;
wire cc_read;wire[11:0]cc_read_addr;
wire palm_ready,palm_busy,palm_done,palm_fault;
wire wrist_ready,wrist_busy,wrist_done,wrist_fault;
wire hull_ready,hull_busy,hull_done,hull_fault;
wire cr,cw,pr,pw,hr,hw;
wire[13:0]ca,pa,ha;
wire[15:0]cd,pd,hd,scratch_q;
wire probe_ready,probe_valid,probe_pixel;
wire component_phase=state==EXTRACT || state==PALM;
wire extra_probe_allowed=state==IDLE && !I_start && !I_clear && I_rst_n;
wire probe=(state==REPLAY_REQUEST && probe_ready) || (extra_probe_allowed && I_extra_probe);
assign O_extra_probe_ready=extra_probe_allowed && probe_ready;
assign O_extra_probe_valid=extra_probe_allowed && probe_valid;
assign O_extra_probe_pixel=probe_pixel;
wire replay_last=replay_x==width-1 && replay_y==height-1;
wire replay_valid=state==REPLAY_PRESENT;
wire[8:0]wrist_x2,wrist_y2;
assign O_read=cc_read && component_phase && !abort && I_rst_n;
assign O_read_addr=cc_read_addr;
assign O_start_ready=state==IDLE && !source_pending && I_rst_n && !I_clear;
ua_hand_component_mask #(.EXTERNAL_MEMORY(SHARED_MEMORY)) component_core(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(abort),.I_start(launch),.I_mode(mode),
 .I_xmin(xmin),.I_width(width),.I_anchor_x(anchor_x),.I_ymin(ymin),.I_height(height),.I_anchor_y(anchor_y),
 .O_read(cc_read),.O_read_addr(cc_read_addr),.I_read_valid(I_read_valid && source_pending),.I_read_data(I_read_data),
 .O_pixel_valid(cc_valid),.O_pixel(cc_pixel),.O_pixel_last(cc_last),.I_pixel_ready(palm_ready && component_phase),
 .O_busy(cc_busy),.O_done(cc_done),.O_fault(cc_fault),.O_overflow(cc_overflow),.O_area(O_area),.O_cycles(),
 .O_scratch_read(cr),.O_scratch_write(cw),.O_scratch_address(ca),.O_scratch_data(cd),.I_scratch_data(scratch_q),
 .I_probe(probe),.I_probe_x(extra_probe_allowed ? I_extra_probe_x : replay_x),
 .I_probe_y(extra_probe_allowed ? I_extra_probe_y : replay_y),
 .O_probe_ready(probe_ready),.O_probe_valid(probe_valid),.O_probe_pixel(probe_pixel));
ua_hand_palm_distance #(.EXTERNAL_MEMORY(SHARED_MEMORY)) palm_core(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(abort),.I_start(launch),.I_width(width),.I_height(height),
 .I_mask_valid(cc_valid && component_phase),.I_mask(cc_pixel),.I_mask_last(cc_last),.O_mask_ready(palm_ready),
 .O_busy(palm_busy),.O_done(palm_done),.O_fault(palm_fault),.O_has_palm(O_has_palm),
 .O_center_x(O_center_x),.O_center_y(O_center_y),.O_radius_q4(O_radius_q4),
 .O_distance_valid(),.O_distance_x(),.O_distance_y(),.O_distance_q4(),.O_cycles(),
 .O_scratch_read(pr),.O_scratch_write(pw),.O_scratch_address(pa),.O_scratch_data(pd),.I_scratch_data(scratch_q));
ua_hand_wrist_median wrist_core(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(abort),.I_start(state==GEOM_START),
 .I_width(width),.I_height(height),.I_center_x(O_center_x),.I_center_y(O_center_y),.I_radius_q4(O_radius_q4),
 .I_mask_valid(replay_valid && hull_ready),.I_mask(held_pixel),.I_mask_last(replay_last),.O_mask_ready(wrist_ready),
 .O_busy(wrist_busy),.O_done(wrist_done),.O_fault(wrist_fault),.O_lower_count(O_lower_count),
 .O_wrist_x2(wrist_x2),.O_wrist_y2(wrist_y2),.O_direction_x2(O_wrist_dx2),.O_direction_y2(O_wrist_dy2));
ua_hand_convex_hull #(.EXTERNAL_MEMORY(SHARED_MEMORY)) hull_core(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(abort),.I_start(state==GEOM_START),
 .I_width(width),.I_height(height),.I_mask_valid(replay_valid && wrist_ready),.I_mask(held_pixel),.I_mask_last(replay_last),.O_mask_ready(hull_ready),
 .O_busy(hull_busy),.O_done(hull_done),.O_fault(hull_fault),.O_vertex_valid(O_vertex_valid),.I_vertex_ready(I_vertex_ready),
 .O_vertex_x(O_vertex_x),.O_vertex_y(O_vertex_y),.O_vertex_last(O_vertex_last),.O_count(O_vertex_count),
 .O_scratch_read(hr),.O_scratch_write(hw),.O_scratch_address(ha),.O_scratch_data(hd),.I_scratch_data(scratch_q));
// Switch to distance ownership on the *first* component output transfer,
// not one clock later. No queue accesses remain once raster output begins.
wire owner_palm=state==PALM || (state==EXTRACT && cc_valid);
wire owner_queue=state==EXTRACT && !cc_valid;
wire owner_hull=state>=GEOM_START && state<=WAIT_GEOMETRY;
assign O_extra_ready=SHARED_MEMORY && I_rst_n && !abort &&
 ((state==IDLE && !I_start && !source_pending) || (state==WAIT_GEOMETRY && !hr && !hw));
assign O_extra_data=scratch_q;
wire scratch_read=!abort && ((O_extra_ready && I_extra_read) || (owner_queue ? cr : owner_palm ? pr : owner_hull ? hr : 1'b0));
wire scratch_write=!abort && ((O_extra_ready && I_extra_write) || (owner_queue ? cw : owner_palm ? pw : owner_hull ? hw : 1'b0));
wire extra_access=O_extra_ready && (I_extra_read || I_extra_write);
wire[13:0]scratch_address=extra_access ? I_extra_address : owner_queue ? ca : owner_palm ? pa : ha;
wire[15:0]scratch_data=extra_access ? I_extra_data : owner_queue ? cd : owner_palm ? pd : hd;
generate if(SHARED_MEMORY)begin:gen_shared_memory
 ua_hand_scratch_ram storage(I_clk,scratch_read,scratch_write,scratch_address,scratch_data,scratch_q);
end else begin:gen_private_memory
 assign scratch_q=16'd0;
end endgenerate
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)source_pending<=0;
 else begin
  if(O_read)source_pending<=1;
  else if(I_read_valid)source_pending<=0;
 end
end
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
  state<=IDLE;mode<=0;xmin<=0;ymin<=0;width<=0;height<=0;anchor_x<=0;anchor_y<=0;
  replay_x<=0;replay_y<=0;held_pixel<=0;wrist_finished<=0;hull_finished<=0;
  O_busy<=0;O_done<=0;O_fault<=0;O_cycles<=0;
 end else if(I_clear)begin
  state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_cycles<=0;
 end else begin
  O_done<=0;
  if(O_busy)O_cycles<=O_cycles+32'd1;
  if(O_busy && state!=FAIL && O_cycles>=MAX_CYCLES)state<=FAIL;
  else if(O_busy && state!=FAIL && ((cc_done && cc_fault) || (palm_done && palm_fault) ||
          (wrist_done && wrist_fault) || (hull_done && hull_fault)))state<=FAIL;
  else case(state)
   IDLE:if(I_start && O_start_ready)begin
    mode<=I_mode;xmin<=I_xmin;ymin<=I_ymin;width<=I_width;height<=I_height;
    anchor_x<=I_anchor_x;anchor_y<=I_anchor_y;O_busy<=1;O_fault<=0;O_cycles<=0;
    wrist_finished<=0;hull_finished<=0;state<=LAUNCH;
   end
   LAUNCH:state<=EXTRACT;
   EXTRACT:if(cc_valid)state<=PALM;
   PALM:if(palm_done)begin replay_x<=0;replay_y<=0;state<=GEOM_START;end
   GEOM_START:state<=REPLAY_REQUEST;
   REPLAY_REQUEST:if(probe_ready)state<=REPLAY_WAIT;
   REPLAY_WAIT:if(probe_valid)begin held_pixel<=probe_pixel;state<=REPLAY_PRESENT;end
   REPLAY_PRESENT:if(wrist_ready && hull_ready)begin
    if(replay_last)state<=WAIT_GEOMETRY;
    else begin
     if(replay_x==width-1)begin replay_x<=0;replay_y<=replay_y+7'd1;end else replay_x<=replay_x+8'd1;
     state<=REPLAY_REQUEST;
    end
   end
   WAIT_GEOMETRY:begin
    if(wrist_done)wrist_finished<=1;
    if(hull_done)hull_finished<=1;
    if((wrist_finished || wrist_done) && (hull_finished || hull_done))state<=FINISH;
   end
   FINISH:begin O_done<=1;O_busy<=0;state<=IDLE;end
   FAIL:begin O_fault<=1;O_done<=1;O_busy<=0;state<=IDLE;end
   default:state<=FAIL;
  endcase
 end
end
endmodule
