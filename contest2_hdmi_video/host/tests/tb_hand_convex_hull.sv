`timescale 1ns/1ps
module tb_hand_convex_hull;
 parameter EXTERNAL=0;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,clear=0,start=0,valid=0,pixel=0,last=0;
 reg[7:0]width;reg[6:0]height;
 wire ready,busy,done,fault,vv,vl;wire[7:0]vx;wire[6:0]vy;wire[8:0]count;
 reg[15:0]rng=16'h5839;wire vr=rng[2:0]!=0;
 wire sr,sw;wire[13:0]sa;wire[15:0]sd,sq;
 ua_hand_scratch_ram storage(clk,sr,sw,sa,sd,sq);
 ua_hand_convex_hull #(.EXTERNAL_MEMORY(EXTERNAL)) dut(clk,rst,clear,start,width,height,valid,pixel,last,
  ready,busy,done,fault,vv,vr,vx,vy,vl,count,sr,sw,sa,sd,sq);
 reg mask[0:14399];reg[14:0]expected[0:321];
 reg[2047:0]path,expected_path;
 integer w,h,n,en,i,outputs=0,cycles=0,checking=0,abort_stage=0,expected_fault=0;
 reg held=0;reg[15:0]held_payload;
 always @(posedge clk)begin
  rng<={rng[14:0],rng[15]^rng[13]^rng[12]^rng[10]};cycles=cycles+1;
  if(cycles>250000)$fatal(1,"timeout");
  if(checking)begin
   if(held && (!vv || {vl,vy,vx}!==held_payload))$fatal(1,"unstable vertex under stall");
   held=vv && !vr;held_payload={vl,vy,vx};
   if(vv && vr)begin
    if(outputs>=en || {vy,vx}!==expected[outputs] || vl!==(outputs==en-1))
     $fatal(1,"hull vertex %0d actual=%0d,%0d expected=%0d,%0d last=%0d",outputs,vx,vy,expected[outputs][7:0],expected[outputs][14:8],vl);
    outputs=outputs+1;
   end
  end else held=0;
 end
 task launch;
 begin @(negedge clk);start=1;@(negedge clk);start=0;end endtask
 task stream;
 begin
  for(i=0;i<n;i=i+1)begin
   @(negedge clk);valid=0;while(!ready)@(negedge clk);
   repeat(rng[1:0])@(negedge clk);
   valid=1;pixel=mask[i];last=i==n-1;
   if(expected_fault==1 && i==n/2)last=1;
   if(expected_fault==2 && i==n-1)last=0;
   @(negedge clk);valid=0;
   if(expected_fault==1 && i==n/2)i=n;
  end
 end endtask
 task abort;
 begin @(negedge clk);valid=0;clear=1;checking=0;@(negedge clk);clear=0;
  if(busy || done || vv || ready)$fatal(1,"abort failed");outputs=0;
 end endtask
 initial begin
  if(!$value$plusargs("INPUT=%s",path)||!$value$plusargs("EXPECTED=%s",expected_path)||
     !$value$plusargs("W=%d",w)||!$value$plusargs("H=%d",h)||!$value$plusargs("COUNT=%d",en))$fatal(1,"arguments");
  if($value$plusargs("ABORT=%d",abort_stage))begin end
  if($value$plusargs("FAULT=%d",expected_fault))begin end
  width=w;height=h;n=w*h;$readmemb(path,mask,0,n-1);
  if(en>0)$readmemh(expected_path,expected,0,en-1);
  repeat(5)@(negedge clk);rst=1;
  if(abort_stage)begin
   launch();
   if(abort_stage==1)repeat(12)@(negedge clk);
   else if(abort_stage==2)begin while(!ready)@(negedge clk);valid=1;pixel=1;last=0;@(negedge clk);end
   else begin stream();while(dut.state<3 || dut.state>10)@(negedge clk);end
   abort();
  end
  checking=1;launch();stream();while(!done)@(negedge clk);
  if(expected_fault)begin if(!fault)$fatal(1,"missing protocol fault");end
  else if(fault || outputs!=en || count!=en)$fatal(1,"hull completion count=%0d/%0d outputs=%0d fault=%0d",count,en,outputs,fault);
  @(negedge clk);checking=0;
  // Reuse metadata and stack with an empty mask, without reset.
  for(i=0;i<n;i=i+1)mask[i]=0;
  expected_fault=0;en=0;outputs=0;checking=1;
  launch();stream();while(!done)@(negedge clk);
  if(fault || outputs!=0 || count!=0)$fatal(1,"stale hull after empty frame");
  $display("HAND_CONVEX_HULL_PASS cycles=%0d",cycles);$finish;
 end
endmodule
