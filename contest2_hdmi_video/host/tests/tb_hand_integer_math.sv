`timescale 1ns/1ps
module tb_hand_integer_math;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,clear=0,start=0,op=0;reg[31:0]a,b;
 wire busy,done,fault;wire[31:0]q,r;
 ua_hand_integer_math dut(clk,rst,clear,start,op,a,b,busy,done,fault,q,r);
 reg[2047:0]path;integer file,rc,n=0,kind,ef,cycles;reg[31:0]ta,tb,tq,tr;
 task launch;
 begin @(negedge clk);start=1;@(negedge clk);start=0;end endtask
 initial begin
  if(!$value$plusargs("INPUT=%s",path))$fatal(1,"input");file=$fopen(path,"r");if(!file)$fatal(1,"open");
  repeat(5)@(negedge clk);rst=1;
  while(!$feof(file))begin
   rc=$fscanf(file,"%d %h %h %h %h %d\n",kind,ta,tb,tq,tr,ef);
   if(rc!=6)$fatal(1,"vector parse");op=kind;a=ta;b=tb;
   launch();cycles=0;
   while(!done)begin
    // Spurious start while busy may not replace the operation.
    if(cycles==3)start=1;else start=0;
    @(negedge clk);cycles=cycles+1;if(cycles>33)$fatal(1,"bounded latency");
   end
   start=0;
   if(busy || fault!==ef[0] || (!ef && (q!==tq || r!==tr)))
    $fatal(1,"math vector=%0d op=%0d a=%h b=%h q=%h/%h rem=%h/%h fault=%0d",n,op,a,b,q,tq,r,tr,fault);
   if(!ef && cycles!=(op ? 16 : 32))$fatal(1,"latency %0d",cycles);
   @(negedge clk);if(done)$fatal(1,"done must pulse");
   if(!ef && (q!==tq || r!==tr))$fatal(1,"unstable result");
   n=n+1;
  end
  // Abort each mode in flight; no delayed completion may leak out.
  for(kind=0;kind<2;kind=kind+1)begin
   op=kind;a=32'hffffffff;b=3;launch();repeat(5)@(negedge clk);
   clear=1;@(negedge clk);clear=0;
   if(busy || done || fault)$fatal(1,"clear");
   repeat(35)begin @(negedge clk);if(done)$fatal(1,"late done after clear");end
  end
  $display("HAND_INTEGER_MATH_PASS tests=%0d",n);$finish;
 end
endmodule
