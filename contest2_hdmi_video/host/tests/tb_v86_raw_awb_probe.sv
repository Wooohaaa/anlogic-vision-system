`timescale 1ns/1ps
// Diagnostic: actual maintained RAW decoder, row bridge and adaptive AWB.
module tb_v86_raw_awb_probe;
 parameter W=1280,H=8,FRAMES=28;
 localparam G=W/4;
 reg clk=0,rst=0,v=0,u=0,l=0;reg[39:0]raw=0;
 always #5 clk=~clk;
 wire[127:0]decoded;wire dv,du,dl;wire[95:0]rgb,repaired;
 wire rv,ru,rl;
 wire ml,mu,mv,by;wire[95:0]lastrow,currow,nextrow;
 // Wire the two production submodules exactly as demosaic.v; its legacy
 // nested comment syntax is rejected by Icarus, so do not rewrite vendor RTL.
 raw_matrix_3x3_buffer #(.IMG_WIDTH(W),.IMG_HEIGHT(H))decoder(
 .I_clk(clk),.I_rst_n(rst),.axi4s_video_tdata(raw),.axi4s_video_tdest(10'd0),
 .axi4s_video_tlast(l),.axi4s_video_tvalid(v),.axi4s_video_tuser(u),
 .O_tvalid(mv),.O_tuser(mu),.O_tlast(ml),.O_tready(1'b1),
 .bayer_ypos(by),.matrix_last_line(lastrow),.matrix_cur_line(currow),.matrix_next_line(nextrow));
 bilinear_interpolation #(.BAYER_MODE("BGGR"))interpolate(
 .I_clk(clk),.I_rst_n(rst),.I_tlast(ml),.I_tuser(mu),.I_tvalid(mv),.bayer_ypos(by),
 .matrix_last_line(lastrow),.matrix_cur_line(currow),.matrix_next_line(nextrow),
 .O_tdata(decoded),.O_tvalid(dv),.O_tuser(du),.O_tlast(dl),.O_tready(1'b1));
 data128_96 cv(decoded,rgb);
 ua_top_row_repair_v85 #(.IMG_WIDTH(W),.IMG_HEIGHT(H))repair(clk,rst,rgb,dv,du,dl,repaired,rv,ru,rl);
 wire[1:0]ov;wire[107:0]od[0:1];
 genvar g;generate for(g=0;g<2;g=g+1)begin:path
 ua_awb_frame #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.OUTPUT_CHANNEL_BITS(9),.RUNTIME_CONTROL(1))awb(
 .I_clk(clk),.I_rst_n(rst),.I_tdata(g==0?rgb:repaired),.I_tvalid(g==0?dv:rv),
 .I_tuser(g==0?du:ru),.I_tlast(g==0?dl:rl),.I_enable(1'b1),.O_tready(1'b1),
 .O_tvalid(ov[g]),.O_tdata(od[g]));
 end endgenerate
 integer dc=0,rc=0,ds=0,rs=0,dlast=0,rlast=0,du_invalid=0;
 reg[95:0]frame[0:G*H-1];
 always @(negedge clk)if(rst)begin
 if(du)begin ds=ds+1;if(!dv)du_invalid=du_invalid+1;end
 if(ru)rs=rs+1;
 if(dv)begin frame[dc%(G*H)]=rgb;dc=dc+1;if(dl)dlast=dlast+1;end
 if(rv)begin
 if(repaired!==frame[((rc%(G*H))/G==0)?G+(rc%G):rc%(G*H)])
 $fatal(1,"bridge changed RGB at group=%0d data=%h",rc,repaired);
 rc=rc+1;if(rl)rlast=rlast+1;
 end
 end
 task idle(input integer n);integer k;begin for(k=0;k<n;k=k+1)begin @(negedge clk);v=0;u=0;l=0;end end endtask
 integer f,y,x,k,value;
 initial begin
 repeat(5)@(negedge clk);rst=1;
 for(f=0;f<FRAMES;f=f+1)begin
 for(y=0;y<H;y=y+1)begin
 for(x=0;x<G;x=x+1)begin
 @(negedge clk);v=1;u=y==0&&x==0;l=x==G-1;
 for(k=0;k<4;k=k+1)begin
 value=(!y[0] && !k[0])?70:(y[0] && k[0])?70:100;
 raw[k*10+:10]=10'(value*4);
 end
 end
 idle(100);
 end
 idle(4*G+1000);
 end
 idle(1000);
 $display("RAW_AWB_PROBE decoded=%0d repaired=%0d SOF=%0d/%0d EOL=%0d/%0d earlySOF=%0d gains=%0d,%0d / %0d,%0d samples=%0d/%0d line=%0d/%0d",dc,rc,ds,rs,dlast,rlast,du_invalid,
 path[0].awb.gain_r,path[0].awb.gain_b,path[1].awb.gain_r,path[1].awb.gain_b,path[0].awb.sample_count,path[1].awb.sample_count,path[0].awb.line_index,path[1].awb.line_index);
 if(dc!=FRAMES*G*H || rc!=dc || ds!=FRAMES || rs!=FRAMES || dlast!=FRAMES*H || rlast!=dlast)$fatal(1,"RAW bridge contract failed");
 if(path[1].awb.gain_r<80000 || path[1].awb.gain_b<80000)$fatal(1,"green cast not corrected");
 $display("V86_RAW_AWB_PROBE_PASS_NOT_BOARD");$finish;
 end
 initial begin #30000000;$fatal(1,"timeout");end
endmodule
