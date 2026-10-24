`timescale 1ns/1ps
module tb_reflection_v58;
 reg clk=0,rst=0,v=0,u=0,l=0;always #5 clk=~clk;
 reg [95:0] data=0;wire [7:0] mean;wire [1:0] hs;wire toggle;
 ua_luma_stats #(.HIGHLIGHT_ENABLE(1),.REFLECTION_TOLERANT(1)) stats(
 .I_clk(clk),.I_rst_n(rst),.I_tvalid(v),.I_tuser(u),.I_tlast(l),.I_tdata(data),.O_luma_mean(mean),.O_highlight(hs),.O_frame_toggle(toggle));
 integer f,x,y,n,row,col,limit,expect_h;reg [23:0] p;
 task check(input integer prior);
 begin
  case(prior)0,1,2:expect_h=0;3,5:expect_h=2;4,8:expect_h=3;6,7:expect_h=1;default:expect_h=0;endcase
  if(hs!==expect_h[1:0])$fatal(1,"area threshold case=%0d got=%0d expected=%0d",prior,hs,expect_h);
  if(prior<8 && mean!=0)$fatal(1,"offcentre patch changed centre fixture");
  if(prior==8 && mean!=255)$fatal(1,"full white mean");
 end endtask
 initial begin
  repeat(4)@(negedge clk);rst=1;
  for(f=0;f<10;f=f+1)begin
   case(f)0:limit=0;1:limit=32;2:limit=63;3:limit=64;4:limit=128;5:limit=96;6:limit=64;7:limit=128;default:limit=0;endcase
   for(y=0;y<720;y=y+1)for(x=0;x<320;x=x+1)begin
    @(negedge clk);v=1;u=(x==0 && y==0);l=(x==319);p=0;
    row=(y>=11 && ((y-11)%22)==0)?(y-11)/22:-1;
    col=(x>=5 && ((x-5)%10)==0)?(x-5)/10:-1;
    if(row>=0 && row<32 && col>=0 && col<4 && row*4+col<limit)
     p=(f==5 || f==6)?24'he10000:(f==7)?24'h00c800:24'hffffff;
    if(f==8)p=24'hffffff;data={4{p}};
    if(u)begin @(posedge clk);#1;if(f>0)check(f-1);end
    if(x==121)begin @(negedge clk);v=0;u=0;l=0;end
   end
   @(negedge clk);v=0;u=0;l=0;
   if(stats.global_count!=1024 || stats.sample_count!=1024)$fatal(1,"coverage");
  end
  wait(loop_done);
  $display("REFLECTION_V58_PASS 0_32_63_64_96_128_1024_samples small_reflection_allowed centre_floor bright_area_guard");$finish;
 end

 reg crst=0;reg ft[0:1];reg [7:0] ym[0:1];reg [1:0] h[0:1];
 wire [15:0] ae[0:1],ag[0:1];wire req[0:1];reg done[0:1];integer busy[0:1];
 genvar k;
 generate for(k=0;k<2;k=k+1)begin:ctrl
 ua_auto_exposure #(.LUMA_LOW(48),.LUMA_HIGH(72),.AG_DEFAULT(16),.AUTO_START_WRITE(1),.AUTO_FAST(1),.HIGHLIGHT_PROTECT(1),.SUBJECT_FLOOR(k?40:0)) dut(
 .I_clk(clk),.I_rst_n(crst),.I_luma_mean(ym[k]),.I_frame_toggle(ft[k]),.I_cam_cfg_done(1'b1),.I_ae_cfg_done(done[k]),.I_auto_enable(1'b1),.I_manual_inc(1'b0),.I_manual_dec(1'b0),.I_highlight(h[k]),.O_ae_req(req[k]),.O_ae(ae[k]),.O_ag(ag[k]));
 always @(posedge clk)if(!crst)begin done[k]<=1;busy[k]<=0;end
 else if(req[k])begin done[k]<=0;busy[k]<=12;end
 else if(busy[k]>0)begin busy[k]<=busy[k]-1;if(busy[k]==1)done[k]<=1;end
 end endgenerate
 reg loop_done=0;integer phase,j,i,code,gain_q5,back[0:1],patch,count;
 initial begin
  ft[0]=0;ft[1]=0;ym[0]=0;ym[1]=0;h[0]=0;h[1]=0;
  wait(rst);
  for(phase=0;phase<2;phase=phase+1)begin
   crst=0;repeat(4)@(negedge clk);crst=1;repeat(40)@(negedge clk);
   count=(phase==0)?32:256; // 3.125% reflection, then 25% bright window.
   for(j=0;j<500;j=j+1)begin
    @(negedge clk);
    for(i=0;i<2;i=i+1)begin
     code=ag[i]-16;gain_q5=(32+(code%32))<<(code/32);
     back[i]=(5*ae[i]*gain_q5)/(1990*32);
     patch=(1000*ae[i]*gain_q5)/(1990*32);
     ym[i]=(back[i]>255)?255:back[i];
     if(i==0)h[i]=(patch>=240 && count>=8)?3:(patch>=224 && count>=8)?2:(patch>=192 && count>=16)?1:0;
     else h[i]=(patch>=240 && count>=128)?3:(patch>=240 && count>=64)?2:(patch>=224 && count>=64)?1:0;
     ft[i]=~ft[i];
    end
    repeat(32)@(negedge clk);
   end
   if(back[0]>=20 || back[1]<40 || back[1]>72)$fatal(1,"subject floor phase=%0d old=%0d new=%0d",phase,back[0],back[1]);
   $display("REFLECTION_LOOP phase=%0d old_centre=%0d new_centre=%0d",phase,back[0],back[1]);
  end
  // Broad highlights with a bright centre still lower exposure.
  for(j=0;j<100;j=j+1)begin
   @(negedge clk);ym[1]=100;h[1]=3;ft[1]=~ft[1];repeat(32)@(negedge clk);
  end
  if(ag[1]!=16 || ae[1]>=1990)$fatal(1,"floor disabled broad highlight protection");
  loop_done=1;
 end
 initial begin #40000000;$fatal(1,"timeout");end
endmodule
