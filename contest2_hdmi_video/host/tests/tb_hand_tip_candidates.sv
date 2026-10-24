`timescale 1ns/1ps
module tb_hand_tip_candidates;
parameter EXTERNAL=1;
reg clk=0;always #5 clk=~clk;
reg rst=0,clear=0,start=0,hv=0,hl=0,ev=0,eq=0,ee=0;
reg[7:0]cx,hx,ax,bx;reg[6:0]cy,hy,ay,by;reg[10:0]radius;reg signed[9:0]wx,wy;
wire hr,er,tv,tl,busy,done,fault,mr,mw;wire[7:0]tx;wire[6:0]ty;wire[2:0]count;
wire[13:0]ma;wire[15:0]md,mq;reg[15:0]rng=16'h4127;
wire tr=rng[3:0]!=0;wire mem_ready=EXTERNAL ? rng[1:0]!=0 : 1'b1;
ua_hand_tip_candidates #(.EXTERNAL_MEMORY(EXTERNAL)) dut(
 clk,rst,clear,start,cx,cy,radius,wx,wy,hv,hl,hx,hy,hr,ev,eq,ee,ax,bx,ay,by,er,
 tv,tr,tx,ty,tl,count,busy,done,fault,mr,mw,ma,md,mem_ready,mq);
ua_hand_scratch_ram memory(clk,mr && mem_ready,mw && mem_ready,ma,md,mq);
reg[14:0]hull[0:319],expected[0:6];reg[30:0]edges[0:319];reg[2047:0]path;
integer f,rc,jobs=0,ticks=0,cxx,cyy,r,wxx,wyy,h,e,n,abort_stage,i,x,y,xa,ya,xb,yb,q,seen=0,checking=0;
reg held=0;reg[15:0]payload;
always @(posedge clk)begin
 rng<={rng[14:0],rng[15]^rng[13]^rng[12]^rng[10]};ticks=ticks+1;
 if(ticks>10000000)$fatal(1,"timeout");
 if((mr||mw) && (ma<9216 || ma>=9856))$fatal(1,"bounds");
 if(checking)begin
  if(held && (!tv || {tl,ty,tx}!==payload))$fatal(1,"unstable tip");
  held=tv && !tr;payload={tl,ty,tx};
  if(tv && tr)begin
   if(seen>=n || {ty,tx}!==expected[seen] || tl!==(seen==n-1))
    $fatal(1,"job %0d tip %0d got %0d,%0d expected %0d,%0d",jobs,seen,tx,ty,expected[seen][7:0],expected[seen][14:8]);
   seen=seen+1;
  end
 end else held=0;
end
task launch;
begin start=1;@(negedge clk);start=0;end endtask
task load;
begin
 for(i=0;i<h;i=i+1)begin
  while(!hr)@(negedge clk);hv=1;hl=i==h-1;hx=hull[i][7:0];hy=hull[i][14:8];
  @(negedge clk);hv=0;hl=0;
 end
 if(!h)begin while(!hr)@(negedge clk);hl=1;@(negedge clk);hl=0;end
 for(i=0;i<e;i=i+1)begin
  while(!er)@(negedge clk);ev=1;eq=edges[i][30];
  ax=edges[i][7:0];ay=edges[i][14:8];bx=edges[i][22:15];by=edges[i][29:23];
  @(negedge clk);ev=0;
 end
 while(!er)@(negedge clk);ee=1;@(negedge clk);ee=0;
end endtask
initial begin
 if(!$value$plusargs("INPUT=%s",path))$fatal(1,"input");f=$fopen(path,"r");if(!f)$fatal(1,"open");
 repeat(5)@(negedge clk);rst=1;
 while(!$feof(f))begin
  rc=$fscanf(f,"%d %d %d %d %d %d %d %d %d\n",cxx,cyy,r,wxx,wyy,h,e,n,abort_stage);
  if(rc!=9 || n>7)$fatal(1,"header");
  for(i=0;i<h;i=i+1)begin rc=$fscanf(f,"%d %d\n",x,y);hull[i]={7'(y),8'(x)};end
  for(i=0;i<e;i=i+1)begin rc=$fscanf(f,"%d %d %d %d %d\n",xa,ya,xb,yb,q);edges[i]={1'(q),7'(yb),8'(xb),7'(ya),8'(xa)};end
  for(i=0;i<n;i=i+1)begin rc=$fscanf(f,"%d %d\n",x,y);expected[i]={7'(y),8'(x)};end
  cx=cxx;cy=cyy;radius=r;wx=wxx;wy=wyy;
  if(abort_stage)begin
   launch();load();while(dut.state!=abort_stage)@(negedge clk);
   clear=1;@(negedge clk);clear=0;if(tv||busy||done)$fatal(1,"abort");
  end
  seen=0;checking=1;launch();load();while(!done)@(negedge clk);
  if(fault || seen!=n || count!=n)$fatal(1,"job %0d fault=%0d count=%0d/%0d seen=%0d",jobs,fault,count,n,seen);
  checking=0;@(negedge clk);jobs=jobs+1;
 end
 $display("HAND_TIP_CANDIDATES_PASS tests=%0d external=%0d cycles=%0d",jobs,EXTERNAL,ticks);$finish;
end
endmodule
