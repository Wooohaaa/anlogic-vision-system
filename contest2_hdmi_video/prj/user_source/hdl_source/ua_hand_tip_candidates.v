`timescale 1ns/1ps
// Hull fallback + qualified-edge endpoint gates + exact distance/lexicographic
// ranking and spatial deduplication. Output is BEFORE width/axial/thumb tests,
// not a gesture ID. At seven distinct tips, further tips cannot change the
// reference's saturated count or OPEN decision and are not materialized.
// Context must be ready at start. Feed all hull points, then qualified edges,
// then edges_end alone. Output holds until ready. Clear aborts immediately.
// External scratch candidate range [9216,9855], one cycle synchronous reads.
module ua_hand_tip_candidates #(parameter EXTERNAL_MEMORY=0,MAX_CANDIDATES=640)(
 input I_clk,I_rst_n,I_clear,I_start,
 input[7:0]I_center_x,input[6:0]I_center_y,input[10:0]I_radius_q4,
 input signed[9:0]I_wrist_dx2,I_wrist_dy2,
 input I_hull_valid,I_hull_last,input[7:0]I_hull_x,input[6:0]I_hull_y,output O_hull_ready,
 input I_edge_valid,I_edge_qualified,I_edges_end,input[7:0]I_ax,I_bx,input[6:0]I_ay,I_by,output O_edge_ready,
 output O_tip_valid,input I_tip_ready,output[7:0]O_tip_x,output[6:0]O_tip_y,output O_tip_last,
 output reg[2:0]O_tip_count,output reg O_busy,O_done,O_fault,
 output O_memory_read,O_memory_write,output[13:0]O_memory_address,output[15:0]O_memory_data,
 input I_memory_ready,input[15:0]I_memory_data
);
localparam IDLE=0,WRIST_MUL=1,SQRT_START=2,SQRT_WAIT=3,RADIUS_MUL=4,RADIUS_EVAL=5,
 HULL_RECEIVE=6,EDGE_RECEIVE=7,POINT_SQUARE=8,POINT_SQUARE_EVAL=9,
 POINT_DOT=10,POINT_DOT_EVAL=11,STORE=12,ADVANCE=13,SORT_INIT=14,
 SORT_READ=15,SORT_WAIT=16,SORT_NEXT=17,MARK=18,DEDUP_INIT=19,
 DEDUP_NEXT=20,ACCEPT=21,OUTPUT=22,FINISH=23,FAIL=24;
localparam KIND_HULL=0,KIND_A=1,KIND_B=2,KIND_FALLBACK=3,KIND_SORT=4,KIND_DEDUP=5;
reg[4:0]state;reg[2:0]kind;
reg[7:0]cx,px,bx,best_x,fallback_x;reg[6:0]cy,py,by,best_y,fallback_y;
reg signed[9:0]wx,wy;
reg[10:0]radius;reg[9:0]wrist_length;
reg[23:0]radius2,radius_length;reg[17:0]distance2,best_distance,fallback_distance;
reg hull_last,fallback_found,best_found;reg[9:0]candidate_count,scan_index,best_slot;
reg[2:0]tip_index,output_index;
reg[14:0]tips[0:6];
reg signed[11:0]ma,mb,mc,md;
reg signed[23:0]product1,product2;
wire signed[24:0]sum_products={product1[23],product1}+{product2[23],product2};
wire signed[9:0]dx=($signed({1'b0,px})-$signed({1'b0,cx}))*10'sd2;
wire signed[9:0]dy=($signed({2'b0,py})-$signed({2'b0,cy}))*10'sd2;
wire signed[9:0]dedup_dx=($signed({1'b0,best_x})-$signed({1'b0,tips[tip_index][7:0]}))*10'sd2;
wire signed[9:0]dedup_dy=($signed({2'b0,best_y})-$signed({2'b0,tips[tip_index][14:8]}))*10'sd2;
wire[31:0]scaled_radius9=({8'd0,radius2}<<3)+{8'd0,radius2};
wire[31:0]fallback100=({14'd0,fallback_distance}<<6)+({14'd0,fallback_distance}<<5)+({14'd0,fallback_distance}<<2);
wire signed[31:0]dot80=($signed(sum_products)<<<6)+($signed(sum_products)<<<4);
wire[31:0]negative_dot16=(-$signed(sum_products))<<<4;
wire endpoint_pass=({14'd0,distance2}<<4)>={8'd0,radius2} && sum_products<0 && negative_dot16>{8'd0,radius_length};
wire[39:0]separation=({15'd0,sum_products}<<14)+({15'd0,sum_products}<<13)+({15'd0,sum_products}<<10);
wire[39:0]radius169=({16'd0,radius2}<<7)+({16'd0,radius2}<<5)+({16'd0,radius2}<<3)+{16'd0,radius2};
wire math_done,math_fault;wire[31:0]math_q;
ua_hand_integer_math math_core(.I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(I_clear || state==FAIL),
 .I_start(state==SQRT_START),.I_sqrt(1'b1),.I_a({7'd0,sum_products}),.I_b(32'd0),
 .O_busy(),.O_done(math_done),.O_fault(math_fault),.O_result(math_q),.O_remainder());
wire[15:0]memory_q;wire memory_ready=EXTERNAL_MEMORY ? I_memory_ready : 1'b1;
assign O_hull_ready=state==HULL_RECEIVE && I_rst_n && !I_clear;
assign O_edge_ready=state==EDGE_RECEIVE && I_rst_n && !I_clear;
assign O_tip_valid=state==OUTPUT && I_rst_n && !I_clear;
assign O_tip_x=tips[output_index][7:0];assign O_tip_y=tips[output_index][14:8];
assign O_tip_last=output_index+3'd1==O_tip_count;
assign O_memory_read=state==SORT_READ && I_rst_n && !I_clear;
assign O_memory_write=((state==STORE && candidate_count<MAX_CANDIDATES) || state==MARK) && I_rst_n && !I_clear;
wire[9:0]memory_slot=state==STORE ? candidate_count : state==MARK ? best_slot : scan_index;
assign O_memory_address=14'd9216+{4'd0,memory_slot};
assign O_memory_data=state==MARK ? {1'b1,best_y,best_x} : {1'b0,py,px};
generate if(EXTERNAL_MEMORY)begin:gen_external
 assign memory_q=I_memory_data;
end else begin:gen_private
 /* fehdl force_ram=1, ram_style="bram" */ reg[15:0]candidates[0:1023];
 reg[15:0]q;
 always @(posedge I_clk)begin
  if(O_memory_read)q<=candidates[memory_slot];
  if(O_memory_write)candidates[memory_slot]<=O_memory_data;
 end
 assign memory_q=q;
end endgenerate
always @*begin
 ma=0;mb=0;mc=0;md=0;
 case(state)
 WRIST_MUL:begin ma=wx;mb=wx;mc=wy;md=wy;end
 RADIUS_MUL:begin ma=$signed({1'b0,radius});mb=ma;mc=ma;md=$signed({2'd0,wrist_length});end
 POINT_SQUARE:begin
  ma=kind==KIND_DEDUP ? dedup_dx : dx;mb=ma;
  mc=kind==KIND_DEDUP ? dedup_dy : dy;md=mc;
 end
 POINT_DOT:begin ma=dx;mb=wx;mc=dy;md=wy;end
 endcase
end
always @(posedge I_clk)if(state==WRIST_MUL || state==RADIUS_MUL || state==POINT_SQUARE || state==POINT_DOT)begin
 product1<=ma*mb;product2<=mc*md;
end
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
  state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_tip_count<=0;
  cx<=0;cy<=0;wx<=0;wy<=0;radius<=0;wrist_length<=0;radius2<=0;radius_length<=0;
  px<=0;py<=0;bx<=0;by<=0;best_x<=0;best_y<=0;fallback_x<=0;fallback_y<=0;
  distance2<=0;best_distance<=0;fallback_distance<=0;hull_last<=0;fallback_found<=0;best_found<=0;
  candidate_count<=0;scan_index<=0;best_slot<=0;tip_index<=0;output_index<=0;kind<=0;
 end else if(I_clear)begin state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_tip_count<=0;end
 else begin
  O_done<=0;
  case(state)
  IDLE:if(I_start)begin
   O_busy<=1;O_fault<=0;O_tip_count<=0;candidate_count<=0;fallback_found<=0;
   cx<=I_center_x;cy<=I_center_y;wx<=I_wrist_dx2;wy<=I_wrist_dy2;radius<=I_radius_q4;
   state<=I_center_x>=160 || I_center_y>=90 ? FAIL : WRIST_MUL;
  end
  WRIST_MUL:state<=SQRT_START;
  SQRT_START:state<=SQRT_WAIT;
  SQRT_WAIT:if(math_done)begin wrist_length<=math_q[9:0];state<=math_fault ? FAIL : RADIUS_MUL;end
  RADIUS_MUL:state<=RADIUS_EVAL;
  RADIUS_EVAL:begin radius2<=product1;radius_length<=product2;state<=HULL_RECEIVE;end
  HULL_RECEIVE:begin
   if(I_hull_valid)begin
    px<=I_hull_x;py<=I_hull_y;hull_last<=I_hull_last;kind<=KIND_HULL;
    state<=I_hull_x>=160 || I_hull_y>=90 ? FAIL : POINT_SQUARE;
   end else if(I_hull_last)state<=EDGE_RECEIVE;
  end
  EDGE_RECEIVE:begin
   if(I_edge_valid && I_edge_qualified)begin
    px<=I_ax;py<=I_ay;bx<=I_bx;by<=I_by;kind<=KIND_A;
    state<=I_ax>=160 || I_bx>=160 || I_ay>=90 || I_by>=90 ? FAIL : POINT_SQUARE;
   end else if(I_edges_end)begin
    if(candidate_count==0 && fallback_found && fallback100>=scaled_radius9)begin
     px<=fallback_x;py<=fallback_y;kind<=KIND_FALLBACK;state<=POINT_SQUARE;
    end else state<=SORT_INIT;
   end
  end
  POINT_SQUARE:state<=POINT_SQUARE_EVAL;
  POINT_SQUARE_EVAL:begin
   distance2<=sum_products[17:0];
   if(kind==KIND_SORT)begin
    if(!best_found || sum_products>{7'd0,best_distance} ||
      (sum_products=={7'd0,best_distance} && (px<best_x || (px==best_x && py<best_y))))begin
     best_found<=1;best_distance<=sum_products[17:0];best_x<=px;best_y<=py;best_slot<=scan_index;
    end
    state<=SORT_NEXT;
   end else if(kind==KIND_DEDUP)state<=separation<=radius169 ? SORT_INIT : DEDUP_NEXT;
   else state<=POINT_DOT;
  end
  POINT_DOT:state<=POINT_DOT_EVAL;
  POINT_DOT_EVAL:begin
   if(kind==KIND_HULL)begin
    if(dot80<$signed({8'd0,radius_length}) && (!fallback_found || distance2>fallback_distance ||
       (distance2==fallback_distance && (px>fallback_x || (px==fallback_x && py>fallback_y)))))begin
     fallback_found<=1;fallback_distance<=distance2;fallback_x<=px;fallback_y<=py;
    end
    state<=hull_last ? EDGE_RECEIVE : HULL_RECEIVE;
   end else state<=endpoint_pass ? STORE : ADVANCE;
  end
  STORE:if(candidate_count>=MAX_CANDIDATES)state<=FAIL;
   else if(memory_ready)begin candidate_count<=candidate_count+10'd1;state<=ADVANCE;end
  ADVANCE:begin
   if(kind==KIND_A)begin px<=bx;py<=by;kind<=KIND_B;state<=POINT_SQUARE;end
   else state<=kind==KIND_FALLBACK ? SORT_INIT : EDGE_RECEIVE;
  end
  SORT_INIT:begin
   scan_index<=0;best_found<=0;state<=candidate_count==0 ? FINISH : SORT_READ;
  end
  SORT_READ:if(memory_ready)state<=SORT_WAIT;
  SORT_WAIT:begin
   if(memory_q[15])state<=SORT_NEXT;
   else begin px<=memory_q[7:0];py<=memory_q[14:8];kind<=KIND_SORT;state<=POINT_SQUARE;end
  end
  SORT_NEXT:begin
   if(scan_index==candidate_count-1)state<=best_found ? MARK : (O_tip_count==0 ? FINISH : OUTPUT);
   else begin scan_index<=scan_index+10'd1;state<=SORT_READ;end
   output_index<=0;
  end
  MARK:if(memory_ready)begin tip_index<=0;state<=O_tip_count==0 ? ACCEPT : DEDUP_INIT;end
  DEDUP_INIT:begin kind<=KIND_DEDUP;state<=POINT_SQUARE;end
  DEDUP_NEXT:if(tip_index==O_tip_count-1)state<=ACCEPT;
   else begin tip_index<=tip_index+3'd1;state<=DEDUP_INIT;end
  ACCEPT:begin
   tips[O_tip_count]<={best_y,best_x};O_tip_count<=O_tip_count+3'd1;output_index<=0;
   state<=O_tip_count==6 ? OUTPUT : SORT_INIT;
  end
  OUTPUT:if(I_tip_ready)begin
   if(O_tip_last)state<=FINISH;else output_index<=output_index+3'd1;
  end
  FINISH:begin O_busy<=0;O_done<=1;state<=IDLE;end
  FAIL:begin O_busy<=0;O_done<=1;O_fault<=1;state<=IDLE;end
  default:state<=FAIL;
  endcase
 end
end
endmodule
