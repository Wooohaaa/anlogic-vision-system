`timescale 1ns/1ps
module tb_latency_frames_v101;
 reg pc=0,cc=0,dc=0,rst=0,raw=0,ws=0,ww=0,rs=0,sof=0;
 reg [1:0] wslot=0,rslot=0;
 wire lv;wire [15:0] delay_ms;wire [7:0] inf,outf;wire sec;
 always #5 pc=~pc;always #7 cc=~cc;always #3 dc=~dc;
 ua_frame_latency #(.PIXEL_HZ(1000),.FRAME_WORDS(3),.FPS_ENABLE(1),.IMG_HEIGHT(2)) dut(
  .I_rst_n(rst),.I_camera_clk(cc),.I_raw_start(raw),.I_ddr_clk(dc),
  .I_write_start(ws),.I_write_slot(wslot),.I_write_word(ww),
  .I_read_start(rs),.I_read_slot(rslot),.I_pixel_clk(pc),.I_display_start(sof),
  .I_display_end(1'b0),.I_underflow(1'b0),
  .O_in_fps_bcd(inf),.O_out_fps_bcd(outf),.O_second_tick(sec),.O_valid(lv),.O_delay_ms(delay_ms));
 task capture;begin @(negedge cc);raw=1;@(negedge cc);raw=0;repeat(10)@(negedge dc);end endtask
 task write_start;begin @(negedge dc);ws=1;@(negedge dc);ws=0;end endtask
 task word;begin @(negedge dc);ww=1;@(negedge dc);ww=0;end endtask
 task read_slot(input expect_valid);begin
  @(negedge dc);rs=1;@(negedge dc);rs=0;repeat(10)@(negedge pc);
  sof=1;@(negedge pc);sof=0;
  if(lv!==expect_valid)$fatal(1,"slot valid expected %b got %b",expect_valid,lv);
 end endtask
 initial begin
  #1;rst=1;#1;rst=0;repeat(3)@(negedge pc);rst=1;
  read_slot(0);
  capture;write_start;word;word;read_slot(0); // partial never counted
  word;read_slot(1);
  repeat(5)word; // extra writes never double count
  repeat(8)@(negedge pc);
  if(dut.gen_fps.meter.input_window!==8'h01)$fatal(1,"complete count");
  capture;write_start;word; // overwrite invalidates previous slot
  read_slot(0);
  capture;wslot=1;write_start;word;word;word;rslot=1;read_slot(1);
  repeat(8)@(negedge pc);
  if(dut.gen_fps.meter.input_window!==8'h02)$fatal(1,"partial incorrectly counted");
  @(negedge pc);rst=0;@(negedge pc);
  if(lv || inf || outf)$fatal(1,"reset");
  $display("LATENCY_FRAMES_V101_PASS asynchronous complete partial overwrite extra_words reset");$finish;
 end
endmodule
