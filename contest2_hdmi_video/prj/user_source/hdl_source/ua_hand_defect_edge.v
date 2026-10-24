`timescale 1ns/1ps
// One ordered hull edge's convexity defect, matching the integer reference.
// A/B and streamed path points use pixel coordinates; cross/length use half-
// pixel deltas. Keep the first maximum-cross point. Depth >=0.65*radius and
// positive (A-F).(B-F) qualify the edge. This does NOT select/dedup fingertips.
// Path transfer is valid && ready. end may accompany the final point or be
// sent alone for an empty/finished path, only when ready. clear aborts.
module ua_hand_defect_edge(
 input I_clk,I_rst_n,I_clear,I_start,
 input[7:0]I_ax,I_bx,input[6:0]I_ay,I_by,input[10:0]I_radius_q4,
 input I_point_valid,I_path_end,input[7:0]I_x,input[6:0]I_y,
 output O_point_ready,output reg O_busy,O_done,O_fault,O_qualified,O_has_far,
 output reg[7:0]O_far_x,output reg[6:0]O_far_y,
 output reg[19:0]O_max_cross,output reg[9:0]O_edge_length
);
localparam IDLE=0,NORM_MUL=1,NORM_START=2,NORM_WAIT=3,RECEIVE=4,
 CROSS_MUL=5,CROSS_EVAL=6,DEPTH_MUL=7,DEPTH_EVAL=8,ANGLE_MUL=9,ANGLE_EVAL=10,FINISH=11,FAIL=12;
reg[3:0]state;
reg[7:0]ax,bx,px;reg[6:0]ay,by,py;reg[10:0]radius;
reg signed[9:0]edge_dx,edge_dy,rel_x,rel_y;
reg signed[23:0]product1,product2;
reg signed[11:0]mul_a,mul_b,mul_c,mul_d;
reg path_last,depth_pass;
wire signed[24:0]cross_value={product1[23],product1}-{product2[23],product2};
wire[24:0]cross_abs=cross_value[24] ? -cross_value : cross_value;
wire signed[24:0]sum_products={product1[23],product1}+{product2[23],product2};
wire signed[9:0]far_ax=($signed({1'b0,ax})-$signed({1'b0,O_far_x}))*10'sd2;
wire signed[9:0]far_ay=($signed({2'b0,ay})-$signed({2'b0,O_far_y}))*10'sd2;
wire signed[9:0]far_bx=($signed({1'b0,bx})-$signed({1'b0,O_far_x}))*10'sd2;
wire signed[9:0]far_by=($signed({2'b0,by})-$signed({2'b0,O_far_y}))*10'sd2;
wire[31:0]depth_left=({12'd0,O_max_cross}<<7)+({12'd0,O_max_cross}<<5);
wire[31:0]depth_right=({8'd0,product1}<<3)+({8'd0,product1}<<2)+{8'd0,product1};
wire math_done,math_fault;wire[31:0]math_q;
ua_hand_integer_math math_core(.I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(I_clear || state==FAIL),
 .I_start(state==NORM_START),.I_sqrt(1'b1),.I_a({7'd0,sum_products}),.I_b(32'd0),
 .O_busy(),.O_done(math_done),.O_fault(math_fault),.O_result(math_q),.O_remainder());
assign O_point_ready=state==RECEIVE;
always @*begin
 mul_a=0;mul_b=0;mul_c=0;mul_d=0;
 case(state)
 NORM_MUL:begin mul_a=edge_dx;mul_b=edge_dx;mul_c=edge_dy;mul_d=edge_dy;end
 CROSS_MUL:begin mul_a=edge_dx;mul_b=rel_y;mul_c=edge_dy;mul_d=rel_x;end
 DEPTH_MUL:begin mul_a=$signed({1'b0,radius});mul_b=$signed({2'd0,O_edge_length});end
 ANGLE_MUL:begin mul_a=far_ax;mul_b=far_bx;mul_c=far_ay;mul_d=far_by;end
 endcase
end
always @(posedge I_clk)begin
 if(state==NORM_MUL || state==CROSS_MUL || state==DEPTH_MUL || state==ANGLE_MUL)begin
  product1<=mul_a*mul_b;product2<=mul_c*mul_d;
 end
end
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
  state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_qualified<=0;O_has_far<=0;
  O_far_x<=0;O_far_y<=0;O_max_cross<=0;O_edge_length<=0;
  ax<=0;ay<=0;bx<=0;by<=0;px<=0;py<=0;radius<=0;edge_dx<=0;edge_dy<=0;rel_x<=0;rel_y<=0;path_last<=0;depth_pass<=0;
 end else if(I_clear)begin
  state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_qualified<=0;O_has_far<=0;
 end else begin
  O_done<=0;
  case(state)
  IDLE:if(I_start)begin
   O_busy<=1;O_fault<=0;O_qualified<=0;O_has_far<=0;O_max_cross<=0;O_edge_length<=0;O_far_x<=0;O_far_y<=0;
   ax<=I_ax;ay<=I_ay;bx<=I_bx;by<=I_by;radius<=I_radius_q4;
   edge_dx<=($signed({1'b0,I_bx})-$signed({1'b0,I_ax}))*10'sd2;
   edge_dy<=($signed({2'd0,I_by})-$signed({2'd0,I_ay}))*10'sd2;
   state<=I_ax>=160 || I_bx>=160 || I_ay>=90 || I_by>=90 ? FAIL : NORM_MUL;
  end
  NORM_MUL:state<=NORM_START;
  NORM_START:state<=NORM_WAIT;
  NORM_WAIT:if(math_done)begin O_edge_length<=math_q[9:0];state<=math_fault ? FAIL : RECEIVE;end
  RECEIVE:begin
   if(I_point_valid)begin
    px<=I_x;py<=I_y;path_last<=I_path_end;
    rel_x<=($signed({1'b0,I_x})-$signed({1'b0,ax}))*10'sd2;
    rel_y<=($signed({2'd0,I_y})-$signed({2'd0,ay}))*10'sd2;
    state<=I_x>=160 || I_y>=90 ? FAIL : CROSS_MUL;
   end else if(I_path_end)state<=DEPTH_MUL;
  end
  CROSS_MUL:state<=CROSS_EVAL;
  CROSS_EVAL:begin
   if(cross_abs>{5'd0,O_max_cross})begin O_max_cross<=cross_abs[19:0];O_far_x<=px;O_far_y<=py;O_has_far<=1;end
   state<=path_last ? DEPTH_MUL : RECEIVE;
  end
  DEPTH_MUL:state<=DEPTH_EVAL;
  DEPTH_EVAL:begin depth_pass<=depth_left>=depth_right;state<=ANGLE_MUL;end
  ANGLE_MUL:state<=ANGLE_EVAL;
  ANGLE_EVAL:begin O_qualified<=O_has_far && O_edge_length!=0 && depth_pass && sum_products>0;state<=FINISH;end
  FINISH:begin O_busy<=0;O_done<=1;state<=IDLE;end
  FAIL:begin O_busy<=0;O_fault<=1;O_done<=1;state<=IDLE;end
  default:state<=FAIL;
  endcase
 end
end
endmodule
