`timescale 1ns/1ps
module tb_hand_frame_classifier_faults;
parameter EXTERNAL_SCRATCH=0;
reg clk=0;always #5 clk=~clk;
reg rst=0,clear=0,start=0,cv=0,finish=0,mode=1,rv=0;
reg[7:0]x=50,w=46,ax=50;reg[6:0]y=44,h=46,ay=44;
reg[13:0]area=1546,bright=0;reg[23:0]sum=247360;reg[17:0]data;
wire ready,cr,read,busy,done,fault,box_valid,backlit;wire[11:0]address;
wire[1:0]id,raw;wire[2:0]tips;wire[7:0]bx,bw;wire[6:0]by,bh;wire[10:0]radius;wire[9:0]mean;
reg sr=0,sw=0;reg[13:0]sa=0;reg[15:0]sd=0;wire sready,sv;wire[15:0]sq;
ua_hand_frame_classifier #(.EXTERNAL_SCRATCH(EXTERNAL_SCRATCH)) dut(clk,rst,clear,start,cv,finish,mode,x,w,ax,y,h,ay,area,sum,bright,
 ready,cr,read,address,rv,data,busy,done,fault,id,raw,box_valid,tips,bx,bw,by,bh,radius,mean,backlit,
 sr,sw || (EXTERNAL_SCRATCH && busy),sa,sd,sready,sv,sq);
reg[31:0]packed_mask[0:2429];reg[17:0]mask[0:2429];reg[2047:0]mp;
integer file,bytes,i,j,stage,pending=0,saved=0,delay_cycles=0,ticks=0,jobs=0;
always @(posedge clk)begin
 rv<=0;ticks=ticks+1;
 if(busy && (sready || sv))$fatal(1,"frame leaked scratch ownership");
 if(ticks>6000000)$fatal(1,"timeout stage=%0d state=%0d shape=%0d policy=%0d",stage,dut.state,dut.shape.state,dut.policy.state);
 if(read)begin
  if(pending || address>=2430)$fatal(1,"read protocol");
  pending=1;saved=address;delay_cycles=4;
 end
 if(pending)begin
  if(!delay_cycles)begin pending=0;rv<=1;data<=mask[saved];end
  else delay_cycles=delay_cycles-1;
 end
end
task begin_frame;
begin while(!ready)@(negedge clk);start=1;@(negedge clk);start=0;end endtask
task candidate;
begin while(!cr)@(negedge clk);cv=1;@(negedge clk);cv=0;end endtask
task end_frame;
begin while(!cr)@(negedge clk);finish=1;@(negedge clk);finish=0;while(!done)@(negedge clk);jobs=jobs+1;end endtask
task check_fist(input integer expected_id);
begin
 begin_frame();candidate();end_frame();
 if(fault || raw!=1 || id!=expected_id || box_valid!==(expected_id!=0) || mean!=160 || bx!=50 || by!=44 || bw!=46 || bh!=46)
  $fatal(1,"fist recovery id=%0d/%0d raw=%0d fault=%0d",id,expected_id,raw,fault);
 @(negedge clk);
end endtask
initial begin
 if(!$value$plusargs("MASK=%s",mp))$fatal(1,"mask");file=$fopen(mp,"rb");bytes=$fread(packed_mask,file);if(bytes!=9720)$fatal(1,"mask bytes");
 for(i=0;i<2430;i=i+1)mask[i]=packed_mask[i][17:0];
 repeat(5)@(negedge clk);rst=1;
 if(EXTERNAL_SCRATCH)begin
  for(i=0;i<14400;i=i+1)begin
   sa=i;sd=(i*29)^16'h7351;sw=1;start=1;#1;
   if(!sready || ready || busy)$fatal(1,"frame write/start arbitration %0d",i);
   @(negedge clk);
  end
  sw=0;start=0;
  for(i=0;i<14400;i=i+1)begin
   sa=i;sr=1;#1;if(!sready || ready)$fatal(1,"frame read grant");
   @(negedge clk);sr=0;
   if(!sv || ready || sq!==(((i*29)^16'h7351)&16'hffff))$fatal(1,"frame scratch response %0d",i);
   @(negedge clk);if(sv)$fatal(1,"frame response not pulse");
  end
  sa=0;sr=1;@(negedge clk);sr=0;clear=1;#1;
  if(sv || sready)$fatal(1,"frame clear response leak");
  @(negedge clk);clear=0;@(negedge clk);if(sv)$fatal(1,"frame stale response");
 end
 check_fist(0);check_fist(1);
 for(i=0;i<5;i=i+1)begin
  begin_frame();end_frame();
  if(fault || raw || box_valid || id!=(i<4 ? 1 : 0))$fatal(1,"withdraw %0d",i);
  @(negedge clk);
 end
 // CCL/geometry area disagreement must invalidate the entire frame.
 area=1547;begin_frame();candidate();while(!done)@(negedge clk);
 if(!fault || id || box_valid)$fatal(1,"missing area fault");jobs=jobs+1;@(negedge clk);area=1546;
 check_fist(0);check_fist(1);
 for(stage=0;stage<4;stage=stage+1)begin
  if(stage==1)begin
   // A plain closed palm may have no width-test candidate at all. Add an
   // actual thin finger to reach and cancel a real bitmap width response.
   for(i=10;i<44;i=i+1)for(j=50;j<55;j=j+1)mask[i*27+j/6][(j%6)*3 +:3]=3'b101;
   y=10;h=80;ay=10;area=1716;sum=274560;
  end
  begin_frame();candidate();
  case(stage)
  0:while(!pending)@(negedge clk);
  1:while(!dut.shape.probe_pending)@(negedge clk);
  2:while(dut.policy.state!=5)@(negedge clk);
  3:begin while(!cr)@(negedge clk);finish=1;@(negedge clk);finish=0;while(dut.state!=8)@(negedge clk);end
  endcase
  clear=1;@(negedge clk);clear=0;
  if(busy || done || fault || id || raw || box_valid || backlit)$fatal(1,"clear failed stage %0d",stage);
  if(stage==1)begin
   for(i=0;i<2430;i=i+1)mask[i]=packed_mask[i][17:0];
   y=44;h=46;ay=44;area=1546;sum=247360;
  end
  check_fist(0);check_fist(1);
 end
 $display("HAND_FRAME_CLASSIFIER_FAULTS_PASS frames=%0d clear_stages=4",jobs);$finish;
end
endmodule
