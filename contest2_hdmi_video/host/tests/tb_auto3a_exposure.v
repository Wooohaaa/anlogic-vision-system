`timescale 1ns/1ps
module tb_auto3a_exposure;
reg clk=0; always #5 clk=~clk;
reg rst=0, cam_done=0, cfg_done=0, ft=0;
reg [7:0] luma=120;
wire req; wire [15:0] ae,ag; wire [3:0] level;
integer writes=0,busy=0,i; reg [15:0] held_ae,held_ag;
integer scene, gain_code, gain_q5, measured, s;
ua_auto_exposure #(.AUTO_START_WRITE(1),.AUTO_FAST(1),.AG_DEFAULT(16)) dut
 (.I_clk(clk),.I_rst_n(rst),.I_luma_mean(luma),.I_frame_toggle(ft),
 .I_cam_cfg_done(cam_done),.I_ae_cfg_done(cfg_done),.I_auto_enable(1'b1),.I_manual_inc(1'b1),
 .I_manual_dec(1'b0),.O_ae_req(req),.O_ae(ae),.O_ag(ag),.O_manual_level(level),.O_luma_dbg());
always @(posedge clk) if(rst && cam_done) begin
 if(req) begin
  if(busy || !cfg_done) $fatal(1,"request while busy");
  writes<=writes+1; held_ae<=ae;held_ag<=ag;busy<=12;cfg_done<=0;
 end else if(busy>0) begin
  if(ae!==held_ae || ag!==held_ag) $fatal(1,"torn sensor register pair");
  busy<=busy-1; if(busy==1) cfg_done<=1;
 end
 if(ae<2 || ae>1990 || ag<16 || ag>143) $fatal(1,"illegal range");
end
task frame; input [7:0] value; begin
 @(negedge clk);luma=value;ft=~ft;
 repeat(30) @(negedge clk);
end endtask
initial begin
 repeat(3) @(negedge clk);rst=1;
 repeat(20) @(negedge clk);
 if(req || writes) $fatal(1,"write before camera initialization");
 cam_done=1;cfg_done=1;repeat(40) @(negedge clk);
 if(writes!=1 || ae!=1990 || ag!=16) $fatal(1,"startup not programmed");
 for(i=0;i<20;i=i+1) frame(120);
 if(writes!=1) $fatal(1,"deadband/manual input changed auto state");
 frame(0); if(writes!=1) $fatal(1,"single frame changed exposure");
 frame(120);
 for(i=0;i<200;i=i+1) frame(0);
 if(ae!=1990 || ag!=143) $fatal(1,"dark convergence failed %d %d",ae,ag);
 for(i=0;i<450;i=i+1) frame(255);
 if(ae!=2 || ag!=16 || level!=0) $fatal(1,"bright convergence failed %d %d",ae,ag);
 for(i=0;i<500;i=i+1) frame(0);
 if(ae!=1990 || ag!=143 || level!=15) $fatal(1,"return dark failed");
 // Synthetic sensor response using the actual four SC500 gain bands.
 // This checks feedback convergence, not real sensor noise/colour quality.
 for(s=0;s<5;s=s+1) begin
  case(s) 0:scene=10;1:scene=30;2:scene=80;3:scene=220;4:scene=600;endcase
  for(i=0;i<250;i=i+1) begin
   gain_code=ag-16;gain_q5=(32+(gain_code%32)) << (gain_code/32);
   measured=(scene*ae*gain_q5)/(1990*32);
   if(measured>255) measured=255;
   frame(measured);
  end
  if(measured<96 || measured>144) $fatal(1,"closed loop not settled scene=%d mean=%d",scene,measured);
  $display("AUTO3A_CLOSED_LOOP scene=%0d mean=%0d ae=%0d ag=%0d",scene,measured,ae,ag);
 end
 $display("AUTO3A_EXPOSURE_PASS startup coherent_I2C deadband transient limits convergence writes=%0d",writes);
 $finish;
end
initial begin #4000000; $fatal(1,"timeout");end
endmodule
