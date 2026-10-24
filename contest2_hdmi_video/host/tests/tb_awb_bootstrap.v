`timescale 1ns/1ps
module tb_awb_bootstrap;
 parameter CHANNEL_BITS=8;
 parameter RUNTIME=0;
 reg clk=0,rst=1,valid=0,user=0,last=0;
 reg [95:0] data=0;
 always #8 clk=~clk;
 wire ready,ov,ou,ol; wire [12*CHANNEL_BITS-1:0] od;
 ua_awb_frame #(.IMG_WIDTH(256),.IMG_HEIGHT(4),.OUTPUT_CHANNEL_BITS(CHANNEL_BITS),.RUNTIME_CONTROL(RUNTIME)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_tlast(last),.I_tuser(user),.I_tdata(data),.I_tvalid(valid),.I_tready(ready),.O_tlast(ol),.O_tuser(ou),.O_tdata(od),.O_tvalid(ov),.O_tready(1'b1),.I_enable(1'b1),.O_status());
 integer f,x,y,region;
 reg [23:0] pixel;
 reg [19:0] prev_r=65536,prev_b=65536;
 reg prev_mode=1;
 always @(posedge clk) begin
  #1;
  if(rst && !user && (dut.gain_r!==prev_r || dut.gain_b!==prev_b || dut.bootstrap_mode!==prev_mode))
   $fatal(1,"AWB policy changed inside frame");
  prev_r=dut.gain_r;prev_b=dut.gain_b;prev_mode=dut.bootstrap_mode;
  if(rst && (dut.gain_r<32768 || dut.gain_r>131072 || dut.gain_b<32768 || dut.gain_b>131072))
   $fatal(1,"gain outside safe range");
  if(ov && (^od===1'bx)) $fatal(1,"unknown output");
 end
 task reset_dut;
 begin @(negedge clk);rst=0;valid=0;user=0;last=0;
 repeat(3) @(negedge clk);rst=1;end
 endtask
 task frame;
 input [23:0] color;
 input integer layout;
 input integer marker;
 begin
  if(!marker) begin @(negedge clk);user=1;valid=0;@(negedge clk);user=0;end
  for(y=0;y<4;y=y+1) begin
   for(x=0;x<64;x=x+1) begin
    region=(y>=2 ? 2 : 0)+(x>=32 ? 1 : 0);
    pixel=color;
    if(layout==1 && region>=2) pixel=24'h080808;
    if(layout==2 && region!=0) pixel=24'h080808;
    if(layout==3 && region==1) pixel=24'h644646;
    if(layout==3 && region>=2) pixel=24'h080808;
    @(negedge clk);valid=1;last=(x==63);data={4{pixel}};
    user=marker && y==0 && x==0;
    if(x==11) begin @(negedge clk);valid=0;user=0;last=0;end
   end
   @(negedge clk);valid=0;last=0;user=0;
   repeat(60) @(negedge clk);
  end
  repeat(160) @(negedge clk);
 end
 endtask
 task converge;
 input [23:0] color;
 input integer layout,expected_r,expected_b;
 begin
  for(f=0;f<96;f=f+1) frame(color,layout,f%2);
  if(dut.gain_r<expected_r-500 || dut.gain_r>expected_r+500 ||
     dut.gain_b<expected_b-500 || dut.gain_b>expected_b+500 || dut.bootstrap_mode)
   $fatal(1,"convergence failed color=%h gains=%d/%d bootstrap=%b",color,dut.gain_r,dut.gain_b,dut.bootstrap_mode);
 end
 endtask
 initial begin
  #1 rst=0;
  reset_dut;converge(24'h466446,0,93622,93622);
  converge(24'h644646,0,45875,65536);
  converge(24'h646464,0,65536,65536);
  reset_dut;converge(24'h326432,0,131072,131072);
  reset_dut;converge(24'h202820,0,81920,81920);
  reset_dut;converge(24'h466446,1,93622,93622);
  reset_dut;
  for(f=0;f<32;f=f+1) frame(24'h466446,2,f%2);
  if(dut.gain_r!=65536 || dut.gain_b!=65536) $fatal(1,"single-region drift");
  for(f=0;f<32;f=f+1) frame(24'h466446,3,f%2);
  if(dut.gain_r!=65536 || dut.gain_b!=65536) $fatal(1,"conflicting-region drift");
  for(f=0;f<32;f=f+1) frame(24'h181c18,0,f%2);
  if(dut.gain_r!=65536 || dut.gain_b!=65536) $fatal(1,"dark-noise drift");
  $display("AWB_BOOTSTRAP_PASS strong_green red_cast dark_cast 2x_limit two_regions sparse_conflict_dark_hold reacquisition frame_only_policy");
  $finish;
 end
 initial begin #20000000;$fatal(1,"timeout");end
endmodule
