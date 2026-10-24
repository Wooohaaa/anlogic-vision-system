`timescale 1ns/1ps
// Shared 32-bit unsigned restoring divider and integer square-root engine.
// sqrt: floor(sqrt(A)), remainder=A-root*root, 16 iteration clocks.
// divide: floor(A/B), remainder=A%B, 32 iteration clocks. B=0 is a fault.
// Launch only idle; busy starts are ignored. clear aborts with no done pulse.
// Outputs stay stable after completion until the next launch/clear/reset.
module ua_hand_integer_math(
 input I_clk,I_rst_n,I_clear,I_start,I_sqrt,
 input[31:0]I_a,I_b,
 output reg O_busy,O_done,O_fault,
 output reg[31:0]O_result,O_remainder
);
reg square_root;
reg[5:0]left;
reg[31:0]shift,denominator,quotient;
reg[32:0]remainder;
wire[32:0]minuend=square_root ? {15'd0,remainder[15:0],shift[31:30]} :
                                              {remainder[31:0],shift[31]};
wire[32:0]subtrahend=square_root ? {15'd0,quotient[15:0],2'b01} : {1'b0,denominator};
wire[33:0]difference={1'b0,minuend}-{1'b0,subtrahend};
wire accept=!difference[33];
wire[32:0]next_remainder=accept ? difference[32:0] : minuend;
wire[31:0]next_quotient={quotient[30:0],accept};
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
  O_busy<=0;O_done<=0;O_fault<=0;O_result<=0;O_remainder<=0;
  square_root<=0;left<=0;shift<=0;denominator<=0;quotient<=0;remainder<=0;
 end else if(I_clear)begin
  O_busy<=0;O_done<=0;O_fault<=0;O_result<=0;O_remainder<=0;
 end else begin
  O_done<=0;
  if(!O_busy)begin
   if(I_start)begin
    O_result<=0;O_remainder<=0;O_fault<=0;
    if(!I_sqrt && I_b==0)begin O_fault<=1;O_done<=1;end
    else begin
     O_busy<=1;square_root<=I_sqrt;left<=I_sqrt ? 6'd16 : 6'd32;
     shift<=I_a;denominator<=I_b;quotient<=0;remainder<=0;
    end
   end
  end else begin
   remainder<=next_remainder;quotient<=next_quotient;
   shift<=square_root ? {shift[29:0],2'b00} : {shift[30:0],1'b0};
   left<=left-6'd1;
   if(left==1)begin
    O_result<=next_quotient;O_remainder<=next_remainder[31:0];O_busy<=0;O_done<=1;
   end
  end
 end
end
endmodule
