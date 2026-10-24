`ifndef UA_RAW_BLACK_40_V
`define UA_RAW_BLACK_40_V
// Combinational RAW10 pedestal subtraction, before demosaic/AWB.
// Lane order/sideband timing unchanged. BLACK_LEVEL=0 is exact bypass.
// Nonzero black: clamp, round before existing >>2 converter, saturate.
// 64 is a measured TEST estimate, not a claimed sensor specification.
module ua_raw_black_40 #(
    parameter [9:0] BLACK_LEVEL=10'd0
)(input [39:0] I_raw, output [39:0] O_raw);
    function [9:0] correct;
      input [9:0] c;
      reg [10:0] rounded;
      begin
        if(BLACK_LEVEL==0) correct=c;
        else if(c<=BLACK_LEVEL) correct=10'd0;
        else begin
          rounded={1'b0,c}-{1'b0,BLACK_LEVEL}+11'd2;
          correct=(rounded>11'd1023)?10'd1023:rounded[9:0];
        end
      end
    endfunction
    assign O_raw={correct(I_raw[39:30]),correct(I_raw[29:20]),
                  correct(I_raw[19:10]),correct(I_raw[9:0])};
endmodule
`endif
