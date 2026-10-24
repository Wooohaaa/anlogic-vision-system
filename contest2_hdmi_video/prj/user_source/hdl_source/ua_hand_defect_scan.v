`timescale 1ns/1ps
// Complete ordered hull/contour -> convexity-defect chain. Hull may arrive in
// ANY order. Repeated contour coordinates use their LAST occurrence, exactly
// like the software reference. Path excludes both endpoints and wraps once.
// One shared 14400x16 scratch: contour[0:8191], hull[8192:8511],
// last-contour-index[8704:9023]. No additional frame/contour RAM is required
// when EXTERNAL_MEMORY=1. Memory accepts read/write only on ready; read data
// is synchronous, available the cycle after an accepted read. No concurrent
// memory owner may change data before that response is consumed.
// start -> hull stream (last may be sent alone for empty hull) -> contour
// stream -> edge results. Radius is captured at contour_last (must be valid
// then, so a preceding geometry stage can compute it while loading hull).
// All streams transfer on valid && ready; end alone
// transfers when ready. clear aborts; no memory response may remain in flight.
module ua_hand_defect_scan #(
 parameter EXTERNAL_MEMORY=0,MAX_HULL=320,MAX_CONTOUR=8192,MAX_CYCLES=8000000
)(
 input I_clk,I_rst_n,I_clear,I_start,input[10:0]I_radius_q4,
 input I_hull_valid,I_hull_last,input[7:0]I_hull_x,input[6:0]I_hull_y,
 output O_hull_ready,
 input I_contour_valid,I_contour_last,input[7:0]I_contour_x,input[6:0]I_contour_y,
 output O_contour_ready,
 output O_edge_valid,input I_edge_ready,
 output[7:0]O_ax,O_bx,output[6:0]O_ay,O_by,
 output O_qualified,O_has_far,output[7:0]O_far_x,output[6:0]O_far_y,
 output[19:0]O_max_cross,output[9:0]O_edge_length,
 output reg O_busy,O_done,O_fault,output reg[8:0]O_hull_count,
 output reg[13:0]O_contour_count,output reg[31:0]O_cycles,
 output O_memory_read,O_memory_write,output reg[13:0]O_memory_address,
 output reg[15:0]O_memory_data,input I_memory_ready,input[15:0]I_memory_data
);
localparam IDLE=0,HULL_LOAD=1,CONTOUR_LOAD=2,MAP_HULL_READ=3,MAP_HULL_WAIT=4,
 MAP_POINT_READ=5,MAP_POINT_WAIT=6,MAP_WRITE=7,PICK_INIT=8,PICK_READ=9,
 PICK_WAIT=10,PICK_FINISH=11,COORD_READ=12,COORD_WAIT=13,EDGE_START=14,
 PATH_READ=15,PATH_WAIT=16,PATH_SEND=17,EDGE_WAIT=18,EDGE_PRESENT=19,
 FINISH=20,FAIL=21;
reg[4:0]state;
reg[10:0]radius;
reg[8:0]hindex,pick_scan,best_slot,current_slot,first_slot,edge_number;
reg[12:0]point_index,last_index,best_index,current_index,first_index,next_index,path_index;
reg found,best_found,initial_pick;
reg[14:0]map_point,a,b,first_point,held_point;
wire[15:0]memory_q;
wire memory_ready=EXTERNAL_MEMORY ? I_memory_ready : 1'b1;
wire edge_ready,edge_done,edge_fault;
wire mem_read_state=state==MAP_HULL_READ || state==MAP_POINT_READ ||
 state==PICK_READ || state==COORD_READ || state==PATH_READ;
wire hull_write=state==HULL_LOAD && I_hull_valid && O_hull_count<MAX_HULL;
wire contour_write=state==CONTOUR_LOAD && I_contour_valid && O_contour_count<MAX_CONTOUR;
wire mem_write_state=hull_write || contour_write || state==MAP_WRITE;
wire enabled=I_rst_n && !I_clear;
assign O_memory_read=enabled && mem_read_state;
assign O_memory_write=enabled && mem_write_state;
assign O_hull_ready=enabled && state==HULL_LOAD && memory_ready;
assign O_contour_ready=enabled && state==CONTOUR_LOAD && memory_ready;
assign O_edge_valid=enabled && state==EDGE_PRESENT;
assign O_ax=a[7:0];assign O_ay=a[14:8];assign O_bx=b[7:0];assign O_by=b[14:8];
always @*begin
 O_memory_address=0;O_memory_data=0;
 case(state)
 HULL_LOAD:begin O_memory_address=14'd8192+{5'd0,O_hull_count};O_memory_data={1'b0,I_hull_y,I_hull_x};end
 CONTOUR_LOAD:begin O_memory_address=O_contour_count;O_memory_data={1'b0,I_contour_y,I_contour_x};end
 MAP_HULL_READ:O_memory_address=14'd8192+{5'd0,hindex};
 MAP_POINT_READ:O_memory_address={1'b0,point_index};
 MAP_WRITE:begin O_memory_address=14'd8704+{5'd0,hindex};O_memory_data={2'd0,found,last_index};end
 PICK_READ:O_memory_address=14'd8704+{5'd0,pick_scan};
 COORD_READ:O_memory_address=14'd8192+{5'd0,best_slot};
 PATH_READ:O_memory_address={1'b0,path_index};
 endcase
end
generate if(EXTERNAL_MEMORY)begin:gen_external
 assign memory_q=I_memory_data;
end else begin:gen_private
 ua_hand_scratch_ram storage(I_clk,O_memory_read,O_memory_write,O_memory_address,O_memory_data,memory_q);
end endgenerate
ua_hand_defect_edge edge_core(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(I_clear || state==FAIL),.I_start(state==EDGE_START),
 .I_ax(a[7:0]),.I_bx(b[7:0]),.I_ay(a[14:8]),.I_by(b[14:8]),.I_radius_q4(radius),
 .I_point_valid(state==PATH_SEND && path_index!=next_index),
 .I_path_end(state==PATH_SEND && (path_index==next_index ||
   (path_index==O_contour_count-1 ? 13'd0 : path_index+13'd1)==next_index)),
 .I_x(held_point[7:0]),.I_y(held_point[14:8]),.O_point_ready(edge_ready),
 .O_busy(),.O_done(edge_done),.O_fault(edge_fault),.O_qualified(O_qualified),
 .O_has_far(O_has_far),.O_far_x(O_far_x),.O_far_y(O_far_y),
 .O_max_cross(O_max_cross),.O_edge_length(O_edge_length));
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
  state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_hull_count<=0;O_contour_count<=0;O_cycles<=0;
  radius<=0;hindex<=0;point_index<=0;last_index<=0;found<=0;map_point<=0;
  pick_scan<=0;best_slot<=0;best_index<=0;best_found<=0;initial_pick<=0;
  current_slot<=0;current_index<=0;first_slot<=0;first_index<=0;first_point<=0;
  next_index<=0;path_index<=0;a<=0;b<=0;held_point<=0;edge_number<=0;
 end else if(I_clear)begin
  state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_hull_count<=0;O_contour_count<=0;O_cycles<=0;
 end else begin
  O_done<=0;
  if(O_busy)O_cycles<=O_cycles+32'd1;
  if(O_busy && state!=FAIL && state!=FINISH && O_cycles>=MAX_CYCLES)state<=FAIL;
  else case(state)
  IDLE:if(I_start)begin
   O_busy<=1;O_fault<=0;O_hull_count<=0;O_contour_count<=0;O_cycles<=0;radius<=I_radius_q4;state<=HULL_LOAD;
  end
  HULL_LOAD:if(O_hull_ready && (I_hull_valid || I_hull_last))begin
   if(I_hull_valid && (O_hull_count>=MAX_HULL || I_hull_x>=160 || I_hull_y>=90))state<=FAIL;
   else begin
    if(I_hull_valid)O_hull_count<=O_hull_count+9'd1;
    if(I_hull_last)state<=CONTOUR_LOAD;
   end
  end
  CONTOUR_LOAD:if(O_contour_ready && (I_contour_valid || I_contour_last))begin
   if(I_contour_valid && (O_contour_count>=MAX_CONTOUR || I_contour_x>=160 || I_contour_y>=90))state<=FAIL;
   else begin
    if(I_contour_valid)O_contour_count<=O_contour_count+14'd1;
    if(I_contour_last)begin radius<=I_radius_q4;hindex<=0;state<=MAP_HULL_READ;end
   end
  end
  MAP_HULL_READ:begin
   if(O_contour_count<3)state<=FINISH;
   else if(O_hull_count==0)state<=FAIL;
   else if(memory_ready)state<=MAP_HULL_WAIT;
  end
  MAP_HULL_WAIT:begin map_point<=memory_q[14:0];point_index<=0;last_index<=0;found<=0;state<=MAP_POINT_READ;end
  MAP_POINT_READ:if(memory_ready)state<=MAP_POINT_WAIT;
  MAP_POINT_WAIT:begin
   if(memory_q[14:0]==map_point)begin last_index<=point_index;found<=1;end
   if({1'b0,point_index}==O_contour_count-1)state<=MAP_WRITE;
   else begin point_index<=point_index+13'd1;state<=MAP_POINT_READ;end
  end
  MAP_WRITE:if(!found)state<=FAIL;
   else if(memory_ready)begin
    if(hindex==O_hull_count-1)begin initial_pick<=1;edge_number<=0;state<=PICK_INIT;end
    else begin hindex<=hindex+9'd1;state<=MAP_HULL_READ;end
   end
  PICK_INIT:begin pick_scan<=0;best_found<=0;state<=PICK_READ;end
  PICK_READ:if(memory_ready)state<=PICK_WAIT;
  PICK_WAIT:begin
   if(!memory_q[13])state<=FAIL;
   else begin
    if((initial_pick || memory_q[12:0]>current_index) && (!best_found || memory_q[12:0]<best_index))begin
     best_found<=1;best_index<=memory_q[12:0];best_slot<=pick_scan;
    end
    if(pick_scan==O_hull_count-1)state<=PICK_FINISH;
    else begin pick_scan<=pick_scan+9'd1;state<=PICK_READ;end
   end
  end
  PICK_FINISH:begin
   if(!best_found)begin
    if(initial_pick || edge_number!=O_hull_count-1)state<=FAIL;
    else begin b<=first_point;next_index<=first_index;state<=EDGE_START;end
   end else state<=COORD_READ;
  end
  COORD_READ:if(memory_ready)state<=COORD_WAIT;
  COORD_WAIT:begin
   if(initial_pick)begin
    a<=memory_q[14:0];current_slot<=best_slot;current_index<=best_index;
    first_slot<=best_slot;first_index<=best_index;first_point<=memory_q[14:0];
    initial_pick<=0;state<=PICK_INIT;
   end else begin b<=memory_q[14:0];next_index<=best_index;state<=EDGE_START;end
  end
  EDGE_START:begin
   path_index<=({1'b0,current_index}==O_contour_count-1) ? 13'd0 : current_index+13'd1;
   state<=PATH_READ;
  end
  PATH_READ:if(path_index==next_index)state<=PATH_SEND;
   else if(memory_ready)state<=PATH_WAIT;
  PATH_WAIT:begin held_point<=memory_q[14:0];state<=PATH_SEND;end
  PATH_SEND:if(edge_ready)begin
   if(path_index==next_index || (path_index==O_contour_count-1 ? 13'd0 : path_index+13'd1)==next_index)state<=EDGE_WAIT;
   else begin path_index<=path_index==O_contour_count-1 ? 13'd0 : path_index+13'd1;state<=PATH_READ;end
  end
  EDGE_WAIT:if(edge_done)state<=edge_fault ? FAIL : EDGE_PRESENT;
  EDGE_PRESENT:if(I_edge_ready)begin
   if(edge_number==O_hull_count-1)state<=FINISH;
   else begin edge_number<=edge_number+9'd1;a<=b;current_index<=next_index;state<=PICK_INIT;end
  end
  FINISH:begin O_busy<=0;O_done<=1;state<=IDLE;end
  FAIL:begin O_busy<=0;O_done<=1;O_fault<=1;state<=IDLE;end
  default:state<=FAIL;
  endcase
 end
end
endmodule
