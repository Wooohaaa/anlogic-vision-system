`timescale 1ns/1ps
module tb_hand_wrist_median;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,clear=0,start=0,valid=0,pixel=0,last=0;
 reg[7:0]width,cx;reg[6:0]height,cy;reg[10:0]radius;
 wire ready,busy,done,fault;wire[13:0]count;wire[8:0]wx,wy;
 wire signed[9:0]dx,dy;
 ua_hand_wrist_median dut(clk,rst,clear,start,width,cx,height,cy,radius,
  valid,pixel,last,ready,busy,done,fault,count,wx,wy,dx,dy);
 reg memory[0:14399];reg[2047:0]path;
 reg[15:0]random_state=16'h5931;
 integer w,h,px,py,r,ex,ey,en,n,i,expected_fault=0,abort_stage=0;
 integer cycles=0,transfers=0;
 always @(posedge clk)begin
  random_state<={random_state[14:0],random_state[15]^random_state[13]^random_state[12]^random_state[10]};
  cycles=cycles+1;if(cycles>200000)$fatal(1,"timeout");
  if(valid && ready)transfers=transfers+1;
 end
 task launch;
 begin @(negedge clk);start=1;@(negedge clk);start=0;end endtask
 task abort;
 begin
  @(negedge clk);valid=0;clear=1;@(negedge clk);clear=0;
  if(busy || done || ready)$fatal(1,"abort failed");
 end endtask
 task stream;
 begin
  for(i=0;i<n;i=i+1)begin
   @(negedge clk);valid=0;
   while(!ready)@(negedge clk);
   repeat(random_state[1:0])@(negedge clk);
   valid=1;pixel=memory[i];last=(i==n-1);
   if(expected_fault==1 && i==n/2)last=1;
   if(expected_fault==2 && i==n-1)last=0;
   @(negedge clk);valid=0;
   if(expected_fault==1 && i==n/2)i=n;
  end
 end endtask
 task check_result;
 begin
  while(!done)@(negedge clk);
  if(fault || count!=en || wx!=ex || wy!=ey || dx!=ex-2*px || dy!=ey-2*py)
   $fatal(1,"wrist count %0d/%0d x %0d/%0d y %0d/%0d vector %0d,%0d expected %0d,%0d fault=%0d",count,en,wx,ex,wy,ey,dx,dy,ex-2*px,ey-2*py,fault);
 end endtask
 initial begin
  if(!$value$plusargs("INPUT=%s",path)||!$value$plusargs("W=%d",w)||!$value$plusargs("H=%d",h)||
     !$value$plusargs("CX=%d",px)||!$value$plusargs("CY=%d",py)||!$value$plusargs("R=%d",r)||
     !$value$plusargs("EX=%d",ex)||!$value$plusargs("EY=%d",ey)||!$value$plusargs("COUNT=%d",en))$fatal(1,"arguments");
  if($value$plusargs("FAULT=%d",expected_fault))begin end
  if($value$plusargs("ABORT=%d",abort_stage))begin end
  width=w;height=h;cx=px;cy=py;radius=r;n=w*h;
  $readmemb(path,memory,0,n-1);
  repeat(5)@(negedge clk);rst=1;
  if(abort_stage!=0)begin
   launch();
   if(abort_stage==1)repeat(20)@(negedge clk);
   else if(abort_stage==2)begin
    while(!ready)@(negedge clk);valid=1;pixel=1;last=0;@(negedge clk);valid=0;
    repeat(2)@(negedge clk);
   end else begin stream();while(dut.state!=8)@(negedge clk);end
   abort();
  end
  launch();stream();
  if(expected_fault)begin
   while(!done)@(negedge clk);if(!fault)$fatal(1,"missing last fault");
   $display("WRIST_EXPECTED_FAULT_PASS");
  end else begin
   check_result();@(negedge clk);
   // Reuse the same RAM with a different mask; no stale histogram allowed.
   for(i=0;i<n;i=i+1)memory[i]=0;
   en=0;ex=2*px;ey=2*(py+r/16);
   launch();stream();check_result();
   $display("WRIST_MEDIAN_PASS transfers=%0d cycles=%0d",transfers,cycles);
  end
  $finish;
 end
endmodule
