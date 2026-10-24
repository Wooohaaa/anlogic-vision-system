`timescale 1ns/1ps
module tb_centre_window_v59;
 reg clk=0,rst=0;always #5 clk=~clk;
 reg ft[0:1];reg [7:0] ym[0:1];reg [1:0] hs[0:1];
 wire [15:0] ae[0:1],ag[0:1];wire req[0:1];reg done[0:1];integer busy[0:1];
 genvar k;
 generate for(k=0;k<2;k=k+1)begin:ctrl
 ua_auto_exposure #(.LUMA_LOW(48),.LUMA_HIGH(72),.AG_DEFAULT(16),.AUTO_START_WRITE(1),.AUTO_FAST(1),.HIGHLIGHT_PROTECT(1),.SUBJECT_FLOOR(40)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_luma_mean(ym[k]),.I_frame_toggle(ft[k]),.I_cam_cfg_done(1'b1),.I_ae_cfg_done(done[k]),.I_auto_enable(1'b1),.I_manual_inc(1'b0),.I_manual_dec(1'b0),.I_highlight(hs[k]),.O_ae_req(req[k]),.O_ae(ae[k]),.O_ag(ag[k]));
 always @(posedge clk)if(!rst)begin done[k]<=1;busy[k]<=0;end
 else if(req[k])begin done[k]<=0;busy[k]<=12;end
 else if(busy[k]>0)begin busy[k]<=busy[k]-1;if(busy[k]==1)done[k]<=1;end
 end endgenerate
 integer j,i,code,q,patch[0:1],back[0:1],rawpatch;
 initial begin
  for(i=0;i<2;i=i+1)begin ft[i]=0;ym[i]=0;hs[i]=0;end
  repeat(4)@(negedge clk);rst=1;repeat(40)@(negedge clk);
  for(j=0;j<500;j=j+1)begin
   @(negedge clk);
   for(i=0;i<2;i=i+1)begin
    code=ag[i]-16;q=(32+(code%32))<<(code/32);
    back[i]=(5*ae[i]*q)/(1990*32);rawpatch=(1000*ae[i]*q)/(1990*32);
    patch[i]=(rawpatch>255)?255:rawpatch;
    // Window occupies 3/8 of centre ROI, enough to dominate an ordinary mean.
    ym[i]=(i==0)?(3*patch[i]+5*back[i])/8:
        (3*((patch[i]>72)?72:patch[i])+5*((back[i]>72)?72:back[i]))/8;
    hs[i]=(rawpatch>=240)?3:(rawpatch>=224)?2:(rawpatch>=192)?1:0;ft[i]=~ft[i];
   end
   repeat(32)@(negedge clk);
   if(j>400 && (back[1]<20 || back[1]>50))$fatal(1,"unstable recovered background");
  end
  if(back[0]>=5 || back[1]<20)$fatal(1,"central glare still dominates old=%0d new=%0d",back[0],back[1]);
  $display("CENTRE_WINDOW_V59_PASS ordinary_mean_background=%0d winsorized_background=%0d bounded_last_100_frames",back[0],back[1]);$finish;
 end
endmodule
