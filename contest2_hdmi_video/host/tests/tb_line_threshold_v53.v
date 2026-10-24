`timescale 1ns/1ps
// Exhaust all modular 24-bit residuals, including the signed minimum.
module tb_line_threshold_v53;
function legacy;
 input[23:0]error;
 reg[23:0]magnitude;
 begin magnitude=error[23]?(~error+24'd1):error;legacy=(magnitude<=24'd2048);end
endfunction
function candidate;
 input signed[23:0]error;
 begin candidate=(error>=-24'sd2048)&&(error<=24'sd2048);end
endfunction
integer i;
initial begin
 for(i=0;i<16777216;i=i+1)
  if(legacy(i[23:0])!==candidate(i[23:0]))$fatal(1,"LINE_THRESHOLD_MISMATCH residual=%h",i[23:0]);
 $display("LINE_THRESHOLD_EXHAUSTIVE_PASS cases=16777216");$finish;
end
endmodule
