`timescale 1ns/1ps
// Candidate-list transaction -> actual selected-component geometry -> exact
// frame winner -> temporal result. List entries require finalized CCL red sum,
// true anchor and seed/grown association in reference order. That association
// and mask/frontend ownership remain caller responsibilities, NOT software
// geometry injected into this core. Mask bank immutable until O_done.
// No video backpressure. O_* result registers update atomically on O_done.
module ua_hand_frame_classifier #(parameter EXTERNAL_SCRATCH=0)(
 input I_clk,I_rst_n,I_clear,I_start,
 input I_candidate_valid,I_finish,I_mode,
 input[7:0]I_x,I_width,I_anchor_x,input[6:0]I_y,I_height,I_anchor_y,
 input[13:0]I_area,input[23:0]I_red_sum,input[13:0]I_bright_count,
 output O_start_ready,O_candidate_ready,O_read,output[11:0]O_read_addr,
 input I_read_valid,input[17:0]I_read_data,
 output reg O_busy,O_done,O_fault,output reg[1:0]O_id,O_raw,
 output reg O_box_valid,output reg[2:0]O_tips,
 output reg[7:0]O_x,O_width,output reg[6:0]O_y,O_height,
 output reg[10:0]O_radius_q4,output reg[9:0]O_mean_r,
 output O_backlit,
 input I_scratch_read,I_scratch_write,input[13:0]I_scratch_address,input[15:0]I_scratch_data,
 output O_scratch_ready,O_scratch_valid,output[15:0]O_scratch_data
);
localparam IDLE=0,BEGIN=1,RECEIVE=2,SHAPE_START=3,SHAPE_WAIT=4,
 POLICY_SUBMIT=5,POLICY_FINISH=6,POLICY_WAIT=7,COMMIT=8,FAIL=9;
reg[3:0]state;
reg mode;reg[7:0]x,width,anchor_x;reg[6:0]y,height,anchor_y;
reg[13:0]area,bright;reg[23:0]red_sum;
wire abort=I_clear || state==FAIL;
wire shape_ready,shape_done,shape_fault;wire[1:0]shape_raw;wire[2:0]shape_tips;
wire[7:0]cx;wire[6:0]cy;wire[10:0]radius;wire[13:0]shape_area;
wire policy_start_ready,policy_ready,policy_done,policy_fault,best_valid;
wire[1:0]best_raw;wire[2:0]best_tips;wire[7:0]best_x,best_width;wire[6:0]best_y,best_height;
wire[10:0]best_radius;wire[9:0]best_mean;
wire vote_valid,vote_box;wire[1:0]vote_id;
wire scratch_idle=EXTERNAL_SCRATCH && state==IDLE && !abort && I_rst_n;
wire scratch_ready,scratch_valid;
assign O_scratch_ready=scratch_idle && scratch_ready;
assign O_scratch_valid=scratch_idle && scratch_valid;
wire[8:0]right={1'b0,I_x}+{1'b0,I_width};
wire[7:0]bottom={1'b0,I_y}+{1'b0,I_height};
wire[10:0]width7=({3'd0,I_width}<<2)+({3'd0,I_width}<<1)+{3'd0,I_width};
wire[10:0]height3=({4'd0,I_height}<<1)+{4'd0,I_height};
wire[10:0]height5=({4'd0,I_height}<<2)+{4'd0,I_height};
wire[10:0]width3=({3'd0,I_width}<<1)+{3'd0,I_width};
// floor(red_sum/area)>=threshold iff red_sum>=area*threshold. This avoids
// expensive geometry for dark/non-hand components without altering the floor.
wire[23:0]threshold_sum=O_backlit ? (({10'd0,I_area}<<7)+({10'd0,I_area}<<5)) :
                                             (({10'd0,I_area}<<6)+({10'd0,I_area}<<5));
wire cheap_pass=I_area>=50 && I_area<=2500 && I_width>=12 && I_height>=10 && I_x>1 && right<159 &&
 bottom<=90 && ({4'd0,I_height}<<1)<=width7 && {3'd0,I_width}<=height3 && height5>=width3 && I_red_sum>=threshold_sum;
assign O_start_ready=state==IDLE && shape_ready && policy_start_ready && I_rst_n && !I_clear;
assign O_candidate_ready=state==RECEIVE && shape_ready && policy_ready && I_rst_n && !abort;
ua_hand_shape_classifier #(.EXTERNAL_SCRATCH(EXTERNAL_SCRATCH)) shape(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(abort),.I_start(state==SHAPE_START),.I_mode(mode),
 .I_xmin(x),.I_width(width),.I_anchor_x(anchor_x),.I_ymin(y),.I_height(height),.I_anchor_y(anchor_y),
 .O_start_ready(shape_ready),.O_read(O_read),.O_read_addr(O_read_addr),.I_read_valid(I_read_valid),.I_read_data(I_read_data),
 .O_busy(),.O_done(shape_done),.O_fault(shape_fault),.O_raw(shape_raw),.O_tip_count(shape_tips),
 .O_center_x(cx),.O_center_y(cy),.O_radius_q4(radius),.O_area(shape_area),.O_cycles(),
 .I_scratch_read(scratch_idle && I_scratch_read),.I_scratch_write(scratch_idle && I_scratch_write),
 .I_scratch_address(I_scratch_address),.I_scratch_data(I_scratch_data),
 .O_scratch_ready(scratch_ready),.O_scratch_valid(scratch_valid),.O_scratch_data(O_scratch_data));
ua_hand_frame_policy policy(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(abort),.I_start(state==BEGIN),
 .I_candidate_valid(state==POLICY_SUBMIT),.I_finish(state==POLICY_FINISH),
 .I_x(x),.I_width(width),.I_center_x(cx),.I_y(y),.I_height(height),.I_center_y(cy),
 .I_area(area),.I_red_sum(red_sum),.I_radius_q4(radius),.I_raw(shape_raw),.I_tips(shape_tips),.I_bright_count(bright),
 .O_start_ready(policy_start_ready),.O_candidate_ready(policy_ready),.O_busy(),.O_done(policy_done),.O_fault(policy_fault),
 .O_backlit(O_backlit),.O_best_valid(best_valid),.O_best_raw(best_raw),.O_best_tips(best_tips),
 .O_best_x(best_x),.O_best_width(best_width),.O_best_center_x(),.O_best_y(best_y),.O_best_height(best_height),.O_best_center_y(),
 .O_best_area(),.O_best_radius_q4(best_radius),.O_best_mean_r(best_mean),.O_best_score());
ua_hand_temporal_vote votes(.I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(abort),
 .I_frame_valid(policy_done && !policy_fault),.I_raw(best_valid ? best_raw : 2'd0),.I_best_present(best_valid),
 .O_valid(vote_valid),.O_id(vote_id),.O_box_valid(vote_box));
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
  state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_id<=0;O_raw<=0;O_box_valid<=0;O_tips<=0;
  O_x<=0;O_y<=0;O_width<=0;O_height<=0;O_radius_q4<=0;O_mean_r<=0;
  mode<=0;x<=0;y<=0;width<=0;height<=0;anchor_x<=0;anchor_y<=0;area<=0;bright<=0;red_sum<=0;
 end else if(I_clear)begin
  state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_id<=0;O_raw<=0;O_box_valid<=0;O_tips<=0;
  O_x<=0;O_y<=0;O_width<=0;O_height<=0;O_radius_q4<=0;O_mean_r<=0;
 end else begin
  O_done<=0;
  if(O_busy && state!=FAIL && ((shape_done && shape_fault) || (policy_done && policy_fault)))state<=FAIL;
  else case(state)
  IDLE:if(I_start && O_start_ready)begin O_busy<=1;O_fault<=0;state<=BEGIN;end
  BEGIN:state<=RECEIVE;
  RECEIVE:if(O_candidate_ready)begin
   if(I_candidate_valid)begin
    if(cheap_pass)begin
     mode<=I_mode;x<=I_x;y<=I_y;width<=I_width;height<=I_height;anchor_x<=I_anchor_x;anchor_y<=I_anchor_y;
     area<=I_area;red_sum<=I_red_sum;state<=SHAPE_START;
    end
   end else if(I_finish)begin bright<=I_bright_count;state<=POLICY_FINISH;end
  end
  SHAPE_START:if(shape_ready)state<=SHAPE_WAIT;
  SHAPE_WAIT:if(shape_done)state<=shape_area!=area ? FAIL : POLICY_SUBMIT;
  POLICY_SUBMIT:if(policy_ready)state<=RECEIVE;
  POLICY_FINISH:if(policy_ready)state<=POLICY_WAIT;
  POLICY_WAIT:if(policy_done)state<=COMMIT;
  COMMIT:if(vote_valid)begin
   O_id<=vote_id;O_raw<=best_valid ? best_raw : 2'd0;O_box_valid<=vote_box;
   O_tips<=best_valid ? best_tips : 3'd0;O_x<=best_valid ? best_x : 8'd0;O_y<=best_valid ? best_y : 7'd0;
   O_width<=best_valid ? best_width : 8'd0;O_height<=best_valid ? best_height : 7'd0;
   O_radius_q4<=best_valid ? best_radius : 11'd0;O_mean_r<=best_valid ? best_mean : 10'd0;
   O_done<=1;O_busy<=0;state<=IDLE;
  end
  FAIL:begin O_done<=1;O_busy<=0;O_fault<=1;O_id<=0;O_raw<=0;O_box_valid<=0;O_tips<=0;state<=IDLE;end
  default:state<=FAIL;
  endcase
 end
end
endmodule
