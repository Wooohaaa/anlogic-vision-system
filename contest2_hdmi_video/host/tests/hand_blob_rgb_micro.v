`include "../../../rtl/user/ua_hand_blob_scan.v"
module hand_blob_rgb_micro(
 input clk,rst,clear,start,mode,input mv,input[17:0]md,input rv,input[9:0]rd,
 output mr,output[11:0]ma,output rr,output[13:0]ra,output[3:0]status,output[31:0]checksum
);
wire[13:0]area,seeds;wire[7:0]xmin,xmax,ax;wire[6:0]ymin,ymax,ay;wire[23:0]redsum;
ua_hand_blob_scan #(.RGB_STATS(1)) core(clk,rst,clear,start,mode,mr,ma,mv,md,
 status[3],status[2],status[1],status[0],area,seeds,xmin,xmax,ymin,ymax,ax,ay,rr,ra,rv,rd,redsum);
assign checksum={area,seeds,4'd0}^{xmin,xmax,ymin,ymax,2'd0}^{ax,ay,17'd0}^{redsum,8'd0};
endmodule
