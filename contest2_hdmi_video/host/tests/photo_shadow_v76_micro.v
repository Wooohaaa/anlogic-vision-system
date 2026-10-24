`include "rtl/user/ua_photo_finish_96.v"
module photo_shadow_v76_core #(parameter BOOST=0)(input clk,rst,valid,user,last,
 input [107:0]data,input[1:0]strength,output[26:0]result);
 wire[95:0]pixels;
 ua_photo_finish_96 #(.INPUT_BITS(9),.RUNTIME_STRENGTH(1),.HIGHLIGHT_SAFE_LIFT(1),
  .SHADOW_COLOR_DENOISE(1),.GENTLE_SHADOW_LIFT(1),.SELECTIVE_SHADOW_BOOST(BOOST)) core(
 clk,rst,valid,user,last,data,strength,result[26],result[25],result[24],pixels);
 assign result[23:0]=pixels[95:72]^pixels[71:48]^pixels[47:24]^pixels[23:0];
endmodule
module photo_shadow_v75_micro(input clk,rst,valid,user,last,input[107:0]data,input[1:0]strength,output[26:0]result);
 photo_shadow_v76_core #(.BOOST(0))core(clk,rst,valid,user,last,data,strength,result);
endmodule
module photo_shadow_v76_micro(input clk,rst,valid,user,last,input[107:0]data,input[1:0]strength,output[26:0]result);
 photo_shadow_v76_core #(.BOOST(1))core(clk,rst,valid,user,last,data,strength,result);
endmodule
