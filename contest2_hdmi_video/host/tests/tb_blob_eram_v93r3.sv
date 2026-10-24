`timescale 1ns/1ps
module tb_blob_eram_v93r3;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,v=0,u=0,e=0;reg[2:0]hit=0;
 reg[9:0]x=0,y=0;reg[11:0]pu=0,pv=0;reg[13:0]pp=0,pq=0;
 wire done,ref_done;wire[332:0]result,golden;
 ua_blob_bank3 #(.USE_ERAM(1)) dut(clk,rst,v,u,e,hit,x,y,pu,pv,pp,pq,done,result);
 ua_blob_bank3_legacy reference_dut(clk,rst,v,u,e,hit,x,y,pu,pv,pp,pq,ref_done,golden);
 reg[332:0]queue[0:2];reg[2:0]events;
 integer i,k,checks=0,same_hits=0;reg[31:0]rng=32'h61972a01;
 always @(posedge clk)begin
  if(!rst)begin for(k=0;k<3;k=k+1)queue[k]<=0;events<=0;end
  else begin queue[0]<=golden;queue[1]<=queue[0];queue[2]<=queue[1];events<={events[1:0],ref_done};end
 end
 always @(negedge clk)if(rst)begin
  checks=checks+1;
  if(result!==queue[2] || done!==events[2])
   $fatal(1,"ERAM blob mismatch cycle=%0d done=%b/%b actual=%h expected=%h",i,done,events[2],result,queue[2]);
  if(dut.gen_eram.storage.write_descriptor && dut.gen_eram.storage.I_valid &&
     dut.gen_eram.storage.p_ch==dut.gen_eram.storage.input_ch)same_hits=same_hits+1;
 end
 initial begin
  repeat(4)@(negedge clk);rst=1;
  for(i=0;i<100000;i=i+1)begin
   @(posedge clk);#1;rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
   // Half uses dense same-colour bursts, half frequent colour switches.
   v=(i<50000)?1'b1:(rng[1:0]!=0);u=(i%89==0)||(i%941==0);e=(i%89==88)||(i%941==0);
   hit=(i<50000)?(3'b001<<((i/19)%3)):((rng[4:2]<3)?(3'b001<<rng[4:2]):0);
   x=(i%89<40)?i%40:rng[14:5];y=(i%89<40)?i/89:rng[24:15];
   pu=rng[11:0];pv=rng[23:12];pp=rng[13:0];pq=rng[27:14];
   if(i%1301==1300)begin rst=0;v=0;repeat(2)@(negedge clk);rst=1;end
  end
  @(posedge clk);#1;v=0;repeat(12)@(negedge clk);
  if(same_hits<10000)$fatal(1,"forwarding not exercised");
  $display("BLOB_ERAM_V93R3_EQUIVALENCE_PASS cycles=%0d forwarding=%0d metadata_delay=3",checks,same_hits);$finish;
 end
endmodule
