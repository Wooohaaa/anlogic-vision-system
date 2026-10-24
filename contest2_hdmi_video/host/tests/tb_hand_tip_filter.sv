`timescale 1ns/1ps
module tb_hand_tip_filter #(parameter PARALLEL_COMPARE=0);
reg clk=0;always #5 clk=~clk;
reg rst=0,clear=0,start=0,tv=0,te=0,probe_valid=0,probe_pixel=0;
reg[7:0]w,cx,tx;reg[6:0]h,cy,ty;reg[10:0]radius;reg signed[9:0]wx,wy;
wire ready,tr,probe,busy,done,fault;wire[7:0]px;wire[6:0]py;wire[1:0]raw;wire[2:0]count;
reg[15:0]rng=16'h6713;wire probe_ready=rng[1:0]!=0;
ua_hand_tip_filter #(.PARALLEL_COMPARE(PARALLEL_COMPARE)) dut(clk,rst,clear,start,w,cx,h,cy,radius,wx,wy,tv,te,tx,ty,ready,tr,
 probe,px,py,probe_ready,probe_valid,probe_pixel,busy,done,fault,raw,count);
reg mask[0:14399];reg[14:0]tips[0:6];reg[2047:0]path;
integer f,rc,jobs=0,ticks=0,ww,hh,cxx,cyy,rr,wxx,wyy,n,expected_raw,expected_count,abort_stage;
integer i,x,y,pixel,pending=0,address=0,delay_cycles=0;
reg held=0;reg[14:0]held_coordinate;
always @(posedge clk)begin
 rng<={rng[14:0],rng[15]^rng[13]^rng[12]^rng[10]};ticks=ticks+1;probe_valid<=0;
 if(ticks>10000000)$fatal(1,"timeout");
 if(held && (!probe || {py,px}!==held_coordinate))$fatal(1,"probe not held under stall");
 held=probe && !probe_ready && !clear;held_coordinate={py,px};
 if(probe && probe_ready)begin
  if(pending || px>=w || py>=h)$fatal(1,"probe overlap/bounds");
  pending=1;address=py*w+px;delay_cycles=1+rng[2:0];
 end
 if(pending)begin
  if(!delay_cycles)begin pending=0;probe_valid<=1;probe_pixel<=mask[address];end
  else delay_cycles=delay_cycles-1;
 end
end
task launch;
begin while(!ready)@(negedge clk);start=1;@(negedge clk);start=0;end endtask
task load;
begin
 for(i=0;i<n;i=i+1)begin
  while(!tr)@(negedge clk);tv=1;te=i==n-1;tx=tips[i][7:0];ty=tips[i][14:8];@(negedge clk);tv=0;te=0;
 end
 if(!n)begin while(!tr)@(negedge clk);te=1;@(negedge clk);te=0;end
end endtask
initial begin
 if(!$value$plusargs("INPUT=%s",path))$fatal(1,"input");f=$fopen(path,"r");if(!f)$fatal(1,"open");
 repeat(5)@(negedge clk);rst=1;
 while(!$feof(f))begin
  rc=$fscanf(f,"%d %d %d %d %d %d %d %d %d %d %d\n",ww,hh,cxx,cyy,rr,wxx,wyy,n,expected_raw,expected_count,abort_stage);
  if(rc!=11)$fatal(1,"header");
  for(i=0;i<ww*hh;i=i+1)begin rc=$fscanf(f,"%d ",pixel);if(rc!=1)$fatal(1,"mask");mask[i]=pixel;end
  for(i=0;i<n;i=i+1)begin rc=$fscanf(f,"%d %d\n",x,y);tips[i]={7'(y),8'(x)};end
  w=ww;h=hh;cx=cxx;cy=cyy;radius=rr;wx=wxx;wy=wyy;
  if(abort_stage)begin
   launch();load();while(!pending)@(negedge clk);
   clear=1;@(negedge clk);clear=0;
   if(busy||done||probe)$fatal(1,"clear incomplete");
   while(!ready)@(negedge clk);
  end
  launch();load();while(!done)@(negedge clk);
  if(fault || raw!=expected_raw || count!=expected_count)
   $fatal(1,"job %0d raw=%0d/%0d count=%0d/%0d fault=%0d",jobs,raw,expected_raw,count,expected_count,fault);
  @(negedge clk);if(done)$fatal(1,"done pulse");jobs=jobs+1;
 end
 $display("HAND_TIP_FILTER_PASS tests=%0d cycles=%0d",jobs,ticks);$finish;
end
endmodule
