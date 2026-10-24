`timescale 1ns/1ps
module tb_meter_v75;
reg clk=0,rst=0,v=0,u=0,l=0;always #5 clk=~clk;
reg [95:0] data=0;wire [7:0] mean[0:1];wire [1:0] hs[0:1];wire ft[0:1];
genvar k;
generate for(k=0;k<2;k=k+1)begin:inst
 ua_luma_stats #(.HIGHLIGHT_ENABLE(1),.REFLECTION_TOLERANT(1),.REFLECTION_CEILING(k?96:72)) stats(
 .I_clk(clk),.I_rst_n(rst),.I_tvalid(v),.I_tuser(u),.I_tlast(l),.I_tdata(data),
 .O_luma_mean(mean[k]),.O_frame_toggle(ft[k]),.O_highlight(hs[k]));
end endgenerate
reg crst=0,ct=0;reg [7:0] cy[0:1];wire [15:0] ae[0:1],ag[0:1];wire req[0:1];
reg done[0:1];integer busy[0:1];
generate for(k=0;k<2;k=k+1)begin:ctrl
 ua_auto_exposure #(.LUMA_LOW(48),.LUMA_HIGH(72),.AG_DEFAULT(16),.AUTO_START_WRITE(1),
 .AUTO_FAST(1),.HIGHLIGHT_PROTECT(1),.SUBJECT_FLOOR(40),.CONFIRM_FRAMES(1),.SETTLE_FRAMES(0)) c(
 .I_clk(clk),.I_rst_n(crst),.I_luma_mean(cy[k]),.I_frame_toggle(ct),.I_cam_cfg_done(1'b1),
 .I_ae_cfg_done(done[k]),.I_auto_enable(1'b1),.I_manual_inc(1'b0),.I_manual_dec(1'b0),
 .I_highlight(2'b0),.O_ae_req(req[k]),.O_ae(ae[k]),.O_ag(ag[k]));
 always @(posedge clk)if(!crst)begin done[k]<=1;busy[k]<=0;end
 else if(req[k])begin done[k]<=0;busy[k]<=8;end
 else if(busy[k]>0)begin busy[k]<=busy[k]-1;if(busy[k]==1)done[k]<=1;end
end endgenerate
integer f,x,y,j;reg [23:0] p;reg controls_done=0;
initial begin
 cy[0]=72;cy[1]=96;
 repeat(4)@(negedge clk);crst=1;
 for(j=0;j<30;j=j+1)begin repeat(80)@(negedge clk);ct=~ct;end
 repeat(80)@(negedge clk);
 if(ae[0]!=1990 || ag[0]!=16)$fatal(1,"old plateau fixture moved");
 if(ae[1]>=1990 || ag[1]!=16)$fatal(1,"new bright branch unreachable");
 // Dark scene must still recover rather than permanently cap brightness.
 cy[1]=24;
 for(j=0;j<100;j=j+1)begin repeat(80)@(negedge clk);ct=~ct;end
 if(ae[1]!=1990 || ag[1]<=16)$fatal(1,"dark recovery failed");
 controls_done=1;
end
initial begin
 repeat(4)@(negedge clk);rst=1;
 for(f=0;f<4;f=f+1)begin
  for(y=0;y<720;y=y+1)for(x=0;x<320;x=x+1)begin
   @(negedge clk);v=1;u=(x==0 && y==0);l=(x==319);
   p=(f<2)?24'h909090:((x<10)?24'hffffff:24'h181818);data={4{p}};
   if(u)begin @(posedge clk);#1;
    if(f==1 && (mean[0]!=72 || mean[1]!=96 || hs[0]!=0 || hs[1]!=0))$fatal(1,"plateau stats");
    if(f==3 && (mean[0]!=24 || mean[1]!=24 || hs[1]!=0))$fatal(1,"small reflection darkened centre");
   end
  end
  @(negedge clk);v=0;u=0;l=0;repeat(5)@(negedge clk);
 end
 wait(controls_done);
 $display("METER_V75_PASS true720p ceiling72_dead_branch ceiling96_bright_reduction dark_recovery 3percent_reflection_tolerated");$finish;
end
initial begin #20000000;$fatal(1,"timeout");end
endmodule
