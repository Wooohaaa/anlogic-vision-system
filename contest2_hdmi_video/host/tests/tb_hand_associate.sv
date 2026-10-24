`timescale 1ns/1ps
module tb_hand_associate;
reg clk=0;always #5 clk=~clk;
reg rst=0,clear=0,start=0,dv=0,dm=0;reg[6:0]dr=0;reg[95:0]dd=0;
wire dready,ready,mr,cv,cm,busy,done,fault;wire[13:0]ma;wire[95:0]cd;
reg[15:0]mq=0;reg[15:0]rng=16'hc31d;wire memory_ready=rng[1:0]!=0;
wire candidate_ready=(rng[3:2]!=0) && !hold_candidate;
reg hold_candidate=0;
wire[4:0]count;wire[31:0]cycles;
ua_hand_associate dut(clk,rst,clear,start,dv || busy,dm,dr,dd,dready,ready,
 mr,ma,memory_ready,mq,cv,candidate_ready,cm,cd,busy,done,fault,count,cycles,
 1'b0,1'b0,7'd0,,,);
reg[15:0]memory[0:14399];reg[95:0]descs[0:255];
reg[4095:0]map_path,desc_path,out_path;integer i,fd=0,ticks=0,abort_stage=0,expected_fault=0;
reg stalled=0;reg[96:0]held;
always @(posedge clk)begin
 rng<={rng[14:0],rng[15]^rng[13]^rng[12]^rng[10]};ticks=ticks+1;
 if(ticks>3000000)$fatal(1,"association timeout state=%d",dut.state);
 if(mr && ma>=14400)$fatal(1,"association map out of bounds");
 if(mr && memory_ready)mq<=memory[ma];
 if(busy && dready)$fatal(1,"descriptor write accepted during transaction");
 if(stalled && !clear && (!cv || held!=={cm,cd}))$fatal(1,"candidate changed under stall");
 stalled<=cv && !candidate_ready && !clear;held<={cm,cd};
 if(cv && candidate_ready && fd!=0)$fdisplay(fd,"%d %024x",cm,cd);
end
task load;
begin
 while(!dready)@(negedge clk);
 for(i=0;i<256;i=i+1)begin dv=1;dm=(i>>7);dr=i&127;dd=descs[i];@(negedge clk);end
 dv=0;
end endtask
task launch;
begin
 while(!ready)@(negedge clk);start=1;@(negedge clk);start=0;
end endtask
initial begin
 if(!$value$plusargs("MAP=%s",map_path)||!$value$plusargs("DESCS=%s",desc_path)||!$value$plusargs("OUT=%s",out_path))$fatal(1,"paths");
 if($value$plusargs("ABORT=%d",abort_stage))begin end
 if($value$plusargs("FAULT=%d",expected_fault))begin end
 $readmemh(map_path,memory);$readmemh(desc_path,descs);
 repeat(5)@(negedge clk);rst=1;load();
 if(abort_stage)begin
  hold_candidate=abort_stage==2;launch();
  if(abort_stage==1)while(dut.state!=6)@(negedge clk);
  else while(!cv)@(negedge clk);
  clear=1;@(negedge clk);clear=0;hold_candidate=0;
  if(busy || done || cv || mr)$fatal(1,"association clear incomplete");
  load();
 end
 fd=$fopen(out_path,"w");launch();while(!done)@(negedge clk);
 if(fault!==(expected_fault!=0))$fatal(1,"association fault %d/%d",fault,expected_fault);
 $fclose(fd);fd=0;
 @(negedge clk);if(done)$fatal(1,"done not pulse");
 $display("HAND_ASSOCIATION_PASS candidates=%d cycles=%d fault=%d",count,cycles,fault);$finish;
end
endmodule
