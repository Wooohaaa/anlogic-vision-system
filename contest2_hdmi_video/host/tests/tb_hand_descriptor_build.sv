`timescale 1ns/1ps
module tb_hand_descriptor_build;
reg clk=0;always #5 clk=~clk;
reg rst=0,clear=0,start=0,astart=0,bv=0;reg[39:0]blob=0;
wire brdy,bready,bmr,busy,bdone,bfault,q,mode,qready,qvalid,dv,dm,dready;
wire[6:0]root,droot;wire[13:0]bma;wire[95:0]query_data,descriptor;
wire ready,amr,cv,cm,abusy,adone,afault;wire[13:0]ama;wire[95:0]candidate;
wire[4:0]count;wire[31:0]bc,ac;
reg[15:0]rng=16'h81c5,mq=0;wire memory_ready=rng[1:0]!=0,crdy=rng[3:2]!=0;
reg association_run=0;
wire mr=association_run ? amr : bmr;wire[13:0]ma=association_run ? ama : bma;
ua_hand_descriptor_build builder(clk,rst,clear,start,bv,blob[39],blob[31:24],blob[38:32],blob[23:0],brdy,bready,
 bmr,bma,memory_ready,mq,q,mode,root,qready,qvalid,query_data,dv,dm,droot,descriptor,dready,busy,bdone,bfault,bc);
ua_hand_associate #(.EXTERNAL_DESCRIPTOR(1)) assoc(clk,rst,clear,astart,dv,dm,droot,descriptor,dready,ready,
 amr,ama,memory_ready,mq,cv,crdy,cm,candidate,abusy,adone,afault,count,ac,q,mode,root,qready,qvalid,query_data);
reg[15:0]memory[0:14399];reg[39:0]records[0:127];
reg[4095:0]map_path,raw_path,out_path;integer raw_count,i,fd=0,ticks=0;
always @(posedge clk)begin
 rng<={rng[14:0],rng[15]^rng[13]^rng[12]^rng[10]};ticks=ticks+1;
 if(ticks>3000000)$fatal(1,"descriptor chain timeout builder=%d assoc=%d",builder.state,assoc.state);
 if(mr && ma>=14400)$fatal(1,"descriptor map out of bounds");
 if(mr && memory_ready)mq<=memory[ma];
 if(cv && crdy && fd!=0)$fdisplay(fd,"%d %024x",cm,candidate);
end
initial begin
 if(!$value$plusargs("MAP=%s",map_path)||!$value$plusargs("RAW=%s",raw_path)||
 !$value$plusargs("OUT=%s",out_path)||!$value$plusargs("RAW_COUNT=%d",raw_count))$fatal(1,"paths");
 $readmemh(map_path,memory);$readmemh(raw_path,records);
 repeat(5)@(negedge clk);rst=1;
 for(i=0;i<raw_count;i=i+1)begin
  while(!brdy)@(negedge clk);blob=records[i];bv=1;@(negedge clk);
 end
 bv=0;while(!ready || !bready)@(negedge clk);
 start=1;@(negedge clk);start=0;while(!bdone)@(negedge clk);
 if(bfault)$fatal(1,"descriptor builder fault addr=%d",builder.address);
 association_run=1;fd=$fopen(out_path,"w");
 while(!ready)@(negedge clk);astart=1;@(negedge clk);astart=0;while(!adone)@(negedge clk);
 if(afault)$fatal(1,"association fault after descriptor build");
 $fclose(fd);fd=0;
 $display("HAND_ASSOCIATION_PASS builder_cycles=%d assoc_cycles=%d candidates=%d",bc,ac,count);$finish;
end
endmodule
