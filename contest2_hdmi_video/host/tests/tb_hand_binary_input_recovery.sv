`timescale 1ns/1ps
module tb_hand_binary_input_recovery;
reg clk=0;always #5 clk=~clk;
reg rst=0,clear=0,valid=0,frame_done=0;reg[9:0]x=0,y=0;
wire result,box,fault,drop;wire[1:0]id,raw;wire[2:0]tips;
wire[7:0]bx,bw;wire[6:0]by,bh;wire[31:0]cycles;
ua_hand_binary_native dut(clk,rst,clear,valid,frame_done,x,y,96'h808080808080808080808080,
 result,id,raw,tips,box,bx,bw,by,bh,fault,drop,cycles);
integer rr,cc,t;
task ready;
 begin t=0;while((dut.state!=0 || !dut.shape_ready || dut.capture_owned) && t<100000)begin @(negedge clk);t=t+1;end
 if(t==100000)$fatal(1,"capture ownership did not recover");end
endtask
task expect_fault;
 begin t=0;while(!result && t<200)begin @(negedge clk);t=t+1;end
 if(!result || !fault || box || id)$fatal(1,"bad frame not safely rejected");
 repeat(5)@(negedge clk);if(dut.capture_owned || dut.front_input_fault)$fatal(1,"sticky fault/owner was not flushed");end
endtask
initial begin
 repeat(5)@(negedge clk);rst=1;ready;
 // Missing the odd sample of a pair: never reinterpret it as valid RGB.
 valid=1;x=0;y=7;@(negedge clk);x=3;
 @(negedge clk);valid=0;expect_fault;ready;
 // Clear after acquisition, before the first native sample exists.
 valid=1;x=0;y=7;@(negedge clk);valid=0;
 if(!dut.capture_owned)$fatal(1,"frame was not reserved at the first sample");
 clear=1;@(negedge clk);clear=0;
 repeat(3)@(negedge clk);
 if(dut.capture_owned || fault || box || id)$fatal(1,"clear did not release capture");ready;
 // A one-pixel frame must also release the reservation after rejection.
 valid=1;x=0;y=7;@(negedge clk);x=1;@(negedge clk);valid=0;
 repeat(3)@(negedge clk);frame_done=1;@(negedge clk);frame_done=0;
 expect_fault;ready;
 // Follow both failures with a complete, genuine RGB frame (no skin).
 for(rr=0;rr<90;rr=rr+1)begin
  for(cc=0;cc<320;cc=cc+1)begin @(negedge clk);valid=1;x=cc;y=rr*8+7;end
  @(negedge clk);valid=0;repeat(2)@(negedge clk);
 end
 repeat(3)@(negedge clk);frame_done=1;@(negedge clk);frame_done=0;
 t=0;while(!result && t<500000)begin @(negedge clk);t=t+1;end
 if(!result || fault || raw || id || box)$fatal(1,"valid RGB frame failed after recovery");
 $display("HAND_BINARY_INPUT_RECOVERY_PASS malformed=1 truncated=1 clear_owner=1 valid_restart=1");$finish;
end
initial begin #20000000;$fatal(1,"recovery timeout");end
endmodule
