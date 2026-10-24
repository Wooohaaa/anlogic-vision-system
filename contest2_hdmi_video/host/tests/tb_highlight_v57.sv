`timescale 1ns/1ps
module tb_highlight_v57;
 reg clk=0,rst=0,valid=0,user=0,last=0;always #5 clk=~clk;
 reg [95:0] data=0;wire [7:0] mean;wire toggle;wire [1:0] highlight;
 ua_luma_stats #(.HIGHLIGHT_ENABLE(1)) stats(.I_clk(clk),.I_rst_n(rst),.I_tlast(last),.I_tuser(user),.I_tdata(data),.I_tvalid(valid),.O_luma_mean(mean),.O_frame_toggle(toggle),.O_highlight(highlight));
 integer f,y,x,g,sample_row,n;reg [23:0] pixel;
 task check_previous(input integer frame_id);
 begin
  if(frame_id==0 && (highlight!=0 || mean!=0))$fatal(1,"black statistics");
  if(frame_id==1 && (highlight!=3 || mean!=0))$fatal(1,"offcentre highlight invisible %d %d",highlight,mean);
  if(frame_id==2 && highlight!=0)$fatal(1,"single specular must not drive exposure");
  if(frame_id==3 && highlight!=2)$fatal(1,"eight red hot samples %d",highlight);
  if(frame_id==4 && highlight!=1)$fatal(1,"sixteen green warm samples %d",highlight);
  if(frame_id==5 && (highlight!=3 || mean!=255))$fatal(1,"counter saturation/white frame");
 end endtask
 initial begin
  repeat(4)@(negedge clk);rst=1;
  for(f=0;f<7;f=f+1)begin
   for(y=0;y<720;y=y+1)for(x=0;x<320;x=x+1)begin
    @(negedge clk);valid=1;user=(x==0 && y==0);last=(x==319);pixel=0;
    sample_row=(y>=11 && ((y-11)%22)==0)?(y-11)/22:-1;
    if(x==5 && sample_row>=0 && sample_row<32)begin
     if(f==1)pixel=24'hfafafa;
     if(f==2 && sample_row==0)pixel=24'hffffff;
     if(f==3 && sample_row<8)pixel=24'he10000;
     if(f==4 && sample_row<16)pixel=24'h00c800;
    end
    if(f==5)pixel=24'hffffff;
    data={4{pixel}};
    if(user)begin @(posedge clk);#1;if(f>0)check_previous(f-1);end
    if(x==121)begin @(negedge clk);valid=0;user=0;last=0;end
   end
   @(negedge clk);valid=0;user=0;last=0;
   if(stats.sample_count!=1024 || stats.global_count!=1024)$fatal(1,"sample count centre=%d global=%d",stats.sample_count,stats.global_count);
  end
  wait(loop_done);
  $display("HIGHLIGHT_V57_PASS 1024_global_samples centre_dark_offcentre_white colour_channel_guard specular_ignore saturation hold_gain closed_loop");$finish;
 end

 reg ft=0;reg [7:0] ymean=0;reg [1:0] hs=0;
 wire [15:0] ae[0:1],ag[0:1];wire req[0:1];reg done[0:1];integer busy[0:1];
 genvar k;
 generate for(k=0;k<2;k=k+1)begin:controller
 ua_auto_exposure #(.LUMA_LOW(48),.LUMA_HIGH(72),.AG_DEFAULT(16),.AUTO_START_WRITE(1),.AUTO_FAST(1),.HIGHLIGHT_PROTECT(k)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_luma_mean(ymean),.I_frame_toggle(ft),.I_cam_cfg_done(1'b1),.I_ae_cfg_done(done[k]),.I_auto_enable(1'b1),.I_manual_inc(1'b0),.I_manual_dec(1'b0),.I_highlight(hs),.O_ae_req(req[k]),.O_ae(ae[k]),.O_ag(ag[k]));
 always @(posedge clk)if(!rst)begin done[k]<=1;busy[k]<=0;end
 else if(req[k])begin done[k]<=0;busy[k]<=12;end
 else if(busy[k]>0)begin busy[k]<=busy[k]-1;if(busy[k]==1)done[k]<=1;end
 end endgenerate
 reg loop_done=0;integer frame_i,code,gain_q5,high,protected_high,old_high,held;
 initial begin
  wait(rst);repeat(40)@(negedge clk);
  // Old and new controllers see their own sensor responses. Central shadows
  // remain below target, while an off-centre diffuse patch needs protection.
  for(frame_i=0;frame_i<500;frame_i=frame_i+1)begin
   @(negedge clk);
   code=ag[1]-16;gain_q5=(32+(code%32))<<(code/32);
   high=(90*ae[1]*gain_q5)/(1990*32);
   ymean=(ae[1]*gain_q5)/(1990*32);
   hs=(high>=240)?3:(high>=224)?2:(high>=192)?1:0;ft=~ft;
   repeat(32)@(negedge clk);
  end
  code=ag[1]-16;gain_q5=(32+(code%32))<<(code/32);protected_high=(90*ae[1]*gain_q5)/(1990*32);
  code=ag[0]-16;gain_q5=(32+(code%32))<<(code/32);old_high=(90*ae[0]*gain_q5)/(1990*32);
  if(protected_high>=224 || protected_high<170 || old_high<255 || ag[1]>=ag[0])$fatal(1,"highlight model old=%d new=%d old_ag=%d new_ag=%d",old_high,protected_high,ag[0],ag[1]);
  $display("HIGHLIGHT_CLOSED_LOOP old_unclamped_patch=%0d protected_patch=%0d old_ag=%0d protected_ag=%0d",old_high,protected_high,ag[0],ag[1]);
  // Recover from already clipped maximum gain even with a dark mean.
  force controller[1].dut.O_ag=16'd143;repeat(2)@(negedge clk);release controller[1].dut.O_ag;
  for(frame_i=0;frame_i<200;frame_i=frame_i+1)begin
   @(negedge clk);hs=3;ymean=1;ft=~ft;repeat(32)@(negedge clk);
  end
  if(ag[1]!=16 || ae[1]>=1990)$fatal(1,"highlights did not override dark mean");
  held=ag[1];
  for(frame_i=0;frame_i<40;frame_i=frame_i+1)begin
   @(negedge clk);hs=1;ft=~ft;repeat(32)@(negedge clk);
  end
  if(ag[1]!=held)$fatal(1,"warning allowed gain increase");
  loop_done=1;
 end
 initial begin #30000000;$fatal(1,"timeout");end
endmodule
