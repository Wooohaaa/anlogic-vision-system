`timescale 1ns/1ps
module tb_hand_geometry_shared;
 parameter WATCHDOG=4000000,SHARED=1;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,clear=0,start=0,mode=1,rv=0;reg[17:0]rd;
 reg[7:0]bx,bw,ax;reg[6:0]by,bh,ay;
 wire ready,read,busy,done,fault,has;wire[11:0]ra;wire[7:0]cx,vx;wire[6:0]cy,vy;
 wire[10:0]radius;wire[13:0]area,lower;wire signed[9:0]wdx,wdy;
 wire vv,vl;wire[8:0]vc;wire[31:0]cycles;
 reg[15:0]rng=16'h8129;reg force_stall=0;wire vr=rng[2:0]!=0 && !force_stall;
 wire unused_extra_ready,unused_probe_ready,unused_probe_valid,unused_probe_pixel;wire[15:0]unused_extra_data;
 ua_hand_geometry_shared #(.MAX_CYCLES(WATCHDOG),.SHARED_MEMORY(SHARED)) dut(clk,rst,clear,start,mode,bx,bw,ax,by,bh,ay,
 ready,read,ra,rv,rd,busy,done,fault,has,cx,cy,radius,area,lower,wdx,wdy,vv,vr,vx,vy,vl,vc,cycles,
 1'b0,1'b0,14'd0,16'd0,unused_extra_ready,unused_extra_data,1'b0,8'd0,7'd0,
 unused_probe_ready,unused_probe_valid,unused_probe_pixel);
 reg[17:0]source[0:2429];reg[15:0]expected[0:14399];reg[14:0]hull[0:321];
 reg[2047:0]mp,ep,hp;
 integer x,y,w,h,anchor_x,anchor_y,ex,ey,er,ea,el,edx,edy,eh,mode_arg;
 integer expected_fault=0,abort_stage=0,n,i,outputs=0,pixels=0,ticks=0,checking=0;
 integer pending=0,pending_address=0,response_delay=0,aborted=0;
 reg held=0;reg[15:0]held_vertex;
 always @(posedge clk)begin
  rng<={rng[14:0],rng[15]^rng[13]^rng[12]^rng[10]};rv<=0;ticks=ticks+1;
  if(ticks>5000000)$fatal(1,"test timeout");
  if(read)begin
   if(pending || ra>=2430)$fatal(1,"source request overlap or bounds");
   pending=1;pending_address=ra;
   response_delay=abort_stage==1 && !aborted ? 60 : 1+rng[1:0];
  end
  if(pending)begin
   if(response_delay==0)begin rv<=1;rd<=source[pending_address];pending=0;end
   else response_delay=response_delay-1;
  end
  if(dut.scratch_read && dut.scratch_write)$fatal(1,"scratch dual operation");
  if((dut.scratch_read||dut.scratch_write) && dut.scratch_address>=14400)$fatal(1,"scratch bounds");
  if((dut.cr||dut.cw) && (dut.pr||dut.pw) || (dut.cr||dut.cw) && (dut.hr||dut.hw) ||
     (dut.pr||dut.pw) && (dut.hr||dut.hw))$fatal(1,"scratch ownership overlap");
  if(checking)begin
   if(held && (!vv || {vl,vy,vx}!==held_vertex))$fatal(1,"unstable shared hull output");
   held=vv && !vr;held_vertex={vl,vy,vx};
   if(vv && vr)begin
    if(outputs>=eh || {vy,vx}!==hull[outputs] || vl!==(outputs==eh-1))$fatal(1,"hull mismatch %0d",outputs);
    outputs=outputs+1;
   end
   if(dut.replay_valid && dut.wrist_ready && dut.hull_ready)begin
    i=dut.replay_y*w+dut.replay_x;
    if(i!=pixels || dut.held_pixel!==expected[i][11])$fatal(1,"selected mask replay mismatch %0d",pixels);
    pixels=pixels+1;
   end
  end else held=0;
 end
 task launch;
 begin while(!ready)@(negedge clk);start=1;@(negedge clk);start=0;end endtask
 task abort_and_drain;
 begin
  @(negedge clk);checking=0;clear=1;@(negedge clk);clear=0;aborted=1;
  if(busy || done || vv)$fatal(1,"clear incomplete");
  if(abort_stage==1)begin
   if(ready)$fatal(1,"accepted new start with stale response pending");
   start=1;repeat(3)@(negedge clk);start=0;
   if(busy || read)$fatal(1,"stale source drain did not block new launch");
  end
  while(!ready)begin @(negedge clk);if(done)$fatal(1,"late completion after abort");end
  outputs=0;pixels=0;force_stall=0;
 end endtask
 initial begin
  if(!$value$plusargs("MASK=%s",mp)||!$value$plusargs("EXPECTED=%s",ep)||!$value$plusargs("HULL=%s",hp)||
     !$value$plusargs("X=%d",x)||!$value$plusargs("Y=%d",y)||!$value$plusargs("W=%d",w)||!$value$plusargs("H=%d",h)||
     !$value$plusargs("AX=%d",anchor_x)||!$value$plusargs("AY=%d",anchor_y)||!$value$plusargs("MODE=%d",mode_arg)||
     !$value$plusargs("CX=%d",ex)||!$value$plusargs("CY=%d",ey)||!$value$plusargs("R=%d",er)||
     !$value$plusargs("AREA=%d",ea)||!$value$plusargs("LOWER=%d",el)||!$value$plusargs("DX=%d",edx)||
     !$value$plusargs("DY=%d",edy)||!$value$plusargs("HC=%d",eh))$fatal(1,"arguments");
  if($value$plusargs("FAULT=%d",expected_fault))begin end
  if($value$plusargs("ABORT=%d",abort_stage))begin end
  n=w*h;bx=x;by=y;bw=w;bh=h;ax=anchor_x;ay=anchor_y;mode=mode_arg;
  $readmemh(mp,source,0,2429);$readmemh(ep,expected,0,n-1);
  if(eh)$readmemh(hp,hull,0,eh-1);
  repeat(5)@(negedge clk);rst=1;
  if(abort_stage)begin
   launch();
   case(abort_stage)
    1:while(!pending || response_delay<20)@(negedge clk);
    2:while(dut.state!=3 || dut.palm_core.state!=4)@(negedge clk);
    3:while(dut.state!=7)@(negedge clk);
    4:begin force_stall=1;while(!vv)@(negedge clk);end
   endcase
   abort_and_drain();
  end
  checking=!expected_fault;launch();while(!done)@(negedge clk);
  if(expected_fault)begin if(!fault)$fatal(1,"missing fault");end
  else if(fault || area!=ea || lower!=el || cx!=ex || cy!=ey || radius!=er ||
          wdx!=edx || wdy!=edy || outputs!=eh || vc!=eh || pixels!=n || has!==(er>=80))
   $fatal(1,"geometry fault=%0d area=%0d/%0d lower=%0d/%0d palm=%0d,%0d r=%0d expected=%0d,%0d r=%0d wrist=%0d,%0d/%0d,%0d vertices=%0d/%0d pixels=%0d/%0d",fault,area,ea,lower,el,cx,cy,radius,ex,ey,er,wdx,wdy,edx,edy,outputs,eh,pixels,n);
  $display("HAND_GEOMETRY_SHARED_PASS cycles=%0d vertices=%0d fault=%0d",cycles,outputs,fault);$finish;
 end
endmodule
