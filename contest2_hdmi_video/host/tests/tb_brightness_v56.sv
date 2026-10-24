`timescale 1ns/1ps
module tb_brightness_v56;
 reg clk=0,src=0,rst=0,en=1,ft=0,done=1;
 always #5 clk=~clk;always #21 src=~src;
 reg [7:0] luma=120;
 reg key=0;wire key_enable;
 ua_button_toggle_embedded key4(.I_clk(clk),.I_rst_n(rst),.I_button(key),.O_enable(key_enable));
 wire req;wire [15:0] ae,ag;wire [4:0] idx;
 integer busy=0,writes=0,i,j;reg [15:0] ha,hg;
 ua_auto_exposure #(.AUTO_START_WRITE(1),.AUTO_FAST(1),.RESTORE_ON_DISABLE(1),.AG_DEFAULT(16)) ae_dut(
 .I_clk(src),.I_rst_n(rst),.I_luma_mean(luma),.I_frame_toggle(ft),
 .I_cam_cfg_done(1'b1),.I_ae_cfg_done(done),.I_auto_enable(en),
 .I_manual_inc(1'b0),.I_manual_dec(1'b0),.O_ae_req(req),.O_ae(ae),.O_ag(ag),.O_gain_index(idx));
 always @(posedge src)if(rst)begin
  if(req)begin
   if(busy || !done)$fatal(1,"busy request");
   busy<=12;done<=0;ha<=ae;hg<=ag;writes<=writes+1;
  end else if(busy)begin
   if(ae!==ha || ag!==hg)$fatal(1,"torn sensor pair");
   busy<=busy-1;if(busy==1)done<=1;
  end
 end
 task frame(input [7:0] y);
 begin @(negedge src);luma=y;ft=~ft;repeat(32)@(negedge src);end endtask
 reg [4:0] panel_index=0;reg panel_en=0;
 wire [5:0] sel;wire [7:0] led;
 ua_ae_panel_embedded #(.SCAN_CYCLES(8)) panel(
 .I_clk(clk),.I_source_clk(src),.I_rst_n(rst),.I_index(panel_index),.I_enable(panel_en),.O_seg_sel(sel),.O_seg_led(led));
 integer d,seen=0;reg [3:0] v;
 always @(posedge clk)begin #1;
  if(rst && sel!=63)begin
   if(((~sel&63)&((~sel&63)-1))!=0)$fatal(1,"multi select");
   for(d=0;d<6;d=d+1)if(!sel[d])begin
    seen=seen|(1<<d);v=15;
    case(d)0:v=panel.tens;1:v=panel.units;5:v={3'd0,panel.scan[5]};endcase
    if(led!==panel.seg(v))$fatal(1,"scan mapping");
   end
  end
 end
 wire [95:0] rgb;wire ov;
 reg iv=0,sof=0,last=0;reg [1:0] strength=0;
 reg [107:0] data={12{9'd32}};
 ua_photo_finish_96 #(.IMG_WIDTH(16),.INPUT_BITS(9),.RUNTIME_STRENGTH(1)) photo(
 .I_clk(clk),.I_rst_n(rst),.I_tvalid(iv),.I_tuser(sof),.I_tlast(last),.I_tdata(data),.I_strength(strength),.O_tdata(rgb),.O_tvalid(ov));
 integer outputs=0;reg [7:0] expected=0;integer base,room;
 always @(posedge clk)begin #1;if(ov)begin
  outputs=outputs+1;
  if(rgb!=={12{expected}})$fatal(1,"live curve mismatch actual=%h expected=%h",rgb,expected);
 end end
 initial begin
  repeat(4)@(negedge clk);rst=1;
  repeat(2)@(negedge clk);if(!key_enable)$fatal(1,"KEY4 default off");
  key=1;repeat(12)@(negedge clk);if(key_enable)$fatal(1,"KEY4 first press");
  key=0;repeat(4)@(negedge clk);key=1;repeat(12)@(negedge clk);
  if(!key_enable)$fatal(1,"KEY4 second press");key=0;
  repeat(80)@(negedge src);
  for(i=0;i<200;i=i+1)frame(0);
  if(ae!=1990 || ag!=143 || idx!=31)$fatal(1,"dark/index convergence");
  // Disable while I2C is in flight: restore only after coherent completion.
  en=0;repeat(120)@(negedge src);
  if(ae!=1990 || ag!=16 || idx!=15)$fatal(1,"disable must restore baseline");
  for(i=0;i<20;i=i+1)frame(0);
  if(ag!=16)$fatal(1,"disabled feedback still adjusts");
  en=1;for(i=0;i<200;i=i+1)frame(0);
  if(idx!=31)$fatal(1,"reenable failed");
  for(i=0;i<450;i=i+1)frame(255);
  if(idx!=0 || ae!=2 || ag!=16)$fatal(1,"bright convergence");
  en=0;repeat(120)@(negedge src);
  if(ae!=1990 || ag!=16)$fatal(1,"restore after bright scene");
  for(i=0;i<64;i=i+1)begin
   @(negedge src);panel_index=i%32;panel_en=i/32;
   repeat(220)@(negedge clk);
   if(panel.scan!=={panel_en,panel_index})$fatal(1,"panel stale or torn");
  end
  if(seen!=63)$fatal(1,"missing scan slots");
  // Exhaust all LUT inputs: no inverted steps/clipping, no pedestal.
  for(j=0;j<3;j=j+1)for(i=0;i<512;i=i+1)begin
   base=photo.tone(i,0);room=(base<128)?base:255-base;
   if(photo.gen_tone_rom.bank_pair[0].lut[j*512+i]!==base+((j==0)?0:(j==1)?room/4:room/2))$fatal(1,"ROM curve");
   if(i && photo.gen_tone_rom.bank_pair[0].lut[j*512+i]<photo.gen_tone_rom.bank_pair[0].lut[j*512+i-1])$fatal(1,"nonmonotonic curve");
  end
  for(j=0;j<3;j=j+1)begin
   strength=j;base=photo.tone(32,0);room=(base<128)?base:255-base;
   expected=base+((j==0)?0:(j==1)?room/4:room/2);
   for(i=0;i<16;i=i+1)begin
    @(negedge clk);iv=1;sof=(i==0);last=(i%4==3);
   end
   @(negedge clk);iv=0;sof=0;last=0;repeat(20)@(negedge clk);
  end
  if(outputs!=48)$fatal(1,"pixel count");
  $display("BRIGHTNESS_V56_PASS dark_bright_restore_resume coherent_index_00_31_enable_0_1 live_three_curves no_added_latency");$finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
