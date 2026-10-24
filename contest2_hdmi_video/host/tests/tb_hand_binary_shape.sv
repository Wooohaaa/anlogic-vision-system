`timescale 1ns/1ps
module tb_hand_binary_shape;
parameter MAX_CYCLES=4000000;
reg clk=0;always #5 clk=~clk;
reg rst=0,clear=0,start=0,mode=0,rv=0,sr=0,sw=0;reg[17:0]rd=0;
reg[7:0]x,w,ax;reg[6:0]y,h,ay;reg[13:0]sa=0;reg[15:0]sd=0;
wire ready,read,busy,done,fault,sready,sv;wire[11:0]ra;wire[1:0]raw;wire[13:0]area;wire[6:0]rows;wire[31:0]cycles;wire[15:0]sq;
ua_hand_binary_shape #(.MAX_CYCLES(MAX_CYCLES)) dut(clk,rst,clear,start,mode,x,w,ax,y,h,ay,
 ready,read,ra,rv,rd,busy,done,fault,raw,area,rows,cycles,sr,sw || busy,sa,sd,sready,sv,sq);
reg[17:0]source[0:2429];reg[4095:0]path;
reg[15:0]rng=16'h91e7;
integer pending=0,saved=0,delay_cycles=0,ticks=0,expected_raw,expected_rows,expected_area,abort_stage=0,expected_fault=0;
integer ix,iy,iw,ih,iax,iay,im,i;
always @(posedge clk)begin
 rv<=0;rng<={rng[14:0],rng[15]^rng[13]^rng[12]^rng[10]};ticks=ticks+1;
 if(ticks>2000000)$fatal(1,"binary shape timeout");
 if(read)begin if(pending || ra>=2430)$fatal(1,"source protocol");pending=1;saved=ra;delay_cycles=1+rng[2:0];end
 if(pending)begin
  if(delay_cycles==0)begin rv<=1;rd<=source[saved];pending=0;end else delay_cycles=delay_cycles-1;
 end
 if(busy && sready)$fatal(1,"scratch granted during classification");
end
task launch;
begin
 while(!ready)@(negedge clk);
 x=ix;y=iy;w=iw;h=ih;ax=iax;ay=iay;mode=im;start=1;@(negedge clk);start=0;
 x=0;y=0;w=0;h=0;ax=0;ay=0;mode=!im;
end endtask
initial begin
 if(!$value$plusargs("MASK=%s",path)||!$value$plusargs("X=%d",ix)||!$value$plusargs("Y=%d",iy)||
 !$value$plusargs("W=%d",iw)||!$value$plusargs("H=%d",ih)||!$value$plusargs("AX=%d",iax)||!$value$plusargs("AY=%d",iay)||
 !$value$plusargs("MODE=%d",im)||!$value$plusargs("RAW=%d",expected_raw)||!$value$plusargs("ROWS=%d",expected_rows)||!$value$plusargs("AREA=%d",expected_area))$fatal(1,"args");
 if($value$plusargs("ABORT=%d",abort_stage))begin end
 if($value$plusargs("FAULT=%d",expected_fault))begin end
 $readmemh(path,source);repeat(5)@(negedge clk);rst=1;
 // Boundary and readback check on the same physical scratch used by BFS.
 for(i=0;i<65;i=i+1)begin sa=i==64 ? 14399 : i*211;sd=i^16'h947a;sw=1;#1;
  if(!sready || ready)$fatal(1,"scratch write arbitration");@(negedge clk);sw=0;
  sr=1;#1;if(!sready)$fatal(1,"scratch read not ready");@(negedge clk);sr=0;
  if(!sv || sq!==(i^16'h947a))$fatal(1,"scratch mismatch");@(negedge clk);
 end
 if(abort_stage)begin
  launch();
  if(abort_stage==1)while(!pending)@(negedge clk);
  else if(abort_stage==2)while(!dut.cc_valid)@(negedge clk);
  else while(dut.state!=4)@(negedge clk);
  clear=1;@(negedge clk);clear=0;if(busy || done || read)$fatal(1,"clear incomplete");
 end
 launch();while(!done)@(negedge clk);
 if(fault!==(expected_fault!=0) || (!expected_fault && (raw!=expected_raw || area!=expected_area || rows!=expected_rows)))
  $fatal(1,"binary mismatch raw=%d/%d area=%d/%d rows=%d/%d fault=%d",raw,expected_raw,area,expected_area,rows,expected_rows,fault);
 @(negedge clk);if(done)$fatal(1,"done not pulse");
 $display("HAND_BINARY_SHAPE_PASS cycles=%d raw=%d rows=%d fault=%d",cycles,raw,rows,fault);$finish;
end
endmodule
