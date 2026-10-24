`timescale 1ns/1ps
// Exact integer monotone-chain convex hull of a cropped binary component.
// Column extrema replace a general point sort without changing the hull.
// Counter-clockwise output starts at the lexicographically smallest (x,y),
// excludes collinear interior points, and does not repeat the first vertex.
// Selected mask transfer: valid && ready, exact final last. Results stream
// only after the whole hull is complete; hold payload stable under stalls.
// clear aborts and invalid geometry/last produces done && fault.
module ua_hand_convex_hull #(parameter EXTERNAL_MEMORY=0)(
 input I_clk,I_rst_n,I_clear,I_start,
 input[7:0]I_width,input[6:0]I_height,
 input I_mask_valid,I_mask,I_mask_last,
 output O_mask_ready,
 output reg O_busy,O_done,O_fault,
 output O_vertex_valid,input I_vertex_ready,
 output[7:0]O_vertex_x,output[6:0]O_vertex_y,
 output O_vertex_last,output reg[8:0]O_count,
 output O_scratch_read,O_scratch_write,
 output[13:0]O_scratch_address,output[15:0]O_scratch_data,
 input[15:0]I_scratch_data
);
localparam IDLE=0,CLEAR=1,LOAD=2,COLUMN=3,CANDIDATE=4,
           STACK_A=5,STACK_B=6,TURN=7,APPEND=8,ADVANCE=9,
           COMPLETE=10,OUTPUT_READ=11,OUTPUT_PRESENT=12,FINISH=13,FAIL=14;
reg[3:0]state;
reg[7:0]width,x,column,point_x;
reg[6:0]height,y,point_y;
reg upper,second,skip_upper_first;
reg[8:0]length,lower_limit,output_index;
wire[14:0]stack_q;
reg[14:0]a,b;
(* ram_style="dram" *) reg[6:0]min_y[0:159];
(* ram_style="dram" *) reg[6:0]max_y[0:159];
wire[7:0]metadata_address=state==LOAD ? x : column;
wire[6:0]column_min=min_y[metadata_address];
wire[6:0]column_max=max_y[metadata_address];
// Native physical depth ensures TD can infer a synchronous ERAM read.
wire stack_read=state==STACK_A || state==STACK_B || state==OUTPUT_READ;
wire[8:0]stack_address=state==STACK_A ? length-9'd2 :
                              state==STACK_B ? length-9'd1 : output_index;
assign O_scratch_read=stack_read && I_rst_n && !I_clear;
assign O_scratch_write=state==APPEND && I_rst_n && !I_clear;
assign O_scratch_address={5'd0,(O_scratch_write ? length : stack_address)};
assign O_scratch_data={1'b0,point_y,point_x};
generate if(EXTERNAL_MEMORY)begin:gen_external_memory
 assign stack_q=I_scratch_data[14:0];
end else begin:gen_private_memory
 /* fehdl force_ram=1, ram_style="bram" */ reg[14:0]stack[0:511];
 reg[14:0]q;
 always @(posedge I_clk)begin
  if(O_scratch_read)q<=stack[stack_address];
  if(O_scratch_write)stack[length]<={point_y,point_x};
 end
 assign stack_q=q;
end endgenerate
wire signed[8:0]dx1=$signed({1'b0,b[7:0]})-$signed({1'b0,a[7:0]});
wire signed[8:0]dy1=$signed({2'b0,b[14:8]})-$signed({2'b0,a[14:8]});
wire signed[8:0]dx2=$signed({1'b0,point_x})-$signed({1'b0,b[7:0]});
wire signed[8:0]dy2=$signed({2'b0,point_y})-$signed({2'b0,b[14:8]});
wire signed[17:0]product1=dx1*dy2;
wire signed[17:0]product2=dy1*dx2;
wire signed[18:0]cross_value={product1[17],product1}-{product2[17],product2};
assign O_mask_ready=state==LOAD;
assign O_vertex_valid=state==OUTPUT_PRESENT;
assign O_vertex_x=stack_q[7:0];assign O_vertex_y=stack_q[14:8];
assign O_vertex_last=output_index+9'd1==O_count;
always @(posedge I_clk)begin
 if(state==CLEAR)begin min_y[column]<=7'd127;max_y[column]<=0;end
 else if(state==LOAD && I_mask_valid && I_mask)begin
  if(column_min==127)min_y[x]<=y;
  max_y[x]<=y;
 end
end
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
  state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_count<=0;
  width<=0;height<=0;x<=0;y<=0;column<=0;point_x<=0;point_y<=0;
  upper<=0;second<=0;skip_upper_first<=0;length<=0;lower_limit<=0;output_index<=0;a<=0;b<=0;
 end else if(I_clear)begin
  state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_count<=0;
 end else begin
  O_done<=0;
  case(state)
  IDLE:if(I_start)begin
   O_busy<=1;O_fault<=0;O_count<=0;length<=0;column<=0;x<=0;y<=0;
   upper<=0;second<=0;skip_upper_first<=0;
   if(I_width==0 || I_width>160 || I_height==0 || I_height>90)state<=FAIL;
   else begin width<=I_width;height<=I_height;state<=CLEAR;end
  end
  CLEAR:if(column==159)begin column<=0;state<=LOAD;end else column<=column+8'd1;
  LOAD:if(I_mask_valid)begin
   if(I_mask_last!=(x==width-1 && y==height-1))state<=FAIL;
   else if(x==width-1 && y==height-1)begin column<=0;second<=0;state<=COLUMN;end
   else if(x==width-1)begin x<=0;y<=y+7'd1;end else x<=x+8'd1;
  end
  COLUMN:begin
   if(column_min==127 || (second && column_min==column_max))state<=ADVANCE;
   else begin
    point_x<=column;
    point_y<=upper ? (second ? column_min : column_max) : (second ? column_max : column_min);
    state<=CANDIDATE;
   end
  end
  CANDIDATE:begin
   if(upper && skip_upper_first)begin skip_upper_first<=0;state<=ADVANCE;end
   else if(length>=(upper ? lower_limit : 9'd2))state<=STACK_A;
   else state<=APPEND;
  end
  STACK_A:state<=STACK_B;
  STACK_B:begin a<=stack_q;state<=TURN;end
  // b must be captured after the second synchronous read.
  TURN:begin b<=stack_q;state<=COMPLETE;end
  COMPLETE:if(cross_value<=0)begin length<=length-9'd1;state<=CANDIDATE;end
           else state<=APPEND;
  APPEND:if(length>=322)state<=FAIL;
         else begin length<=length+9'd1;state<=ADVANCE;end
  ADVANCE:begin
   if(!second && column_min!=127 && column_min!=column_max)begin second<=1;state<=COLUMN;end
   else begin
    second<=0;
    if(!upper && column+9'd1<{1'b0,width})begin column<=column+8'd1;state<=COLUMN;end
    else if(!upper && length>1)begin
     upper<=1;skip_upper_first<=1;lower_limit<=length+9'd1;column<=width-1;state<=COLUMN;
    end else if(upper && column!=0)begin column<=column-8'd1;state<=COLUMN;end
    else begin
     O_count<=upper ? length-9'd1 : length;output_index<=0;
     state<=length==0 ? FINISH : OUTPUT_READ;
    end
   end
  end
  OUTPUT_READ:state<=OUTPUT_PRESENT;
  OUTPUT_PRESENT:if(I_vertex_ready)begin
   if(O_vertex_last)state<=FINISH;
   else begin output_index<=output_index+9'd1;state<=OUTPUT_READ;end
  end
  FINISH:begin O_done<=1;O_busy<=0;state<=IDLE;end
  FAIL:begin O_fault<=1;O_done<=1;O_busy<=0;state<=IDLE;end
  default:state<=FAIL;
  endcase
 end
end
endmodule
