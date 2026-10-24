`timescale 1ns/1ps
module tb_hand_contour_trace #(parameter STEP_LIMIT=8192,OPENCV_ORDER=0);
reg clk=0;always #5 clk=~clk;
reg rst=0,clear=0,start=0,mode=0,rv=0;
reg [17:0] data=0;reg[7:0] ax=0;reg[6:0] ay=0;
wire rd,busy,done,fault,vertex;wire[11:0]addr;
wire[7:0]x;wire[6:0]y;wire[13:0]count;
reg[17:0]memory[0:2429];string path;
integer pending=0,delay_count=0,saved_addr=0,cycles=0,j,ret,random_state=7541;
ua_hand_contour_trace #(.MAX_STEPS(STEP_LIMIT),.OPENCV_ORDER(OPENCV_ORDER)) dut(clk,rst,clear,start,mode,ax,ay,rd,addr,rv,data,
 busy,done,fault,vertex,x,y,count);
always @(negedge clk)begin
 rv=0;
 if(!rst || clear)pending=0;
 else if(rd)begin
  if(pending || addr>=2430)$fatal(1,"invalid memory request");
  pending=1;saved_addr=addr;
  random_state=(random_state*1103515245+12345)&32'h7fffffff;
  delay_count=(random_state>>8)%4+1;
 end else if(pending)begin
  if(delay_count==0)begin rv=1;data=memory[saved_addr];pending=0;end
  else delay_count=delay_count-1;
 end
end
always @(posedge clk)begin #1;if(vertex)$display("V %0d %0d",x,y);end
task launch;
 begin @(posedge clk);#2;start=1;@(posedge clk);#2;start=0;end
endtask
initial begin
 if(!$value$plusargs("INPUT=%s",path))$fatal(1,"input required");
 ret=$value$plusargs("X=%d",j);ax=j;ret=$value$plusargs("Y=%d",j);ay=j;
 ret=$value$plusargs("MODE=%d",j);mode=j;
 $readmemh(path,memory);
 repeat(3)@(posedge clk);#2;rst=1;
 // Clear with a pending anchor read. No stale vertex may escape.
 launch();repeat(2)@(posedge clk);#2;clear=1;
 repeat(2)@(posedge clk);#2;clear=0;
 if(busy || vertex || rd)$fatal(1,"clear failed");
 launch();cycles=0;
 while(!done && cycles<1000000)begin @(posedge clk);#2;cycles=cycles+1;end
 if(!done || busy)$fatal(1,"trace watchdog state=%d",dut.state);
 $display("DONE %0d %0d %0d",fault,count,cycles);
 $display("HAND_CONTOUR_TRACE_COMPLETE");$finish;
end
endmodule
