`timescale 1ns/1ps
module tb_hand_blob_scan;
reg clk=0; always #5 clk=~clk;
reg rst=0,clear=0,start=0,mode=0,read_valid=0;
reg [17:0] read_data=0;
wire read_req,busy,done,overflow,blob;
wire [11:0] addr;
wire [13:0] area,seeds;
wire [7:0] xmin,xmax;
wire [6:0] ymin,ymax;
wire [7:0] anchor_x;wire [6:0] anchor_y;
wire unused_red_read;wire[13:0]unused_red_addr;wire[23:0]unused_red_sum;
reg [17:0] memory [0:2429];
string input_path;
integer pending=0,delay_count=0,saved_addr=0,cycles=0,pass=0;
integer random_state=12345;
ua_hand_blob_scan dut(clk,rst,clear,start,mode,read_req,addr,
 read_valid,read_data,busy,done,overflow,blob,area,seeds,xmin,xmax,ymin,ymax,anchor_x,anchor_y,
 unused_red_read,unused_red_addr,1'b0,10'd0,unused_red_sum);
// Variable-latency memory, one outstanding transaction. Deliberate bubbles.
always @(negedge clk) begin
 read_valid=0;
 if(!rst || clear) pending=0;
 else begin
  if(read_req) begin
   if(pending) $fatal(1,"multiple outstanding reads");
   if(addr>=2430) $fatal(1,"read out of range %d",addr);
   saved_addr=addr; pending=1;
   random_state=(random_state*1103515245+12345)&32'h7fffffff;
   delay_count=(random_state>>8)%6+1;
  end else if(pending) begin
   if(delay_count==0) begin read_data=memory[saved_addr]; read_valid=1; pending=0; end
   else delay_count=delay_count-1;
  end
 end
end
always @(posedge clk) begin
 #1;
 if(blob) begin
  if(!busy) $fatal(1,"blob outside busy");
  if(area==0 || seeds>area || xmin>xmax || ymin>ymax) $fatal(1,"invalid blob");
  $display("BLOB %0d %0d %0d %0d %0d %0d %0d %0d %0d",pass,area,seeds,xmin,xmax,ymin,ymax,anchor_x,anchor_y);
 end
end
task launch;
 begin @(posedge clk); #2; start=1; @(posedge clk); #2; start=0; end
endtask
initial begin
 if(!$value$plusargs("INPUT=%s",input_path)) $fatal(1,"INPUT required");
 $readmemh(input_path,memory);
 repeat(3) @(posedge clk); #2; rst=1;
 // Abort while a memory response is outstanding, then restart without reset.
 launch(); repeat(23) @(posedge clk); #2; clear=1;
 repeat(2) @(posedge clk); #2; clear=0;
 if(busy || done || blob || read_req) $fatal(1,"clear did not cancel transaction");
 for(pass=0;pass<2;pass=pass+1) begin
  mode=pass; launch(); cycles=0;
  while(!done && cycles<400000) begin @(posedge clk); #2; cycles=cycles+1; end
  if(!done || busy) $fatal(1,"timeout mode=%d state=%d",pass,dut.state);
  $display("DONE %0d %0d %0d",pass,overflow,cycles);
  repeat(3) @(posedge clk); #2;
 end
 $display("HAND_BLOB_SCAN_COMPLETE"); $finish;
end
endmodule
