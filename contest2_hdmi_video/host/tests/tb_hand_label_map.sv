`timescale 1ns/1ps
module tb_hand_label_map;
parameter LABELS=128;
reg clk=0;always #5 clk=~clk;
reg rst=0,clear=0,start=0,mode=0,rv=0;reg[17:0]rd=0;
wire ready,read,mr,mw,busy,done,fault;wire[11:0]ra;wire[13:0]ma;wire[15:0]md;reg[15:0]mq=0;
wire[7:0]labels;wire[31:0]cycles;
reg[15:0]memory[0:14399];reg[17:0]source[0:2429];
reg[15:0]rng=16'hcd52;wire memory_ready=rng[1:0]!=0;
ua_hand_label_map #(.LABELS(LABELS)) dut(clk,rst,clear,start,mode,ready,read,ra,rv,rd,
 mr,mw,ma,md,memory_ready,mq,busy,done,fault,labels,cycles);
reg[4095:0]mask_path,out_path;
integer pending=0,saved=0,delay_cycles=0,ticks=0,fd,i,which,expected_fault=0,abort_stage=0;
always @(posedge clk)begin
 rng<={rng[14:0],rng[15]^rng[13]^rng[12]^rng[10]};rv<=0;ticks=ticks+1;
 if(ticks>2000000)$fatal(1,"label map timeout state=%d",dut.state);
 if(read)begin
  if(pending || ra>=2430)$fatal(1,"mask read protocol");
  pending=1;saved=ra;delay_cycles=1+rng[4:2];
 end
 if(pending)begin
  if(delay_cycles==0)begin pending=0;rv<=1;rd<=source[saved];end
  else delay_cycles=delay_cycles-1;
 end
 if(mr && mw)$fatal(1,"scratch read/write conflict");
 if((mr || mw) && ma>=14400)$fatal(1,"scratch address overflow");
 if(mr && memory_ready)mq<=memory[ma];
 if(mw && memory_ready)memory[ma]<=md;
end
task launch;
begin
 while(!ready)@(negedge clk);
 start=1;@(negedge clk);start=0;mode=~mode;
end endtask
initial begin
 if(!$value$plusargs("MASK=%s",mask_path) || !$value$plusargs("OUT=%s",out_path))$fatal(1,"paths");
 if($value$plusargs("FAULT=%d",expected_fault))begin end
 if($value$plusargs("ABORT=%d",abort_stage))begin end
 $readmemh(mask_path,source);for(i=0;i<14400;i=i+1)memory[i]=16'hbeef;
 repeat(5)@(negedge clk);rst=1;
 if(abort_stage)begin
  launch();
  if(abort_stage==1)while(!pending)@(negedge clk);
  else if(abort_stage==2)while(!mr)@(negedge clk);
  else while(dut.state!=18)@(negedge clk);
  clear=1;@(negedge clk);clear=0;mode=0;
  if(busy || done || mr || mw || read)$fatal(1,"clear incomplete");
 end
 for(which=0;which<2;which=which+1)begin
  mode=which;launch();while(!done)@(negedge clk);
  if(fault!==(expected_fault!=0))$fatal(1,"fault %d/%d mode=%d labels=%d",fault,expected_fault,which,labels);
  $display("LABEL_PASS mode=%d labels=%d cycles=%d fault=%d",which,labels,cycles,fault);
  @(negedge clk);if(done)$fatal(1,"done not pulse");
  if(expected_fault)begin $display("HAND_LABEL_MAP_EXPECTED_OVERFLOW_PASS");$finish;end
 end
 fd=$fopen(out_path,"w");for(i=0;i<14400;i=i+1)$fdisplay(fd,"%04x",memory[i]);$fclose(fd);
 $display("HAND_LABEL_MAP_PASS");$finish;
end
endmodule
