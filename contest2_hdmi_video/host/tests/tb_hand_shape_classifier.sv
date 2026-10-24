`timescale 1ns/1ps
module tb_hand_shape_classifier;
parameter WATCHDOG=16000000,PARALLEL_COMPARE=0,EXTERNAL_SCRATCH=0;
reg clk=0;always #5 clk=~clk;
reg rst=0,clear=0,start=0,mode=0,rv=0;reg[17:0]rd;
reg[7:0]xmin,width,anchor_x;reg[6:0]ymin,height,anchor_y;
wire ready,read,busy,done,fault;wire[11:0]ra;wire[1:0]raw;wire[2:0]tips;
wire[7:0]cx;wire[6:0]cy;wire[10:0]radius;wire[13:0]area;wire[31:0]cycles;
reg sr=0,sw=0;reg[13:0]sa=0;reg[15:0]sd=0;wire sready,sv;wire[15:0]sq;
// Deliberately attempt writes while busy: these must never reach geometry.
wire attempted_write=sw || (EXTERNAL_SCRATCH && busy);
ua_hand_shape_classifier #(.MAX_CYCLES(WATCHDOG),.PARALLEL_COMPARE(PARALLEL_COMPARE),.EXTERNAL_SCRATCH(EXTERNAL_SCRATCH)) dut(
 clk,rst,clear,start,mode,xmin,width,anchor_x,ymin,height,anchor_y,ready,read,ra,rv,rd,
 busy,done,fault,raw,tips,cx,cy,radius,area,cycles,sr,attempted_write,sa,sd,sready,sv,sq);
reg[17:0]source[0:2429];reg[2047:0]mp;
reg[15:0]rng=16'h9843;
integer pending=0,address=0,delay_cycles=0,ticks=0;
integer x,y,w,h,ax,ay,md,expected_raw,expected_tips,expected_cx,expected_cy,expected_radius,expected_area,abort_stage=0,expected_fault=0;
integer si;
always @(posedge clk)begin
 rng<={rng[14:0],rng[15]^rng[13]^rng[12]^rng[10]};ticks=ticks+1;rv<=0;
 if(ticks>5000000)$fatal(1,"timeout state=%0d geo=%0d cand=%0d filter=%0d",dut.state,dut.geometry.state,dut.candidates.state,dut.filter.state);
 if(read)begin
  if(pending || ra>=2430)$fatal(1,"read overlap/bounds");
  pending=1;address=ra;delay_cycles=1+rng[2:0];
 end
 if(pending)begin
  if(!delay_cycles)begin pending=0;rv<=1;rd<=source[address];end
  else delay_cycles=delay_cycles-1;
 end
 if(dut.geometry.geometry.scratch_read && dut.geometry.geometry.scratch_write)$fatal(1,"scratch collision");
 if(busy && sready)$fatal(1,"external scratch granted during classification");
end
task launch;
begin
 while(!ready)@(negedge clk);
 xmin=x;ymin=y;width=w;height=h;anchor_x=ax;anchor_y=ay;mode=md;
 start=1;@(negedge clk);start=0;
 // Transaction context must be latched, not sampled one cycle too late.
 xmin=0;ymin=0;width=0;height=0;anchor_x=0;anchor_y=0;mode=!md;
end endtask
initial begin
 if(!$value$plusargs("MASK=%s",mp)||!$value$plusargs("X=%d",x)||!$value$plusargs("Y=%d",y)||
 !$value$plusargs("W=%d",w)||!$value$plusargs("H=%d",h)||!$value$plusargs("AX=%d",ax)||
 !$value$plusargs("AY=%d",ay)||!$value$plusargs("MODE=%d",md)||!$value$plusargs("RAW=%d",expected_raw)||
 !$value$plusargs("TIPS=%d",expected_tips)||!$value$plusargs("CX=%d",expected_cx)||
 !$value$plusargs("CY=%d",expected_cy)||!$value$plusargs("R=%d",expected_radius)||!$value$plusargs("AREA=%d",expected_area))$fatal(1,"args");
 if($value$plusargs("ABORT=%d",abort_stage))begin end
 if($value$plusargs("FAULT=%d",expected_fault))begin end
 $readmemh(mp,source,0,2429);repeat(5)@(negedge clk);rst=1;
 if(EXTERNAL_SCRATCH)begin
  // A full native-red frame occupies precisely the existing geometry RAM.
  for(si=0;si<14400;si=si+1)begin
   sa=si;sd=(si*37)^16'h5a39;sw=1;#1;
   if(!sready || ready)$fatal(1,"scratch write/start ownership %0d",si);
   @(negedge clk);
  end
  sw=0;
  for(si=0;si<14400;si=si+1)begin
   sa=si;sr=1;#1;if(!sready || ready)$fatal(1,"scratch read ownership");
   @(negedge clk);sr=0;
   if(!sv || sq!==(((si*37)^16'h5a39)&16'hffff))$fatal(1,"scratch readback %0d data=%h",si,sq);
   if(ready)$fatal(1,"start accepted with response pending");
   @(negedge clk);if(sv)$fatal(1,"scratch valid not pulse");
  end
  sa=14400;sw=1;#1;if(sready)$fatal(1,"out of bounds grant");
  @(negedge clk);sa=0;sr=1;#1;if(sready)$fatal(1,"simultaneous read/write grant");
  @(negedge clk);sw=0;sr=1;#1;if(!sready)$fatal(1,"read before clear not ready");
  @(negedge clk);sr=0;clear=1;#1;if(sv || sready)$fatal(1,"clear leaked response");
  @(negedge clk);clear=0;@(negedge clk);if(sv)$fatal(1,"stale response after clear");
 end
 if(abort_stage)begin
  launch();
  case(abort_stage)
  1:while(!pending)@(negedge clk);
  2:while(dut.geometry.state!=4 || !pending)@(negedge clk);
  3:while(dut.candidates.state!=15)@(negedge clk);
  4:while(!dut.probe_pending)@(negedge clk);
  endcase
  clear=1;@(negedge clk);clear=0;
  if(busy || done || read)$fatal(1,"clear incomplete");
 end
 launch();while(!done)@(negedge clk);
 if(fault!==(expected_fault!=0) || (!expected_fault && (raw!=expected_raw || tips!=expected_tips ||
   cx!=expected_cx || cy!=expected_cy || radius!=expected_radius || area!=expected_area)))
  $fatal(1,"fault=%0d raw=%0d/%0d tips=%0d/%0d palm=%0d,%0d,%0d/%0d,%0d,%0d area=%0d/%0d",
   fault,raw,expected_raw,tips,expected_tips,cx,cy,radius,expected_cx,expected_cy,expected_radius,area,expected_area);
 @(negedge clk);if(done)$fatal(1,"done not pulse");
 $display("HAND_SHAPE_CLASSIFIER_PASS cycles=%0d raw=%0d tips=%0d fault=%0d",cycles,raw,tips,fault);$finish;
end
endmodule
