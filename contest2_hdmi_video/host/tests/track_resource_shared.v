`include "../../host/prototypes/ua_track_detect_shared_v51.v"
module track_resource_micro(input clk,rst,last,user,valid,ready,input[95:0]data,output[31:0]checksum);
wire[311:0]actual;
ua_track_detect #(.IMG_WIDTH(1280),.IMG_HEIGHT(720)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_tlast(last),.I_tuser(user),.I_tvalid(valid),.I_tready(ready),.I_tdata(data),
 .O_tlast(actual[311]),.O_tuser(actual[310]),.O_tdata(actual[309:214]),.O_tvalid(actual[213]),.O_tready(actual[212]),
 .O_track_valid(actual[211]),.O_obj_cnt(actual[210:207]),
 .O_v0(actual[206]),.O_x0(actual[205:195]),.O_y0(actual[194:184]),.O_shape0(actual[183:182]),
 .O_xmin0(actual[181:171]),.O_xmax0(actual[170:160]),.O_ymin0(actual[159:149]),.O_ymax0(actual[148:138]),
 .O_v1(actual[137]),.O_x1(actual[136:126]),.O_y1(actual[125:115]),.O_shape1(actual[114:113]),
 .O_xmin1(actual[112:102]),.O_xmax1(actual[101:91]),.O_ymin1(actual[90:80]),.O_ymax1(actual[79:69]),
 .O_v2(actual[68]),.O_x2(actual[67:57]),.O_y2(actual[56:46]),.O_shape2(actual[45:44]),
 .O_xmin2(actual[43:33]),.O_xmax2(actual[32:22]),.O_ymin2(actual[21:11]),.O_ymax2(actual[10:0]));
assign checksum=actual[31:0]^actual[63:32]^actual[95:64]^actual[127:96]^actual[159:128]^actual[191:160]^actual[223:192]^actual[255:224]^actual[287:256]^{8'd0,actual[311:288]};
endmodule
