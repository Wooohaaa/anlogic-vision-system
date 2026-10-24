`timescale 1ns/1ps
module tb_hand_palm_distance;
parameter EXTERNAL=0;
reg clk=0;always #5 clk=~clk;
reg rst=0,clear=0,start=0,valid=0,mask=0,last=0;
reg[7:0] width;reg[6:0]height;
wire ready,busy,done,fault,has_palm,dv;wire[7:0]cx,dx;wire[6:0]cy,dy;
wire[10:0]radius,distance_q4;wire[31:0]cycles;
wire sr,sw;wire[13:0]sa;wire[15:0]sd,sq;
ua_hand_scratch_ram storage(clk,sr,sw,sa,sd,sq);
ua_hand_palm_distance #(.EXTERNAL_MEMORY(EXTERNAL)) dut(clk,rst,clear,start,width,height,valid,mask,last,
 ready,busy,done,fault,has_palm,cx,cy,radius,dv,dx,dy,distance_q4,cycles,sr,sw,sa,sd,sq);
reg[15:0] vectors[0:14399];reg seen[0:14399];
reg[2047:0] input_path;
integer w,h,expected_x,expected_y,expected_radius,bad_last,abort_stage,zero_reuse;
integer n,i,k,samples,waited,index,zero_mode=0;reg checking=0;
always @(posedge clk)begin
 #1;
 if(checking && dv)begin
  if(dx>=w || dy>=h)$fatal(1,"distance coordinates out of bounds %0d %0d",dx,dy);
  index=dy*w+dx;
  if(seen[index])$fatal(1,"duplicate output %0d",index);
  seen[index]=1;samples=samples+1;
  if(distance_q4!==(zero_mode ? 11'd0 : vectors[index][10:0]))
   $fatal(1,"distance mismatch x=%0d y=%0d expected=%0d actual=%0d",dx,dy,
      zero_mode ? 0 : vectors[index][10:0],distance_q4);
 end
end
task launch;
 begin
  @(negedge clk);start=1;
  @(negedge clk);start=0;
 end
endtask
task feed(input integer count);
 integer j;
 begin
  while(!ready && busy)@(negedge clk);
  for(j=0;j<count;j=j+1)begin
   if(j%17==3)begin @(negedge clk);valid=0;repeat(2)@(negedge clk);end
   if(!ready)$fatal(1,"loader not ready at %0d",j);
   valid=1;mask=zero_mode ? 0 : vectors[j][11];
   last=(bad_last==1 && j==0) || (bad_last!=2 && j==n-1);
   @(negedge clk);valid=0;last=0;
   if(bad_last==1 && j==0)j=count;
  end
 end
endtask
task abort_and_restart;
 begin
  checking=0;@(negedge clk);clear=1;valid=0;last=0;
  @(negedge clk);clear=0;
  if(busy||done||dv||ready)$fatal(1,"clear did not release transaction");
  samples=0;for(k=0;k<n;k=k+1)seen[k]=0;
  checking=1;launch();feed(n);
 end
endtask
task await_result;
 begin
  waited=0;
  while(!done && waited<600000)begin @(negedge clk);waited=waited+1;end
  if(!done)$fatal(1,"palm timeout");
  if(bad_last!=0)begin
   if(!fault||busy||has_palm)$fatal(1,"malformed stream not rejected");
  end else begin
   if(fault||busy||samples!=n)$fatal(1,"bad completion fault=%0d busy=%0d samples=%0d n=%0d",fault,busy,samples,n);
   if(cx!==(zero_mode ? 0 : expected_x) || cy!==(zero_mode ? 0 : expected_y) ||
      radius!==(zero_mode ? 0 : expected_radius) || has_palm!==(!zero_mode && expected_radius>=80))
    $fatal(1,"palm mismatch center=(%0d,%0d) R=%0d has=%0d expected=(%0d,%0d) R=%0d",cx,cy,radius,has_palm,
      zero_mode ? 0 : expected_x,zero_mode ? 0 : expected_y,zero_mode ? 0 : expected_radius);
   $display("PALM_RESULT width=%0d height=%0d pixels=%0d cx=%0d cy=%0d radius=%0d cycles=%0d zero=%0d",w,h,n,cx,cy,radius,cycles,zero_mode);
  end
 end
endtask
initial begin
 bad_last=0;abort_stage=0;zero_reuse=0;
 if(!$value$plusargs("INPUT=%s",input_path))$fatal(1,"missing input");
 if(!$value$plusargs("W=%d",w)||!$value$plusargs("H=%d",h)||
    !$value$plusargs("CX=%d",expected_x)||!$value$plusargs("CY=%d",expected_y)||
    !$value$plusargs("R=%d",expected_radius))$fatal(1,"missing geometry");
 if($value$plusargs("BAD_LAST=%d",bad_last))begin end
 if($value$plusargs("ABORT=%d",abort_stage))begin end
 if($value$plusargs("ZERO_REUSE=%d",zero_reuse))begin end
 width=w;height=h;n=w*h;samples=0;
 $readmemh(input_path,vectors,0,n-1);for(i=0;i<n;i=i+1)seen[i]=0;
 repeat(4)@(negedge clk);rst=1;checking=1;launch();
 if(abort_stage==1)begin feed(n/2);abort_and_restart();end
 else begin
  feed(n);
  if(abort_stage==2)begin repeat(20)@(negedge clk);abort_and_restart();end
 end
 await_result();
 if(zero_reuse && !bad_last)begin
  @(negedge clk);checking=0;zero_mode=1;samples=0;
  for(i=0;i<n;i=i+1)seen[i]=0;
  checking=1;launch();feed(n);await_result();
 end
 $display("HAND_PALM_DISTANCE_PASS bad_last=%0d abort=%0d",bad_last,abort_stage);$finish;
end
endmodule
