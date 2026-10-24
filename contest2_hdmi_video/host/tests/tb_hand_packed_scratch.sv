`timescale 1ns/1ps
module tb_hand_packed_scratch;
reg clk=0;always #5 clk=~clk;
reg external_mode=0,rd=0,wr=0;reg[13:0]address=0;reg[15:0]data=0;wire[15:0]q;
ua_hand_binary_scratch_ram dut(clk,external_mode,rd,wr,address,data,q);
reg[9:0]model[0:14399];reg[15:0]expected;reg[31:0]rng=32'h90871246;
integer i,pass,slot,checks=0;
task transfer(input ext,read_enable,write_enable,input[13:0]a,input[15:0]d);
 begin
  @(negedge clk);external_mode=ext;rd=read_enable;wr=write_enable;address=a;data=d;
  if(read_enable)expected=ext ? {6'd0,model[a]} : {1'b0,model[a*2+1][4:0],model[a*2]};
  if(write_enable)begin
   if(ext)model[a]=d[9:0];else begin model[a*2]=d[9:0];model[a*2+1]={5'd0,d[14:10]};end
  end
  @(posedge clk);#1;
  if(read_enable)begin if(q!==expected)$fatal(1,"Packed scratch mode=%d address=%d got=%h expected=%h",ext,a,q,expected);checks=checks+1;end
 end
endtask
initial begin
 for(pass=0;pass<3;pass=pass+1)begin
  for(i=0;i<14400;i=i+1)transfer(1,0,1,i,(i^(pass*341))&1023);
  for(i=0;i<14400;i=i+1)transfer(1,1,0,i,0);
  for(i=0;i<2500;i=i+1)transfer(0,0,1,i,(i*17+pass*1024)&32767);
  for(i=0;i<2500;i=i+1)transfer(0,1,0,i,0);
  for(i=0;i<14400;i=i+1)transfer(1,1,0,i,0);
 end
 for(i=0;i<10000;i=i+1)begin
  rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
  slot=rng%(rng[1] ? 14400 : 2500);
  transfer(rng[1],!rng[0],rng[0],slot,rng[1] ? rng[9:0] : rng[14:0]);
 end
 @(negedge clk);rd=0;wr=0;
 $display("PACKED_SCRATCH_ONE_CYCLE_PASS checks=%d",checks);$finish;
end
endmodule
