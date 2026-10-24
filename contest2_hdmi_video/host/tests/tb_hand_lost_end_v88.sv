`timescale 1ns/1ps
module tb_hand_lost_end_v88;
reg clk=0;always #5 clk=~clk;
reg rst=0,v=0,done=0;reg[9:0]x=0,y=0;
wire result,fault;integer t,rr,cc,n=0,expected_faults=1;
always @(posedge clk)if(result && fault)n=n+1;
ua_hand_binary_native #(.MAX_CYCLES(500000)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_clear(1'b0),.I_sample_valid(v),.I_frame_done(done),
 .I_x_grp(x),.I_y(y),.I_rgb(96'h808080808080808080808080),
 .O_result_valid(result),.O_fault(fault));
task ready;
 begin t=0;while((dut.state!=0 || !dut.shape_ready || dut.capture_owned) && t<600000)begin @(negedge clk);t=t+1;end
 if(t==600000)$fatal(1,"capture did not recover");end
endtask
task acquire;
 begin @(negedge clk);v=1;x=0;y=7;@(negedge clk);x=1;@(negedge clk);v=0;repeat(4)@(negedge clk);end
endtask
task fault_result;
 begin t=0;while(n<expected_faults && t<600000)begin @(negedge clk);t=t+1;end
 if(n!=expected_faults)$fatal(1,"lost EOF permanently wedges hand acquisition");
 expected_faults=expected_faults+1;repeat(6)@(negedge clk);ready;end
endtask
initial begin
 repeat(5)@(negedge clk);rst=1;ready;
 // One sampled pair, then no EOF and no further input: bounded watchdog.
 acquire;fault_result;
 // Missing EOF followed by a new frame: reject stale bank, then rearm.
 acquire;acquire;fault_result;
 // A genuine complete frame must work again without resetting the FPGA.
 for(rr=0;rr<90;rr=rr+1)begin
  for(cc=0;cc<320;cc=cc+1)begin @(negedge clk);v=1;x=cc;y=rr*8+7;end
  @(negedge clk);v=0;repeat(2)@(negedge clk);
 end
 repeat(3)@(negedge clk);done=1;@(negedge clk);done=0;
 t=0;while(!result && t<600000)begin @(negedge clk);t=t+1;end
 if(!result || fault || dut.O_id || dut.O_box_valid)$fatal(1,"valid restart failed");
 $display("HAND_LOST_END_V88_PASS faults=%d genuine_restart=1",n);$finish;
end
initial begin #20000000;$fatal(1,"test timeout");end
endmodule
