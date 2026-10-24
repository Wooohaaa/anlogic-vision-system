`timescale 1ns/1ps
// Exact reference candidate association, no bbox-overlap approximation.
// Descriptors indexed by persistent union root (1..127), loaded before start.
// [95:84] earliest 2x2 block; [83:60] R sum; [59:46] area;
// [45:38]/[37:31] true anchor x/y; [30:23]/[22:15] xmax/xmin;
// [14:8]/[7:1] ymax/ymin (inclusive), bit0 reserved.
// A synchronous scratch map word holds {grown_root,seed_root}. Immutable
// until done. Label-map roots need not be dense or ordered. Rank by area
// descending and block key ascending; overlap ties use LARGER grown block key.
// Candidate output held under backpressure; used-grown suppression happens
// before later hand-policy filters, exactly like the software reference.
module ua_hand_associate #(parameter EXTERNAL_DESCRIPTOR=0)(
 input I_clk,I_rst_n,I_clear,I_start,
 input I_descriptor_valid,I_descriptor_mode,input[6:0]I_descriptor_root,
 input[95:0]I_descriptor_data,output O_descriptor_ready,O_start_ready,
 output O_memory_read,output[13:0]O_memory_address,
 input I_memory_ready,input[15:0]I_memory_data,
 output O_candidate_valid,input I_candidate_ready,output reg O_candidate_mode,
 output reg[95:0]O_candidate_data,
 output reg O_busy,O_done,O_fault,output reg[4:0]O_candidates,
 output reg[31:0]O_cycles,
 // Idle-only descriptor builder access; reuse the same descriptor ERAM.
 input I_query,I_query_mode,input[6:0]I_query_root,
 output O_query_ready,O_query_valid,output[95:0]O_query_data
);
localparam INIT=0,IDLE=1,SELECT=2,SELECT_WAIT=3,HIST_CLEAR=4,
 MAP_READ=5,MAP_WAIT=6,GROWN_READ=7,GROWN_WAIT=8,DECIDE=9,
 PRESENT=10,NEXT=11,FINISH=12,FAIL=13;
reg[3:0]state;
reg[7:0]init_index;
reg[6:0]index,seed_root,grown_root;
reg[4:0]selected;
reg[13:0]best_area,best_overlap,address;
reg[11:0]best_key;
reg[95:0]seed_data,grown_data,meta_q;
reg[127:0]used_seed,used_grown;
reg query_pending;
(* ram_style="dram" *) reg[13:0]histogram[0:127];
/* fehdl force_ram=1, ram_style="bram" */ reg[95:0]descriptors[0:255];
wire live=I_rst_n && !I_clear;
wire query_request=EXTERNAL_DESCRIPTOR ? I_query : 1'b0;
assign O_descriptor_ready=state==IDLE && live && !query_pending;
assign O_query_ready=EXTERNAL_DESCRIPTOR && O_descriptor_ready && !I_descriptor_valid;
wire query_access=O_query_ready && query_request;
assign O_query_valid=state==IDLE && live && query_pending;
assign O_query_data=meta_q;
assign O_start_ready=O_descriptor_ready && !I_descriptor_valid && !query_request;
assign O_memory_read=state==MAP_READ && live;
assign O_memory_address=address;
assign O_candidate_valid=state==PRESENT && live;
wire meta_read=state==SELECT || state==GROWN_READ || query_access;
wire[7:0]meta_address=query_access ? {I_query_mode,I_query_root} : state==GROWN_READ ? {1'b1,index} : {1'b0,index};
wire[13:0]meta_area=meta_q[59:46];
wire[11:0]meta_key=meta_q[95:84];
wire[13:0]overlap_count=histogram[index];
wire grown_usable=grown_root!=0 && grown_data[22:15]>1 && grown_data[30:23]<158 && grown_data[59:46]<=2500;
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)query_pending<=0;
 else if(I_clear)query_pending<=0;
 else query_pending<=query_access;
end
always @(posedge I_clk)begin
 if(live && state==INIT)descriptors[init_index]<=0;
 else if(O_descriptor_ready && I_descriptor_valid)descriptors[{I_descriptor_mode,I_descriptor_root}]<=I_descriptor_data;
 if(live && meta_read)meta_q<=descriptors[meta_address];
 if(live && state==HIST_CLEAR)histogram[index]<=0;
 else if(live && state==MAP_WAIT && I_memory_data[7:0]=={1'b0,seed_root} && I_memory_data[15:8]!=0 && !I_memory_data[15])
  histogram[I_memory_data[14:8]]<=histogram[I_memory_data[14:8]]+14'd1;
end
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
  state<=INIT;init_index<=0;index<=0;selected<=0;seed_root<=0;grown_root<=0;
  best_area<=0;best_overlap<=0;address<=0;best_key<=0;seed_data<=0;grown_data<=0;
  used_seed<=0;used_grown<=0;O_candidate_mode<=0;O_candidate_data<=0;
  O_busy<=0;O_done<=0;O_fault<=0;O_candidates<=0;O_cycles<=0;
 end else if(I_clear)begin
  state<=INIT;init_index<=0;O_busy<=0;O_done<=0;O_fault<=0;O_candidates<=0;O_cycles<=0;
 end else begin
  O_done<=0;if(O_busy)O_cycles<=O_cycles+32'd1;
  case(state)
  INIT:if(init_index==255)state<=IDLE;else init_index<=init_index+8'd1;
  IDLE:if(I_start && O_start_ready)begin
   O_busy<=1;O_fault<=0;O_candidates<=0;O_cycles<=0;used_seed<=0;used_grown<=0;
   selected<=0;index<=1;seed_root<=0;best_area<=0;best_key<=12'hfff;state<=SELECT;
  end
  SELECT:state<=SELECT_WAIT;
  SELECT_WAIT:begin
   if(!used_seed[index] && meta_area!=0 && (meta_area>best_area || (meta_area==best_area && meta_key<best_key)))begin
    seed_root<=index;best_area<=meta_area;best_key<=meta_key;seed_data<=meta_q;
   end
   if(index==127)begin index<=0;state<=HIST_CLEAR;end
   else begin index<=index+7'd1;state<=SELECT;end
  end
  HIST_CLEAR:if(seed_root==0)state<=FINISH;
   else if(index==127)begin
    used_seed[seed_root]<=1;selected<=selected+5'd1;address<=0;state<=MAP_READ;
   end else index<=index+7'd1;
  MAP_READ:if(I_memory_ready)state<=MAP_WAIT;
  MAP_WAIT:if(I_memory_data[15] || I_memory_data[7])state<=FAIL;
   else if(address==14399)begin grown_root<=0;best_overlap<=0;best_key<=0;index<=1;state<=GROWN_READ;end
   else begin address<=address+14'd1;state<=MAP_READ;end
  GROWN_READ:if(overlap_count==0)begin
   if(index==127)state<=DECIDE;else index<=index+7'd1;
  end else state<=GROWN_WAIT;
  GROWN_WAIT:begin
   if(meta_area==0)state<=FAIL;
   else begin
    if(overlap_count>best_overlap || (overlap_count==best_overlap && meta_key>best_key))begin
     grown_root<=index;best_overlap<=overlap_count;best_key<=meta_key;grown_data<=meta_q;
    end
    if(index==127)state<=DECIDE;else begin index<=index+7'd1;state<=GROWN_READ;end
   end
  end
  DECIDE:if(grown_usable && used_grown[grown_root])state<=NEXT;
   else begin
    O_candidate_mode<=grown_usable;O_candidate_data<=grown_usable ? grown_data : seed_data;
    if(grown_usable)used_grown[grown_root]<=1;
    state<=PRESENT;
   end
  PRESENT:if(I_candidate_ready)begin O_candidates<=O_candidates+5'd1;state<=NEXT;end
  NEXT:if(selected==16)state<=FINISH;
   else begin index<=1;seed_root<=0;best_area<=0;best_key<=12'hfff;state<=SELECT;end
  FINISH:begin O_done<=1;O_busy<=0;state<=IDLE;end
  FAIL:begin O_done<=1;O_busy<=0;O_fault<=1;state<=IDLE;end
  default:state<=FAIL;
  endcase
 end
end
endmodule
