`timescale 1ns/1ps
module tb_awb_toggle;
parameter BITS=9;
reg clk=0;always #8 clk=~clk;
reg rst=0,v=0,u=0,l=0,en=1;
reg [95:0] data={4{24'h405064}};
wire ov,ol,ou,ready;wire [12*BITS-1:0] out;wire [10:0] status;
integer f,y,x,k,pixels=0;
reg [BITS-1:0] expected_r,expected_b;
ua_awb_frame #(.IMG_WIDTH(256),.IMG_HEIGHT(4),.OUTPUT_CHANNEL_BITS(BITS),.RUNTIME_CONTROL(1)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_tlast(l),.I_tuser(u),.I_tdata(data),.I_tvalid(v),
 .I_tready(ready),.O_tlast(ol),.O_tuser(ou),.O_tdata(out),.O_tvalid(ov),.O_tready(1'b1),.I_enable(en),.O_status(status));
always @(posedge clk) begin
 #1;
 if(rst && ov) begin
  expected_r=dut.enabled?128:64;expected_b=dut.enabled?50:100;
  for(k=0;k<4;k=k+1) begin
   if(out[(k*3+2)*BITS+:BITS]!==expected_r || out[(k*3+1)*BITS+:BITS]!==80 || out[(k*3)*BITS+:BITS]!==expected_b)
    $fatal(1,"gain/bypass mismatch bits=%d output=%h enabled=%b",BITS,out,dut.enabled);
  end
  if(status !== (dut.enabled ? {1'b1,5'd20,5'd5} : {1'b0,5'd10,5'd10})) $fatal(1,"incorrect applied coefficient status");
  pixels=pixels+4;
 end
end
initial begin
 repeat(3) @(negedge clk);rst=1;
 force dut.gain_r=20'h20000;force dut.gain_b=20'h08000;
 for(f=0;f<3;f=f+1) begin
  @(negedge clk);u=1;v=0;l=0;
  @(negedge clk);u=0;
  for(y=0;y<4;y=y+1) begin
   for(x=0;x<64;x=x+1) begin
    @(negedge clk);v=1;l=(x==63);
    if(y==1 && x==20) en=(f==0)?0:1;
    if(y==2 && dut.enabled!==(f!=1)) $fatal(1,"midframe enable changed");
   end
   @(negedge clk);v=0;l=0;repeat(70) @(negedge clk);
  end
 end
 repeat(200) @(negedge clk);
 if(pixels!=3072) $fatal(1,"stream geometry changed pixels=%d",pixels);
 force dut.gain_r=20'd81920;force dut.gain_b=20'd49152;#1;
 if(status!=={1'b1,5'd13,5'd8}) $fatal(1,"round half up coefficient error");
 force dut.gain_r=20'd81919;force dut.gain_b=20'd49151;#1;
 if(status!=={1'b1,5'd12,5'd7}) $fatal(1,"below half coefficient error");
 $display("AWB_TOGGLE_PASS bits=%0d unity_bypass all_4_lanes frame_atomic coefficient_status half_rounding pixels=%0d",BITS,pixels);$finish;
end
endmodule
