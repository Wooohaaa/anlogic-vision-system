`timescale 1ns/1ps
// Persistent 8-connected labels for exact seed/grown overlap association.
// Call ONLY after both modes' red statistics have consumed the red frame.
// Reuses the classifier 14400x16 scratch: seed in low byte, grown high byte.
// The seed pass initializes whole words; grown preserves the seed byte.
// Labels are union roots, NOT OpenCV dense IDs. After done each region has a
// unique root; caller ranks by earliest 2x2 block for OpenCV default ordering.
// Fixed one-cycle synchronous scratch read, gated by I_memory_ready. Only
// one outstanding mask read, variable latency. Clear drains mask responses.
// Every lifetime label is persistent (never recycled). Overflow invalidates
// the entire map. No published provisional result is valid on fault.
module ua_hand_label_map #(parameter WIDTH=160,HEIGHT=90,LABELS=128)(
 input I_clk,I_rst_n,I_clear,I_start,I_mode,
 output O_start_ready,output reg O_read,output reg[11:0]O_read_addr,
 input I_read_valid,input[17:0]I_read_data,
 output O_memory_read,O_memory_write,output[13:0]O_memory_address,
 output[15:0]O_memory_data,input I_memory_ready,input[15:0]I_memory_data,
 output reg O_busy,O_done,O_fault,output reg[7:0]O_labels,
 output reg[31:0]O_cycles
);
localparam WORDS=(WIDTH+5)/6,PIXELS=WIDTH*HEIGHT;
localparam IDLE=0,INIT=1,REQUEST=2,WAIT_MASK=3,PIXEL=4,NEIGHBOR=5,
 ROOT=6,UNION=7,ASSIGN=8,READ_OLD=9,WAIT_OLD=10,WRITE=11,ADVANCE=12,
 COMPRESS=13,COMPRESS_ROOT=14,COMPRESS_WRITE=15,NORM_READ=16,
 NORM_WAIT=17,NORM_WRITE=18,FINISH=19,FAIL=20;
reg[4:0]state;
reg mode,source_pending;
reg[7:0]x,chosen,root,neighbor_left,neighbor_up_left,neighbor_up,neighbor_right,up_left;
reg[6:0]y;
reg[2:0]slot,neighbor_index;
reg[11:0]mask_address;
reg[13:0]address;
reg[17:0]word_data;
reg[15:0]old_word;
reg[7:0]init_index,compress_index,root_depth;
(* ram_style="dram" *) reg[7:0]parent[0:LABELS-1];
(* ram_style="dram" *) reg[7:0]row_labels[0:WIDTH-1];
wire foreground=mode ? word_data[slot*3+2] : word_data[slot*3];
wire[7:0]neighbor=neighbor_index==0 ? neighbor_left : neighbor_index==1 ? neighbor_up_left :
                    neighbor_index==2 ? neighbor_up : neighbor_right;
wire[7:0]parent_q=parent[root];
wire live=I_rst_n && !I_clear;
assign O_start_ready=state==IDLE && !source_pending && live;
assign O_memory_read=live && (state==READ_OLD || state==NORM_READ);
assign O_memory_write=live && (state==WRITE || state==NORM_WRITE);
assign O_memory_address=address;
assign O_memory_data=state==NORM_WRITE ?
 (mode ? {parent_q,old_word[7:0]} : {old_word[15:8],parent_q}) :
 (mode ? {chosen,old_word[7:0]} : {8'd0,chosen});
// Only previous-row slots at x or x+1 are read before overwriting slot x.
// up_left holds the OLD preceding slot, not the just-written current row.
always @(posedge I_clk)if(live && state==ASSIGN)row_labels[x]<=chosen;
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)source_pending<=0;
 else if(O_read)source_pending<=1;
 else if(I_read_valid)source_pending<=0;
end
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
  state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_labels<=0;O_cycles<=0;
  O_read<=0;O_read_addr<=0;mode<=0;x<=0;y<=0;slot<=0;mask_address<=0;address<=0;
  word_data<=0;old_word<=0;chosen<=0;root<=0;neighbor_index<=0;
  neighbor_left<=0;neighbor_up_left<=0;neighbor_up<=0;neighbor_right<=0;up_left<=0;
  init_index<=0;compress_index<=0;root_depth<=0;
 end else if(I_clear)begin
  state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_read<=0;O_labels<=0;O_cycles<=0;
 end else begin
  O_done<=0;O_read<=0;
  if(O_busy)O_cycles<=O_cycles+32'd1;
  case(state)
  IDLE:if(I_start && O_start_ready)begin
   O_busy<=1;O_fault<=0;O_labels<=0;O_cycles<=0;mode<=I_mode;init_index<=0;
   x<=0;y<=0;slot<=0;mask_address<=0;address<=0;neighbor_left<=0;up_left<=0;state<=INIT;
  end
  INIT:begin
   parent[init_index]<=init_index;
   if(init_index==LABELS-1)state<=REQUEST;else init_index<=init_index+8'd1;
  end
  REQUEST:begin O_read<=1;O_read_addr<=mask_address;state<=WAIT_MASK;end
  WAIT_MASK:if(I_read_valid && source_pending)begin word_data<=I_read_data;state<=PIXEL;end
  PIXEL:begin
   neighbor_up_left<=up_left;
   neighbor_up<=y==0 ? 8'd0 : row_labels[x];
   neighbor_right<=(y==0 || x==WIDTH-1) ? 8'd0 : row_labels[x+8'd1];
   chosen<=0;neighbor_index<=0;
   state<=foreground ? NEIGHBOR : ASSIGN;
  end
  NEIGHBOR:if(neighbor_index==4)begin
   if(chosen==0)begin
    if(O_labels==LABELS-1)state<=FAIL;
    else begin O_labels<=O_labels+8'd1;chosen<=O_labels+8'd1;state<=ASSIGN;end
   end else state<=ASSIGN;
  end else if(neighbor==0)neighbor_index<=neighbor_index+3'd1;
  else begin root<=neighbor;root_depth<=0;state<=ROOT;end
  ROOT:if(root>=LABELS)state<=FAIL;
       else if(parent_q==root)state<=UNION;
       else if(root_depth==LABELS-1)state<=FAIL;
       else begin root<=parent_q;root_depth<=root_depth+8'd1;end
  UNION:begin
   if(chosen==0)chosen<=root;
   else if(chosen!=root)begin
    if(chosen<root)parent[root]<=chosen;
    else begin parent[chosen]<=root;chosen<=root;end
   end
   neighbor_index<=neighbor_index+3'd1;state<=NEIGHBOR;
  end
  ASSIGN:begin
   neighbor_left<=chosen;up_left<=neighbor_up;
   state<=mode ? READ_OLD : WRITE;
  end
  READ_OLD:if(I_memory_ready)state<=WAIT_OLD;
  WAIT_OLD:begin old_word<=I_memory_data;state<=WRITE;end
  WRITE:if(I_memory_ready)state<=ADVANCE;
  ADVANCE:if(x==WIDTH-1 && y==HEIGHT-1)begin compress_index<=0;state<=COMPRESS;end
  else begin
   address<=address+14'd1;
   if(x==WIDTH-1)begin x<=0;y<=y+7'd1;slot<=0;mask_address<=mask_address+12'd1;neighbor_left<=0;up_left<=0;state<=REQUEST;end
   else begin
    x<=x+8'd1;
    if(slot==5)begin slot<=0;mask_address<=mask_address+12'd1;state<=REQUEST;end
    else begin slot<=slot+3'd1;state<=PIXEL;end
   end
  end
  COMPRESS:begin root<=compress_index;root_depth<=0;state<=COMPRESS_ROOT;end
  COMPRESS_ROOT:if(parent_q==root)state<=COMPRESS_WRITE;
   else if(root_depth==LABELS-1)state<=FAIL;
   else begin root<=parent_q;root_depth<=root_depth+8'd1;end
  COMPRESS_WRITE:begin
   parent[compress_index]<=root;
   if(compress_index==O_labels)begin address<=0;state<=NORM_READ;end
   else begin compress_index<=compress_index+8'd1;state<=COMPRESS;end
  end
  NORM_READ:if(I_memory_ready)state<=NORM_WAIT;
  NORM_WAIT:begin old_word<=I_memory_data;root<=mode ? I_memory_data[15:8] : I_memory_data[7:0];state<=NORM_WRITE;end
  NORM_WRITE:if(I_memory_ready)begin
   if(address==PIXELS-1)state<=FINISH;else begin address<=address+14'd1;state<=NORM_READ;end
  end
  FINISH:begin O_done<=1;O_busy<=0;state<=IDLE;end
  FAIL:begin O_done<=1;O_busy<=0;O_fault<=1;state<=IDLE;end
  default:state<=FAIL;
  endcase
 end
end
`ifndef SYNTHESIS
initial if(WIDTH<1 || WIDTH>160 || HEIGHT<1 || HEIGHT>90 || LABELS<2 || LABELS>256)
 $fatal(1,"invalid label map parameters");
`endif
endmodule
