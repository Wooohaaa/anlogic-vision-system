`timescale 1ns/1ps
module tb_motion_mailbox_v92;
 reg sclk=0,dclk=0,srst=0,drst=0,valid=0;reg [52:0] data=0;
 always #5 sclk=~sclk;
 always #7 dclk=~dclk;
 wire ov;wire [52:0] od;
 ua_motion_mailbox dut(sclk,srst,valid,data,dclk,drst,ov,od);
 reg [52:0] expected;integer i,seen=0;
 always @(posedge dclk)begin #1;if(ov)begin
  if(od!==expected)$fatal(1,"torn mailbox got=%h want=%h",od,expected);
  seen=seen+1;
 end end
 initial begin
  repeat(5)@(negedge sclk);srst=1;drst=1;
  for(i=0;i<100;i=i+1)begin
   @(negedge sclk);expected={i[10:0],i[10:0],i[10:0],i[10:0],i[8:0]};data=expected;valid=1;
   @(negedge sclk);valid=0;
   // Input may change after submission: held source data must not.
   data=~expected;repeat(20)@(negedge sclk);
  end
  if(seen!=100)$fatal(1,"lost result %0d",seen);
  $display("MOTION_MAILBOX_V92_PASS coherent_packets=%0d",seen);$finish;
 end
endmodule
