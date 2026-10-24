`timescale 1ns/1ps
module tb_awb_pre73_compare;
reg clk=0,rst=1,v=0,u=0,l=0,en=1;always #5 clk=~clk;
reg [95:0] data=0;wire [107:0] rgb0,rgb1;wire ov0,ov1,ol0,ol1,ou0,ou1;wire [10:0] status0,status1;
ua_awb_frame #(.IMG_WIDTH(128),.IMG_HEIGHT(16),.OUTPUT_CHANNEL_BITS(9),.RUNTIME_CONTROL(1)) a(
 .I_clk(clk),.I_rst_n(rst),.I_tlast(l),.I_tuser(u),.I_tvalid(v),.I_tdata(data),.I_enable(en),
 .O_tdata(rgb0),.O_tvalid(ov0),.O_tlast(ol0),.O_tuser(ou0),.O_status(status0),.O_tready(1'b1));
ua_awb_pre73_reference #(.IMG_WIDTH(128),.IMG_HEIGHT(16),.OUTPUT_CHANNEL_BITS(9),.RUNTIME_CONTROL(1)) b(
 .I_clk(clk),.I_rst_n(rst),.I_tlast(l),.I_tuser(u),.I_tvalid(v),.I_tdata(data),.I_enable(en),
 .O_tdata(rgb1),.O_tvalid(ov1),.O_tlast(ol1),.O_tuser(ou1),.O_status(status1),.O_tready(1'b1));
integer f,y,x,region,cycles=0;reg [23:0] p;
always @(posedge clk)begin
 #1;if(rst)begin
  cycles=cycles+1;
  if({ov0,ol0,ou0,status0,rgb0}!=={ov1,ol1,ou1,status1,rgb1})$fatal(1,"output mismatch %0d",cycles);
  if({a.gain_r,a.gain_b,a.pending_gain_r,a.pending_gain_b,a.spatial_confident}!==
     {b.gain_r,b.gain_b,b.pending_gain_r,b.pending_gain_b,b.spatial_confident})$fatal(1,"estimator mismatch");
 end
end
initial begin
 #1;rst=0;repeat(4)@(negedge clk);rst=1;
 for(f=0;f<64;f=f+1)begin
  en=(f<56 || f>=60);
  repeat(5)@(negedge clk);
  for(y=0;y<16;y=y+1)begin
   for(x=0;x<32;x=x+1)begin
    region=(y>=8?2:0)+(x>=16?1:0);
    if(f<16)p=24'h50645a;
    else if(f<32)p=24'h646464;
    else if(f<48)p=(region==f%4)?24'h967878:24'h646464;
    else p=(x%5==0)?24'h10e810:24'h786450;
    @(negedge clk);v=1;u=(y==0 && x==0);l=(x==31);data={4{p}};
    if(x==7)begin @(negedge clk);v=0;u=0;l=0;end
   end
   @(negedge clk);v=0;u=0;l=0;repeat(60)@(negedge clk);
  end
 end
 repeat(150)@(negedge clk);
 $display("AWB_PRE73_RECONSTRUCTED_CYCLE_EQ_PASS 64_frames production9bit_runtime gain_data_status_equal cycles=%0d",cycles);$finish;
end
endmodule
