`include "rtl/user/ua_photo_finish_96.v"
`include "host/tests/reference/ua_photo_finish_v59_reference.v"
module photo_v60_micro(input clk,rst,valid,user,last,input[107:0]data,input[1:0]strength,output[26:0]result);
 wire[95:0]pixels;
 ua_photo_finish_96 #(.INPUT_BITS(9),.RUNTIME_STRENGTH(1),.HIGHLIGHT_SAFE_LIFT(1))core(
 clk,rst,valid,user,last,data,strength,result[26],result[25],result[24],pixels);
 assign result[23:0]=pixels[95:72]^pixels[71:48]^pixels[47:24]^pixels[23:0];
endmodule
module photo_v59_micro(input clk,rst,valid,user,last,input[107:0]data,input[1:0]strength,output[26:0]result);
 wire[95:0]pixels;
 ua_photo_finish_v59_reference #(.INPUT_BITS(9),.RUNTIME_STRENGTH(1),.HIGHLIGHT_SAFE_LIFT(1))core(
 clk,rst,valid,user,last,data,strength,result[26],result[25],result[24],pixels);
 assign result[23:0]=pixels[95:72]^pixels[71:48]^pixels[47:24]^pixels[23:0];
endmodule
