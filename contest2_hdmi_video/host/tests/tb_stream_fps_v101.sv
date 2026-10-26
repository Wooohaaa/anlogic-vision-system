`timescale 1ns/1ps
module tb_stream_fps_v101;
 reg clk=0,rst=0,tick=0,toggle=0,sof=0,frame_end=0,underflow=0,valid=0;
 integer rows=0;
 reg [15:0] id=0;
 wire [7:0] inf,outf;wire sec;
 always #5 clk=~clk;
 ua_stream_fps dut(clk,rst,tick,toggle,sof,frame_end,underflow,valid,id,inf,outf,sec);
 task step;begin @(negedge clk);end endtask
 task input_frame;begin step;toggle=~toggle;repeat(5)step;end endtask
 task start_frame(input [15:0] n,input v);begin
  step;id=n;valid=v;sof=1;rows=0;step;sof=0;
 end endtask
 task row(input bad);begin
  step;underflow=bad;step;underflow=0;rows=rows+1;frame_end=(rows==3);
  step;frame_end=0;
 end endtask
 task frame(input [15:0] n,input v,input bad);begin
  start_frame(n,v);row(0);row(bad);row(0);
 end endtask
 task window(input [7:0] ei,input [7:0] eo);begin
  step;tick=1;repeat(1000)step;tick=0;
  if(inf!==ei || outf!==eo)$fatal(1,"rates expected %h/%h got %h/%h",ei,eo,inf,outf);
 end endtask
 initial begin
  #1;rst=1;#1;rst=0;repeat(3)step;rst=1;
  input_frame;frame(16'hffff,1,0);
  frame(16'hffff,1,0); // repeated DDR slot excluded
  frame(0,1,0); // timestamp wrap is a new frame
  frame(1,1,1); // underflow excludes output
  frame(1,1,0); // retry same source after bad frame succeeds
  frame(2,0,0); // invalid source
  start_frame(3,1);row(0); // interrupted frame
  frame(4,1,0);
  window(8'h01,8'h04);
  window(0,0); // no stale rate
  repeat(105)input_frame;
  repeat(105)begin frame(id+1,1,0);end
  window(8'h99,8'h99); // saturation, no 99->90 or wrap
  // Events on the exact second boundary belong to the ending window.
  step;tick=1;repeat(999)step;tick=0;
  toggle=~toggle;repeat(3)step;
  if(!dut.input_event)$fatal(1,"test alignment");tick=1;
  step;tick=0;
  if(inf!==1)$fatal(1,"boundary input dropped");
  step;rst=0;step;
  if(inf!==0 || outf!==0)$fatal(1,"reset");
  $display("STREAM_FPS_V101_PASS repeats invalid underrun interrupted wrap idle saturation boundary reset");$finish;
 end
endmodule
