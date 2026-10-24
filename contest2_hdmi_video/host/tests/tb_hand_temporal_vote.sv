`timescale 1ns/1ps
module tb_hand_temporal_vote;
reg clk=0;always #5 clk=~clk;
reg rst=0,clear=0,fv=0,present=0;reg[1:0]raw;
wire valid,box_valid;wire[1:0]id;
ua_hand_temporal_vote dut(clk,rst,clear,fv,raw,present,valid,id,box_valid);
reg[2047:0]path;reg[15:0]rng=16'h7239;
integer file,rc,r,p,c,ei,eb,jobs=0,i;
always @(posedge clk)rng<={rng[14:0],rng[15]^rng[13]^rng[12]^rng[10]};
initial begin
 if(!$value$plusargs("INPUT=%s",path))$fatal(1,"input");file=$fopen(path,"r");if(!file)$fatal(1,"open");
 repeat(5)@(negedge clk);rst=1;
 while(!$feof(file))begin
  rc=$fscanf(file,"%d %d %d %d %d\n",r,p,c,ei,eb);if(rc!=5)$fatal(1,"header");
  if(c)begin clear=1;@(negedge clk);clear=0;if(valid || id || box_valid)$fatal(1,"clear");end
  for(i=0;i<rng[2:0];i=i+1)begin
   @(negedge clk);if(valid)$fatal(1,"phantom result");
  end
  raw=r;present=p;fv=1;@(negedge clk);fv=0;
  if(!valid || id!=ei || box_valid!==eb[0])$fatal(1,"frame %0d id=%0d/%0d box=%0d/%0d",jobs,id,ei,box_valid,eb);
  @(negedge clk);if(valid)$fatal(1,"valid not pulse");jobs=jobs+1;
 end
 $display("HAND_TEMPORAL_VOTE_PASS tests=%0d",jobs);$finish;
end
endmodule
