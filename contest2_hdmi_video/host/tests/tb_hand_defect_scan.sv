`timescale 1ns/1ps
module tb_hand_defect_scan;
parameter EXTERNAL=1;
reg clk=0;always #5 clk=~clk;
reg rst=0,clear=0,start=0,hv=0,hl=0,cv=0,cl=0,er=0;
reg[7:0]hx,cx;reg[6:0]hy,cy;reg[10:0]radius;
wire hr,cr,ev,busy,done,fault,qual,has,mr,mw;
wire[7:0]ax,bx,fx;wire[6:0]ay,by,fy;wire[19:0]cross_value;wire[9:0]length;
wire[8:0]hc;wire[13:0]cc,ma;wire[31:0]cycles;wire[15:0]md,mq;
reg[15:0]rng=16'h8d17;wire mem_ready=EXTERNAL ? rng[1:0]!=0 : 1'b1;
ua_hand_defect_scan #(.EXTERNAL_MEMORY(EXTERNAL)) dut(
 clk,rst,clear,start,radius,hv,hl,hx,hy,hr,cv,cl,cx,cy,cr,ev,er,
 ax,bx,ay,by,qual,has,fx,fy,cross_value,length,busy,done,fault,hc,cc,cycles,mr,mw,ma,md,mem_ready,mq);
ua_hand_scratch_ram external_memory(clk,mr && mem_ready,mw && mem_ready,ma,md,mq);
reg[2047:0]path;
integer file,rc,jobs=0,ticks=0,i,n,h,e,r,invalid,abort_stage,observed=0,checking=0;
integer x,y,ea,eb,ec,ed,eq,eh,ex,ey,em,el;
reg[14:0]hp[0:320],cp[0:8192];reg[127:0]expected[0:320];
reg held=0;reg[76:0]payload;
wire[76:0]result_payload={ax,bx,ay,by,qual,has,fx,fy,cross_value,length};
always @(posedge clk)begin
 rng<={rng[14:0],rng[15]^rng[13]^rng[12]^rng[10]};ticks=ticks+1;
 if(ticks>40000000)$fatal(1,"timeout");
 if((mr || mw) && ma>=14400)$fatal(1,"memory bounds");
 if(mr && mw)$fatal(1,"memory collision");
 if(checking)begin
  if(held && (!ev || result_payload!==payload))$fatal(1,"edge not held");
  held=ev && !er;payload=result_payload;
  if(ev && er)begin
   if(observed>=e || result_payload!==expected[observed][76:0])
    $fatal(1,"job %0d edge %0d got %h expected %h",jobs,observed,result_payload,expected[observed][76:0]);
   observed=observed+1;
  end
 end else held=0;
end
always @(negedge clk)er=rng[3:0]!=0;
task launch;
begin start=1;@(negedge clk);start=0;end endtask
task load;
begin
 for(i=0;i<h;i=i+1)begin
  while(!hr)@(negedge clk);
  hv=1;hl=i==h-1;hx=hp[i][7:0];hy=hp[i][14:8];
  @(posedge clk);while(!hr)@(posedge clk);
  @(negedge clk);hv=0;hl=0;
 end
 if(!h)begin while(!hr)@(negedge clk);hl=1;@(posedge clk);while(!hr)@(posedge clk);@(negedge clk);hl=0;end
 for(i=0;i<n;i=i+1)begin
  while(!cr)@(negedge clk);
  cv=1;cl=i==n-1;cx=cp[i][7:0];cy=cp[i][14:8];
  @(posedge clk);while(!cr)@(posedge clk);
  @(negedge clk);cv=0;cl=0;
 end
 if(!n)begin while(!cr)@(negedge clk);cl=1;@(posedge clk);while(!cr)@(posedge clk);@(negedge clk);cl=0;end
end endtask
initial begin
 if(!$value$plusargs("INPUT=%s",path))$fatal(1,"input");file=$fopen(path,"r");if(!file)$fatal(1,"open");
 repeat(5)@(negedge clk);rst=1;
 while(!$feof(file))begin
  rc=$fscanf(file,"%d %d %d %d %d %d\n",h,n,r,e,invalid,abort_stage);if(rc!=6)$fatal(1,"header");
  for(i=0;i<h;i=i+1)begin rc=$fscanf(file,"%d %d\n",x,y);hp[i]={7'(y),8'(x)};end
  for(i=0;i<n;i=i+1)begin rc=$fscanf(file,"%d %d\n",x,y);cp[i]={7'(y),8'(x)};end
  for(i=0;i<e;i=i+1)begin
   rc=$fscanf(file,"%d %d %d %d %d %d %d %d %d %d\n",ea,eb,ec,ed,eq,eh,ex,ey,em,el);
   if(rc!=10)$fatal(1,"expected");
   expected[i]={8'(ea),8'(ec),7'(eb),7'(ed),1'(eq),1'(eh),8'(ex),7'(ey),20'(em),10'(el)};
  end
  radius=r;
  if(abort_stage)begin
   launch();load();
   while(dut.state!=abort_stage)@(negedge clk);
   clear=1;@(negedge clk);clear=0;
   if(busy || ev || done)$fatal(1,"abort failed");
  end
  observed=0;checking=!invalid;launch();load();while(!done)@(negedge clk);
  if(fault!==(invalid!=0) || (!invalid && (observed!=e || hc!=h || cc!=n)))
   $fatal(1,"job %0d fault %0d/%0d edges %0d/%0d counts %0d,%0d/%0d,%0d",jobs,fault,invalid,observed,e,hc,cc,h,n);
  checking=0;@(negedge clk);if(done)$fatal(1,"done not pulse");jobs=jobs+1;
 end
 $display("HAND_DEFECT_SCAN_PASS tests=%0d external=%0d cycles=%0d",jobs,EXTERNAL,ticks);$finish;
end
endmodule
