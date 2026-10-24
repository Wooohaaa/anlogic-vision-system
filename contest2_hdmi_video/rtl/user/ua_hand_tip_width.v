`timescale 1ns/1ps
// Exact two-cut finger-width probes from hand_fixed_classifier.width_checks.
// Center/tip use pixels, radius Q4; normals/midpoints use signed pixel Q8.
// Cuts are 205/256 and 230/256 of center->tip. Samples span +/-2*floor(R).
// Pick the nearest foreground pivot within 0.8R (negative side wins a tie),
// then count only that contiguous run. Missing cuts remain explicitly invalid.
// One variable-latency bitmap probe may be outstanding. Clear drains an old
// response before start_ready is raised; it never aliases the next job.
module ua_hand_tip_width(
 input I_clk,I_rst_n,I_clear,I_start,
 input[7:0]I_width,I_center_x,I_tip_x,
 input[6:0]I_height,I_center_y,I_tip_y,
 input[10:0]I_radius_q4,
 output O_start_ready,O_probe,
 output[7:0]O_probe_x,output[6:0]O_probe_y,
 input I_probe_ready,I_probe_valid,I_probe_pixel,
 output reg O_busy,O_done,O_fault,O_narrow,
 output reg[1:0]O_width_valid,
 output reg[8:0]O_width0,O_width1
);
localparam IDLE=0,SQUARE_MUL=1,SQRT_START=2,SQRT_WAIT=3,
 NX_START=4,NX_WAIT=5,NY_START=6,NY_WAIT=7,MID_MUL=8,MID_EVAL=9,
 START_MUL=10,LINE_INIT=11,SAMPLE=12,REQUEST=13,RESPONSE=14,
 CONSUME=15,FINAL_EVAL=16,FINISH=17,FAIL=18;
reg[4:0]state;
reg[7:0]width,cx;reg[6:0]height,cy;
reg[10:0]radius;reg[6:0]radius_int;
reg signed[9:0]dx,dy,nx,ny;
reg[9:0]length;
reg cut,pending,foreground,pivot_found,run_selected;
reg[8:0]run_length,best_width,best_distance;
reg signed[9:0]step;
reg signed[19:0]mid_x,mid_y,sample_x,sample_y;
reg signed[9:0]ma,mb,mc,md;
reg signed[19:0]product1,product2;
wire signed[20:0]sum_products={product1[19],product1}+{product2[19],product2};
wire[9:0]dx_abs=dx[9] ? -dx : dx;
wire[9:0]dy_abs=dy[9] ? -dy : dy;
wire[31:0]normal_numerator=({22'd0,(state==NX_START ? dy_abs : dx_abs)}<<8)+{23'd0,length[9:1]};
wire math_done,math_fault;wire[31:0]math_result;
ua_hand_integer_math math_core(.I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(I_clear || state==FAIL),
 .I_start(state==SQRT_START || state==NX_START || state==NY_START),.I_sqrt(state==SQRT_START),
 .I_a(state==SQRT_START ? {11'd0,sum_products} : normal_numerator),.I_b({22'd0,length}),
 .O_busy(),.O_done(math_done),.O_fault(math_fault),.O_result(math_result),.O_remainder());
function signed[19:0]round_half;
 input signed[19:0]v;
 begin round_half=v<0 ? -(((-v)+20'sd1)>>>1) : ((v+20'sd1)>>>1);end
endfunction
function signed[11:0]round_pixel;
 input signed[19:0]v;
 reg signed[19:0]r;
 begin r=v<0 ? -(((-v)+20'sd128)>>>8) : ((v+20'sd128)>>>8);round_pixel=r[11:0];end
endfunction
wire signed[11:0]sx=round_pixel(sample_x),sy=round_pixel(sample_y);
wire point_in_bounds=sx>=0 && sy>=0 && sx<$signed({4'd0,width}) && sy<$signed({5'd0,height});
wire[8:0]step_abs=step[9] ? -step : step;
wire[13:0]pivot_limit=({5'd0,step_abs}<<4)+({5'd0,step_abs}<<2);
wire new_pivot=foreground && pivot_limit<={3'd0,radius} && (!pivot_found || step_abs<best_distance);
wire found_next=pivot_found || new_pivot;
wire[8:0]run_next=run_length+9'd1;
wire[8:0]final_width=foreground ? ((run_selected || new_pivot) ? run_next : best_width) :
                                             (run_selected ? run_length : best_width);
wire[8:0]largest_width=O_width_valid[0] && (!O_width_valid[1] || O_width0>=O_width1) ? O_width0 : O_width1;
wire[16:0]width_scaled=({8'd0,largest_width}<<7)+({8'd0,largest_width}<<5);
wire[16:0]radius_scaled=({6'd0,radius}<<3)+({6'd0,radius}<<1)+{6'd0,radius};
assign O_start_ready=state==IDLE && !pending && I_rst_n && !I_clear;
assign O_probe=state==REQUEST && I_rst_n && !I_clear;
assign O_probe_x=sx[7:0];assign O_probe_y=sy[6:0];
always @*begin
 ma=0;mb=0;mc=0;md=0;
 case(state)
 SQUARE_MUL:begin ma=dx;mb=dx;mc=dy;md=dy;end
 MID_MUL:begin ma=dx;mb=cut ? 10'sd230 : 10'sd205;mc=dy;md=mb;end
 START_MUL:begin ma=nx;mb=$signed({2'd0,radius_int,1'b0});mc=ny;md=mb;end
 endcase
end
always @(posedge I_clk)if(state==SQUARE_MUL || state==MID_MUL || state==START_MUL)begin
 product1<=ma*mb;product2<=mc*md;
end
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)pending<=0;
 else if(O_probe && I_probe_ready)pending<=1;
 else if(I_probe_valid)pending<=0;
end
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
  state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_narrow<=0;O_width_valid<=0;O_width0<=0;O_width1<=0;
  width<=0;height<=0;cx<=0;cy<=0;radius<=0;radius_int<=0;dx<=0;dy<=0;nx<=0;ny<=0;length<=0;
  cut<=0;foreground<=0;pivot_found<=0;run_selected<=0;run_length<=0;best_width<=0;best_distance<=0;
  step<=0;mid_x<=0;mid_y<=0;sample_x<=0;sample_y<=0;
 end else if(I_clear)begin
  state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_narrow<=0;O_width_valid<=0;O_width0<=0;O_width1<=0;
 end else begin
  O_done<=0;
  case(state)
  IDLE:if(I_start && O_start_ready)begin
   O_busy<=1;O_fault<=0;O_narrow<=0;O_width_valid<=0;O_width0<=0;O_width1<=0;
   width<=I_width;height<=I_height;cx<=I_center_x;cy<=I_center_y;radius<=I_radius_q4;radius_int<=I_radius_q4[10:4];cut<=0;
   dx<=($signed({1'b0,I_tip_x})-$signed({1'b0,I_center_x}))*10'sd2;
   dy<=($signed({2'd0,I_tip_y})-$signed({2'd0,I_center_y}))*10'sd2;
   if(I_width==0 || I_width>160 || I_height==0 || I_height>90 || I_center_x>=I_width || I_tip_x>=I_width || I_center_y>=I_height || I_tip_y>=I_height)state<=FAIL;
   else if(I_radius_q4<16 || (I_tip_x==I_center_x && I_tip_y==I_center_y))state<=FINISH;
   else state<=SQUARE_MUL;
  end
  SQUARE_MUL:state<=SQRT_START;
  SQRT_START:state<=SQRT_WAIT;
  SQRT_WAIT:if(math_done)begin length<=math_result[9:0];state<=math_fault || math_result==0 ? FAIL : NX_START;end
  NX_START:state<=NX_WAIT;
  NX_WAIT:if(math_done)begin nx<=dy>0 ? -$signed(math_result[9:0]) : $signed(math_result[9:0]);state<=math_fault ? FAIL : NY_START;end
  NY_START:state<=NY_WAIT;
  NY_WAIT:if(math_done)begin ny<=dx<0 ? -$signed(math_result[9:0]) : $signed(math_result[9:0]);state<=math_fault ? FAIL : MID_MUL;end
  MID_MUL:state<=MID_EVAL;
  MID_EVAL:begin mid_x<=$signed({4'd0,cx,8'd0})+round_half(product1);mid_y<=$signed({5'd0,cy,8'd0})+round_half(product2);state<=START_MUL;end
  START_MUL:state<=LINE_INIT;
  LINE_INIT:begin
   sample_x<=mid_x-product1;sample_y<=mid_y-product2;step<=-$signed({2'd0,radius_int,1'b0});
   pivot_found<=0;run_selected<=0;run_length<=0;best_width<=0;best_distance<=0;state<=SAMPLE;
  end
  SAMPLE:if(point_in_bounds)state<=REQUEST;else begin foreground<=0;state<=CONSUME;end
  REQUEST:if(I_probe_ready)state<=RESPONSE;
  RESPONSE:if(I_probe_valid && pending)begin foreground<=I_probe_pixel;state<=CONSUME;end
  CONSUME:begin
   if(new_pivot)begin pivot_found<=1;best_distance<=step_abs;run_selected<=1;end
   if(foreground)run_length<=run_next;
   else begin if(run_selected)best_width<=run_length;run_length<=0;run_selected<=0;end
   if(step==$signed({2'd0,radius_int,1'b0}))begin
    if(!cut)begin O_width_valid[0]<=found_next;O_width0<=found_next ? final_width : 9'd0;cut<=1;state<=MID_MUL;end
    else begin O_width_valid[1]<=found_next;O_width1<=found_next ? final_width : 9'd0;state<=FINAL_EVAL;end
   end else begin sample_x<=sample_x+nx;sample_y<=sample_y+ny;step<=step+10'sd1;state<=SAMPLE;end
  end
  FINAL_EVAL:begin O_narrow<=(|O_width_valid) && width_scaled<=radius_scaled;state<=FINISH;end
  FINISH:begin O_busy<=0;O_done<=1;state<=IDLE;end
  FAIL:begin O_busy<=0;O_fault<=1;O_done<=1;state<=IDLE;end
  default:state<=FAIL;
  endcase
 end
end
endmodule
