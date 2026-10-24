`timescale 1ns/1ps
// Exact unsigned AxB ->(A+B) product, shared shift/add datapath, B clocks.
// Default 32x32; the classifier uses 42x21 for both metrics and scaled ratios.
// Start accepted only idle; clear aborts and suppresses done.
module ua_hand_product_serial #(parameter A_BITS=32,B_BITS=32,COMPACT=1,HARD_MULTIPLY=0)(
 input I_clk,I_rst_n,I_clear,I_start,input[A_BITS-1:0]I_a,input[B_BITS-1:0]I_b,
 output reg O_busy,O_done,output reg[A_BITS+B_BITS-1:0]O_product
);
localparam RESULT_BITS=A_BITS+B_BITS;
generate if(HARD_MULTIPLY)begin:gen_hardware
// Optional DSP rebalance for slice-limited builds. Exact full-width result,
// one busy clock, no truncation, no operand replacement while busy.
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin O_busy<=0;O_done<=0;O_product<=0;end
 else if(I_clear)begin O_busy<=0;O_done<=0;end
 else begin
  O_done<=0;
  if(O_busy)begin O_busy<=0;O_done<=1;end
  else if(I_start)begin O_product<=I_a*I_b;O_busy<=1;end
 end
end
end else if(COMPACT)begin:gen_compact
// Right-shifting combined product: retain A bits (not A+B) for the fixed
// multiplicand and reuse the result register for both running halves.
// Product is valid only at done/idle; exact latency remains B_BITS clocks.
reg[A_BITS-1:0]operand;reg[5:0]step;
wire[A_BITS:0]upper_sum={1'b0,O_product[RESULT_BITS-1:B_BITS]}+
 (O_product[0] ? {1'b0,operand} : {(A_BITS+1){1'b0}});
wire[RESULT_BITS:0]combined={upper_sum,O_product[B_BITS-1:0]};
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin O_busy<=0;O_done<=0;O_product<=0;operand<=0;step<=0;end
 else if(I_clear)begin O_busy<=0;O_done<=0;end
 else begin
  O_done<=0;
  if(!O_busy)begin
   if(I_start)begin O_busy<=1;operand<=I_a;O_product<={{A_BITS{1'b0}},I_b};step<=0;end
  end else begin
   O_product<=combined[RESULT_BITS:1];step<=step+6'd1;
   if(step==B_BITS-1)begin O_busy<=0;O_done<=1;end
  end
 end
end
end else begin:gen_reference
reg[RESULT_BITS-1:0]multiplicand,accumulator;reg[B_BITS-1:0]multiplier;reg[5:0]step;
wire[RESULT_BITS-1:0]next_accumulator=accumulator+(multiplier[0] ? multiplicand : {RESULT_BITS{1'b0}});
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin O_busy<=0;O_done<=0;O_product<=0;multiplicand<=0;accumulator<=0;multiplier<=0;step<=0;end
 else if(I_clear)begin O_busy<=0;O_done<=0;end
 else begin
  O_done<=0;
  if(!O_busy)begin
   if(I_start)begin O_busy<=1;multiplicand<={{B_BITS{1'b0}},I_a};multiplier<=I_b;accumulator<=0;step<=0;end
  end else begin
   accumulator<=next_accumulator;multiplicand<=multiplicand<<1;multiplier<=multiplier>>1;step<=step+6'd1;
   if(step==B_BITS-1)begin O_product<=next_accumulator;O_busy<=0;O_done<=1;end
  end
 end
end
end endgenerate
endmodule
