`timescale 1ns/1ps
// Hardware bridge: CCL exact red sums + persistent pixel label map -> the
// association core's OWN descriptor RAM. No duplicate descriptor frame RAM.
// Collect BOTH seed/grown CCL blobs first; only then may labels overwrite R.
// At most 128 final blobs total (both modes); overflow is a frame fault.
// CCL anchors are actual earliest component pixels, not bbox corners.
// Scratch is synchronous one-cycle; descriptor query is ready/valid.
// Clear is a new frame boundary; association must also be cleared/initialized.
module ua_hand_descriptor_build(
 input I_clk,I_rst_n,I_clear,I_start,
 input I_blob_valid,I_blob_mode,input[7:0]I_blob_anchor_x,input[6:0]I_blob_anchor_y,
 input[23:0]I_blob_red_sum,output O_blob_ready,O_start_ready,
 output O_memory_read,output[13:0]O_memory_address,input I_memory_ready,input[15:0]I_memory_data,
 output O_query,output O_query_mode,output[6:0]O_query_root,
 input I_query_ready,I_query_valid,input[95:0]I_query_data,
 output O_descriptor_valid,output O_descriptor_mode,output[6:0]O_descriptor_root,
 output reg[95:0]O_descriptor_data,input I_descriptor_ready,
 output reg O_busy,O_done,O_fault,output reg[31:0]O_cycles
);
localparam IDLE=0,MAP_READ=1,MAP_WAIT=2,MODE=3,QUERY=4,QUERY_WAIT=5,
 RED_READ=6,RED_WAIT=7,WRITE=8,NEXT_MODE=9,ADVANCE=10,FINISH=11,FAIL=12;
reg[3:0]state;
reg[7:0]raw_count,x;
reg[6:0]y,raw_index,root;
reg mode;reg[13:0]address;reg[15:0]map_word;
reg[39:0]raw_q;
/* fehdl force_ram=1, ram_style="bram" */ reg[39:0]red_records[0:511];
wire live=I_rst_n && !I_clear;
wire[7:0]selected_root=mode ? map_word[15:8] : map_word[7:0];
wire[11:0]block_row=({6'd0,y[6:1]}<<6)+({6'd0,y[6:1]}<<4);
wire[11:0]block_key=block_row+{5'd0,x[7:1]};
assign O_blob_ready=state==IDLE && live && raw_count<128 && !I_start;
assign O_start_ready=state==IDLE && live && !I_blob_valid;
assign O_memory_read=state==MAP_READ && live;
assign O_memory_address=address;
assign O_query=state==QUERY && live;
assign O_query_mode=mode;assign O_query_root=root;
assign O_descriptor_valid=state==WRITE && live;
assign O_descriptor_mode=mode;assign O_descriptor_root=root;
always @(posedge I_clk)begin
 if(I_blob_valid && O_blob_ready)red_records[{2'd0,raw_count[6:0]}]<={I_blob_mode,I_blob_anchor_y,I_blob_anchor_x,I_blob_red_sum};
 if(live && state==RED_READ)raw_q<=red_records[{2'd0,raw_index}];
end
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
  state<=IDLE;raw_count<=0;x<=0;y<=0;raw_index<=0;root<=0;mode<=0;address<=0;map_word<=0;
  O_descriptor_data<=0;O_busy<=0;O_done<=0;O_fault<=0;O_cycles<=0;
 end else if(I_clear)begin
  state<=IDLE;raw_count<=0;O_busy<=0;O_done<=0;O_fault<=0;O_cycles<=0;
 end else begin
  O_done<=0;if(O_busy)O_cycles<=O_cycles+32'd1;
  if(I_blob_valid && O_blob_ready)raw_count<=raw_count+8'd1;
  else if(I_blob_valid && state==IDLE && raw_count==128)O_fault<=1;
  case(state)
  IDLE:if(I_start && O_start_ready)begin
   O_busy<=1;O_cycles<=0;address<=0;x<=0;y<=0;state<=O_fault ? FAIL : MAP_READ;
  end
  MAP_READ:if(I_memory_ready)state<=MAP_WAIT;
  MAP_WAIT:begin map_word<=I_memory_data;mode<=0;state<=MODE;end
  MODE:if(selected_root[7])state<=FAIL;
   else if(selected_root==0)state<=NEXT_MODE;
   else begin root<=selected_root[6:0];state<=QUERY;end
  QUERY:if(I_query_ready)state<=QUERY_WAIT;
  QUERY_WAIT:if(I_query_valid)begin
   if(I_query_data[59:46]==0)begin
    raw_index<=0;state<=raw_count==0 ? FAIL : RED_READ;
   end else begin
    O_descriptor_data<=I_query_data;
    O_descriptor_data[59:46]<=I_query_data[59:46]+14'd1;
    if(block_key<I_query_data[95:84])O_descriptor_data[95:84]<=block_key;
    if(x>I_query_data[30:23])O_descriptor_data[30:23]<=x;
    if(x<I_query_data[22:15])O_descriptor_data[22:15]<=x;
    if(y>I_query_data[14:8])O_descriptor_data[14:8]<=y;
    if(y<I_query_data[7:1])O_descriptor_data[7:1]<=y;
    state<=WRITE;
   end
  end
  RED_READ:state<=RED_WAIT;
  RED_WAIT:if(raw_q[39:24]=={mode,y,x})begin
   O_descriptor_data<={block_key,raw_q[23:0],14'd1,x,y,x,x,y,y,1'b0};state<=WRITE;
  end else if({1'b0,raw_index}+8'd1==raw_count)state<=FAIL;
  else begin raw_index<=raw_index+7'd1;state<=RED_READ;end
  WRITE:if(I_descriptor_ready)state<=NEXT_MODE;
  NEXT_MODE:if(!mode)begin mode<=1;state<=MODE;end else state<=ADVANCE;
  ADVANCE:if(address==14399)state<=FINISH;
   else begin
    address<=address+14'd1;
    if(x==159)begin x<=0;y<=y+7'd1;end else x<=x+8'd1;
    state<=MAP_READ;
   end
  FINISH:begin O_busy<=0;O_done<=1;state<=IDLE;end
  FAIL:begin O_busy<=0;O_done<=1;O_fault<=1;state<=IDLE;end
  default:state<=FAIL;
  endcase
 end
end
endmodule
