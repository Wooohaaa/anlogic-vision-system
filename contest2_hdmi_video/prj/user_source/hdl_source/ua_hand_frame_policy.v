`timescale 1ns/1ps
// Exact post-classification candidate filters / score / frame winner from
// hand_fixed_classifier.classify_video. Inputs are finalized CCL/geometry
// results in reference candidate order; equal scores keep the FIRST entry.
// red_sum is the sum of native 10-bit red samples in the selected component,
// not bbox red or seed-only red. Geometry raw==0 is a valid ambiguous candidate
// and may win. No implicit deletion of software brightness confidence.
// start -> zero/more candidate valid&&ready -> finish alone while ready.
// bright_count is captured on finish; hysteresis affects the NEXT frame.
module ua_hand_frame_policy(
 input I_clk,I_rst_n,I_clear,I_start,
 input I_candidate_valid,I_finish,
 input[7:0]I_x,I_width,I_center_x,input[6:0]I_y,I_height,I_center_y,
 input[13:0]I_area,input[23:0]I_red_sum,input[10:0]I_radius_q4,
 input[1:0]I_raw,input[2:0]I_tips,input[13:0]I_bright_count,
 output O_start_ready,O_candidate_ready,output reg O_busy,O_done,O_fault,O_backlit,
 output reg O_best_valid,output reg[1:0]O_best_raw,output reg[2:0]O_best_tips,
 output reg[7:0]O_best_x,O_best_width,O_best_center_x,
 output reg[6:0]O_best_y,O_best_height,O_best_center_y,
 output reg[13:0]O_best_area,output reg[10:0]O_best_radius_q4,
 output reg[9:0]O_best_mean_r,output reg[26:0]O_best_score
);
localparam IDLE=0,RECEIVE=1,BOX_START=2,BOX_WAIT=3,DIV_START=4,DIV_WAIT=5,
 SCORE_START=6,SCORE_WAIT=7,FINISH=8,FAIL=9;
reg[3:0]state;
reg[7:0]x,width,cx;reg[6:0]y,height,cy;reg[13:0]area;
reg[23:0]red_sum;reg[10:0]radius;reg[1:0]raw;reg[2:0]tips;
reg[9:0]mean_r;reg[15:0]score_factor;
wire[8:0]right={1'b0,I_x}+{1'b0,I_width};
wire[7:0]bottom={1'b0,I_y}+{1'b0,I_height};
wire[10:0]width7=({3'd0,I_width}<<2)+({3'd0,I_width}<<1)+{3'd0,I_width};
wire[10:0]height3=({4'd0,I_height}<<1)+{4'd0,I_height};
wire[10:0]height5=({4'd0,I_height}<<2)+{4'd0,I_height};
wire[10:0]width3=({3'd0,I_width}<<1)+{3'd0,I_width};
wire prefilter=I_area>=50 && I_area<=2500 && I_width>=12 && I_height>=10 &&
 I_x>1 && right<159 && bottom<=90 && I_center_x<I_width && I_center_y<I_height &&
 ({4'd0,I_height}<<1)<=width7 && {3'd0,I_width}<=height3 && height5>=width3 && I_radius_q4>=80;
wire[15:0]height100=({9'd0,height}<<6)+({9'd0,height}<<5)+({9'd0,height}<<2);
wire[15:0]width85=({8'd0,width}<<6)+({8'd0,width}<<4)+({8'd0,width}<<2)+{8'd0,width};
wire[21:0]area100=({8'd0,area}<<6)+({8'd0,area}<<5)+({8'd0,area}<<2);
wire[31:0]product;wire product_done;
wire[15:0]product_a=state==BOX_START ? {8'd0,width} : {2'd0,area};
wire[15:0]product_b=state==BOX_START ? {9'd0,height} : score_factor;
wire[31:0]box60=(product<<5)+(product<<4)+(product<<3)+(product<<2);
wire[7:0]short_side=width<{1'b0,height} ? width : {1'b0,height};
wire short_fist=raw==1 && {10'd0,area100}>=box60 && radius>={1'b0,short_side,2'd0};
ua_hand_product_serial #(.A_BITS(16),.B_BITS(16)) product_core(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(I_clear || state==FAIL),
 .I_start(state==BOX_START || state==SCORE_START),.I_a(product_a),.I_b(product_b),
 .O_busy(),.O_done(product_done),.O_product(product));
wire div_done,div_fault;wire[31:0]quotient;
ua_hand_integer_math divider(.I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(I_clear || state==FAIL),
 .I_start(state==DIV_START),.I_sqrt(1'b0),.I_a({8'd0,red_sum}),.I_b({18'd0,area}),
 .O_busy(),.O_done(div_done),.O_fault(div_fault),.O_result(quotient),.O_remainder());
wire[16:0]mean100=(quotient<<6)+(quotient<<5)+(quotient<<2);
assign O_start_ready=state==IDLE && I_rst_n && !I_clear;
assign O_candidate_ready=state==RECEIVE && I_rst_n && !I_clear;
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
  state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_backlit<=0;O_best_valid<=0;O_best_raw<=0;O_best_tips<=0;
  O_best_x<=0;O_best_y<=0;O_best_width<=0;O_best_height<=0;O_best_center_x<=0;O_best_center_y<=0;
  O_best_area<=0;O_best_radius_q4<=0;O_best_mean_r<=0;O_best_score<=0;
  x<=0;y<=0;width<=0;height<=0;cx<=0;cy<=0;area<=0;red_sum<=0;radius<=0;raw<=0;tips<=0;mean_r<=0;score_factor<=0;
 end else if(I_clear)begin
  state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_backlit<=0;O_best_valid<=0;O_best_raw<=0;O_best_tips<=0;O_best_score<=0;
 end else begin
  O_done<=0;
  case(state)
  IDLE:if(I_start)begin
   O_busy<=1;O_fault<=0;O_best_valid<=0;O_best_raw<=0;O_best_tips<=0;O_best_score<=0;state<=RECEIVE;
  end
  RECEIVE:if(I_candidate_valid)begin
   if(prefilter)begin
    x<=I_x;y<=I_y;width<=I_width;height<=I_height;cx<=I_center_x;cy<=I_center_y;
    area<=I_area;red_sum<=I_red_sum;radius<=I_radius_q4;raw<=I_raw;tips<=I_tips;state<=BOX_START;
   end
  end else if(I_finish)begin
   if(I_bright_count>=450)O_backlit<=1;
   else if(I_bright_count<225)O_backlit<=0;
   state<=FINISH;
  end
  BOX_START:state<=BOX_WAIT;
  BOX_WAIT:if(product_done)state<=height100<width85 && !short_fist ? RECEIVE : DIV_START;
  DIV_START:state<=DIV_WAIT;
  DIV_WAIT:if(div_done)begin
   if(div_fault || quotient>1023)state<=FAIL;
   else if(quotient<(O_backlit ? 160 : 96))state<=RECEIVE;
   else begin
    mean_r<=quotient[9:0];score_factor<=quotient>=384 ? 16'd38400 : mean100[15:0];state<=SCORE_START;
   end
  end
  SCORE_START:state<=SCORE_WAIT;
  SCORE_WAIT:if(product_done)begin
   if(!O_best_valid || product>{5'd0,O_best_score})begin
    O_best_valid<=1;O_best_raw<=raw;O_best_tips<=tips;O_best_x<=x;O_best_y<=y;O_best_width<=width;O_best_height<=height;
    O_best_center_x<=cx;O_best_center_y<=cy;O_best_area<=area;O_best_radius_q4<=radius;
    O_best_mean_r<=mean_r;O_best_score<=product[26:0];
   end
   state<=RECEIVE;
  end
  FINISH:begin O_done<=1;O_busy<=0;state<=IDLE;end
  FAIL:begin O_done<=1;O_busy<=0;O_fault<=1;O_best_valid<=0;O_best_raw<=0;O_best_tips<=0;state<=IDLE;end
  default:state<=FAIL;
  endcase
 end
end
endmodule
