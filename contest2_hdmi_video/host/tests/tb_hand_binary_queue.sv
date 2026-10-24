`timescale 1ns/1ps
// White-box controller protocol test, NOT image-quality evidence.
// Inject CCL descriptors to reach boundaries impossible to fill quickly in RGB.
module tb_hand_binary_queue;
reg clk=0;always #5 clk=~clk;
reg rst=0,clear=0,inject=0,publish=0,done=0;
reg[7:0]anchor=0;
wire result,box,fault,drop;wire[1:0]id,raw;wire[2:0]tips;
wire[7:0]x,w;wire[6:0]y,h;wire[31:0]cycles;
ua_hand_binary_native dut(clk,rst,clear,1'b0,1'b0,10'd0,10'd0,96'd0,
 result,id,raw,tips,box,x,w,y,h,fault,drop,cycles);
integer k,j;reg[95:0]expected,actual;
task start_frame;
 begin
  @(negedge clk);clear=1;inject=0;publish=0;done=0;
  repeat(3)@(negedge clk);clear=0;
  @(negedge clk);publish=1;@(negedge clk);publish=0;
  repeat(2)@(negedge clk);
 end
endtask
task push_record(input[7:0]a);
 begin
  anchor=a;inject=1;@(negedge clk);inject=0;
  // Next item arrives exactly as the sixth word commits.
  repeat(5)@(negedge clk);
 end
endtask
initial begin
 force dut.mask_valid=publish;
 force dut.blob=inject;force dut.ccl_done=done;force dut.ccl_fault=1'b0;
 force dut.area=14'd300;force dut.red_sum=24'd90000;
 force dut.xmin=8'd10;force dut.xmax=8'd29;
 force dut.ymin=7'd20;force dut.ymax=7'd39;
 force dut.ax=anchor;force dut.ay=7'd20;
 repeat(4)@(negedge clk);rst=1;
 start_frame;
 for(k=0;k<128;k=k+1)push_record(k);
 @(negedge clk);
 if(dut.count!=128 || dut.writer_busy || fault)$fatal(1,"128 descriptors not committed count=%d",dut.count);
 for(k=0;k<128;k=k+1)begin
  expected={12'd0,1'b0,24'd90000,14'd300,k[7:0],7'd20,8'd20,8'd10,7'd20,7'd20};
  actual=0;
  for(j=0;j<6;j=j+1)actual[j*16+:16]=dut.descriptor_memory[k*8+j];
  if(actual!==expected)$fatal(1,"descriptor corruption slot=%d actual=%h expected=%h",k,actual,expected);
 end
 // An additional candidate must fault, never wrap over slot zero.
 inject=1;anchor=8'd200;@(negedge clk);inject=0;
 repeat(3)@(negedge clk);
 if(!fault || id || box)$fatal(1,"overflow did not safely withdraw result");
 // Reset during a partial write must discard it and permit a clean restart.
 start_frame;anchor=7;inject=1;@(negedge clk);inject=0;
 repeat(2)@(negedge clk);clear=1;@(negedge clk);clear=0;
 repeat(2)@(negedge clk);
 if(dut.count || dut.writer_busy || fault || box || id)$fatal(1,"clear retained partial queue");
 start_frame;
 push_record(8'd23);repeat(2)@(negedge clk);
 if(dut.count!=1 || dut.writer_busy)$fatal(1,"restart failed");
 // Empty-frame path must emit a result and return to capture-ready.
 start_frame;
 done=1;@(negedge clk);done=0;repeat(2)@(negedge clk);
 done=1;@(negedge clk);done=0;
 j=0;while(!result && j<50)begin @(negedge clk);j=j+1;end
 if(!result || fault || id || box)$fatal(1,"empty frame failed");
 $display("HAND_BINARY_QUEUE_BOUNDARY_PASS capacity=128 overflow=129 partial_clear=1 restart=1 empty=1");
 $finish;
end
initial begin #100000;$fatal(1,"protocol timeout");end
endmodule
