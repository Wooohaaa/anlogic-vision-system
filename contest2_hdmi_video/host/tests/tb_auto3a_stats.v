`timescale 1ns/1ps
module tb_auto3a_stats;
reg clk=0;always #5 clk=~clk;
reg rst=0,valid=0,user=0,last=0;
reg [95:0] data=0;
wire [7:0] mean;wire toggle;
integer f,y,x,old_toggle,expected;
reg [23:0] pixel;
ua_luma_stats dut(.I_clk(clk),.I_rst_n(rst),.I_tlast(last),.I_tuser(user),.I_tdata(data),.I_tvalid(valid),.O_luma_mean(mean),.O_frame_toggle(toggle),.O_highlight());
initial begin
 repeat(3) @(negedge clk);rst=1;
 for(f=0;f<5;f=f+1) begin
  old_toggle=toggle;
  case(f) 0:pixel=24'h000000;1:pixel=24'hffffff;2:pixel=24'h204080;3:pixel=24'h787878;default:pixel=0;endcase
  for(y=0;y<720;y=y+1) begin
   for(x=0;x<320;x=x+1) begin
    @(negedge clk);valid=1;last=(x==319);user=(x==0 && y==0);data={4{pixel}};
    if(x==0 && y==0) begin
     @(posedge clk);#1;
     if(f>0 && (toggle==old_toggle || mean!==expected)) $fatal(1,"incorrect complete-frame mean %d expected %d",mean,expected);
    end
    if(x==121) begin @(negedge clk);valid=0;last=0;user=0;end
   end
   @(negedge clk);valid=0;last=0;user=0;repeat(4) @(negedge clk);
  end
  if(dut.sample_count!=1024) $fatal(1,"sample coverage %d",dut.sample_count);
  expected=(pixel[23:16]+2*pixel[15:8]+pixel[7:0])/4;
 end
 $display("AUTO3A_STATS_PASS 1280x720 1024_samples black white colour bubbles previous_frame_publish");$finish;
end
endmodule
