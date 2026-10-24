`timescale 1ns/1ps
module tb_hand_frame_policy;
reg clk=0;always #5 clk=~clk;
reg rst=0,clear=0,start=0,cv=0,finish=0;
reg[7:0]x,w,cx;reg[6:0]y,h,cy;reg[13:0]area,bright;reg[23:0]redsum;
reg[10:0]radius;reg[1:0]raw;reg[2:0]tips;
wire ready,cr,busy,done,fault,backlit,bv;wire[1:0]br;wire[2:0]bt;
wire[7:0]bx,bw,bcx;wire[6:0]by,bh,bcy;wire[13:0]ba;wire[10:0]brr;wire[9:0]mean;wire[26:0]score;
ua_hand_frame_policy dut(clk,rst,clear,start,cv,finish,x,w,cx,y,h,cy,area,redsum,radius,raw,tips,bright,
 ready,cr,busy,done,fault,backlit,bv,br,bt,bx,bw,bcx,by,bh,bcy,ba,brr,mean,score);
reg[2047:0]path;reg[15:0]rng=16'h8135;
integer file,rc,jobs=0,i,n,b,ev,er,et,ex,ey,ew,eh,ecx,ecy,ea,err,em,es,eb,abort_stage;
integer ix,iy,iw,ih,icx,icy,ia,irs,ir,iraw,it,ticks=0;
integer data[0:31][0:10];
always @(posedge clk)begin
 rng<={rng[14:0],rng[15]^rng[13]^rng[12]^rng[10]};ticks=ticks+1;
 if(ticks>10000000)$fatal(1,"timeout");
end
task launch;
begin while(!ready)@(negedge clk);start=1;@(negedge clk);start=0;end endtask
task load;
begin
 for(i=0;i<n;i=i+1)begin
  while(!cr)@(negedge clk);repeat(rng[1:0])@(negedge clk);
  x=data[i][0];y=data[i][1];w=data[i][2];h=data[i][3];cx=data[i][4];cy=data[i][5];
  area=data[i][6];redsum=data[i][7];radius=data[i][8];raw=data[i][9];tips=data[i][10];
  cv=1;@(negedge clk);cv=0;
  // Pins may change immediately after transfer, all context must be latched.
  x=0;y=0;w=0;h=0;area=0;redsum=0;radius=0;raw=0;tips=0;
 end
end endtask
initial begin
 if(!$value$plusargs("INPUT=%s",path))$fatal(1,"input");file=$fopen(path,"r");if(!file)$fatal(1,"open");
 repeat(5)@(negedge clk);rst=1;
 while(!$feof(file))begin
  rc=$fscanf(file,"%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",n,b,ev,er,et,ex,ey,ew,eh,ecx,ecy,ea,err,em,es,eb,abort_stage);
  if(rc!=17 || n>32)$fatal(1,"header");
  for(i=0;i<n;i=i+1)begin
   rc=$fscanf(file,"%d %d %d %d %d %d %d %d %d %d %d\n",ix,iy,iw,ih,icx,icy,ia,irs,ir,iraw,it);
   if(rc!=11)$fatal(1,"candidate");
   data[i][0]=ix;data[i][1]=iy;data[i][2]=iw;data[i][3]=ih;data[i][4]=icx;data[i][5]=icy;
   data[i][6]=ia;data[i][7]=irs;data[i][8]=ir;data[i][9]=iraw;data[i][10]=it;
  end
  if(abort_stage)begin
   launch();load();while(dut.state!=abort_stage)@(negedge clk);
   clear=1;@(negedge clk);clear=0;
   if(busy || done || bv)$fatal(1,"clear");
  end
  launch();load();while(!cr)@(negedge clk);bright=b;finish=1;@(negedge clk);finish=0;
  while(!done)@(negedge clk);
  if(fault || bv!==ev[0] || backlit!==eb[0] || (ev &&
   (br!=er || bt!=et || bx!=ex || by!=ey || bw!=ew || bh!=eh || bcx!=ecx || bcy!=ecy || ba!=ea || brr!=err || mean!=em || score!=es)))
   $fatal(1,"job %0d valid=%0d/%0d raw=%0d/%0d mean=%0d/%0d score=%0d/%0d backlit=%0d/%0d fault=%0d",jobs,bv,ev,br,er,mean,em,score,es,backlit,eb,fault);
  @(negedge clk);if(done)$fatal(1,"done pulse");jobs=jobs+1;
 end
 $display("HAND_FRAME_POLICY_PASS tests=%0d cycles=%0d",jobs,ticks);$finish;
end
endmodule
