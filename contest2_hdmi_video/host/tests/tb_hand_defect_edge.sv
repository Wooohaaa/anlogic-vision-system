`timescale 1ns/1ps
module tb_hand_defect_edge;
reg clk=0;always #5 clk=~clk;
reg rst=0,clear=0,start=0,pvalid=0,pend=0;
reg[7:0]ax,bx,px;reg[6:0]ay,by,py;reg[10:0]radius;
wire ready,busy,done,fault,qualified,has;wire[7:0]fx;wire[6:0]fy;wire[19:0]cross_value;wire[9:0]length;
ua_hand_defect_edge dut(clk,rst,clear,start,ax,bx,ay,by,radius,pvalid,pend,px,py,
 ready,busy,done,fault,qualified,has,fx,fy,cross_value,length);
reg[2047:0]path;reg[14:0]points[0:8191];reg[15:0]rng=16'h9317;
integer file,rc,ta,tb,tc,td,tr,n,eq,eh,ex,ey,ec,el,invalid,abort_stage,i,jobs=0,ticks=0;
integer qx,qy;
always @(posedge clk)begin
 rng<={rng[14:0],rng[15]^rng[13]^rng[12]^rng[10]};ticks=ticks+1;
 if(ticks>5000000)$fatal(1,"timeout");
end
task launch;
begin @(negedge clk);start=1;@(negedge clk);start=0;end endtask
task abort;
begin @(negedge clk);pvalid=0;pend=0;clear=1;@(negedge clk);clear=0;
 if(busy||ready||done)$fatal(1,"clear");end endtask
task send_point(input integer idx,input integer last_point);
begin
 while(!ready)@(negedge clk);
 repeat(rng[1:0])@(negedge clk);
 pvalid=1;pend=last_point;px=points[idx][7:0];py=points[idx][14:8];
 @(negedge clk);pvalid=0;pend=0;
end endtask
initial begin
 if(!$value$plusargs("INPUT=%s",path))$fatal(1,"input");file=$fopen(path,"r");if(!file)$fatal(1,"open");
 repeat(5)@(negedge clk);rst=1;
 while(!$feof(file))begin
  rc=$fscanf(file,"%d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",ta,tb,tc,td,tr,n,eq,eh,ex,ey,ec,el,invalid,abort_stage);
  if(rc!=14 || n>8192)$fatal(1,"header");
  ax=ta;ay=tb;bx=tc;by=td;radius=tr;
  for(i=0;i<n;i=i+1)begin rc=$fscanf(file,"%d %d\n",qx,qy);if(rc!=2)$fatal(1,"point");points[i]={7'(qy),8'(qx)};end
  if(abort_stage)begin
   launch();
   if(abort_stage==1)repeat(5)@(negedge clk);
   else if(abort_stage==2)send_point(0,0);
   else begin
    for(i=0;i<n;i=i+1)send_point(i,i==n-1);
    while(dut.state!=7)@(negedge clk);
   end
   abort();
  end
  launch();
  if(invalid!=1)begin
   for(i=0;i<n;i=i+1)send_point(i,i==n-1);
   if(n==0)begin while(!ready)@(negedge clk);pend=1;@(negedge clk);pend=0;end
  end
  while(!done)@(negedge clk);
  if(fault!==(invalid!=0) || (!invalid && (qualified!==eq[0] || has!==eh[0] || fx!=ex || fy!=ey || cross_value!=ec || length!=el)))
   $fatal(1,"edge=%0d qualified=%0d/%0d far=%0d:%0d,%0d/%0d:%0d,%0d cross=%0d/%0d len=%0d/%0d fault=%0d",jobs,qualified,eq,has,fx,fy,eh,ex,ey,cross_value,ec,length,el,fault);
  @(negedge clk);if(done)$fatal(1,"done must pulse");jobs=jobs+1;
 end
 $display("HAND_DEFECT_EDGE_PASS tests=%0d",jobs);$finish;
end
endmodule
