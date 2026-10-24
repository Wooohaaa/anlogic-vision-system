`timescale 1ns/1ps
// Real RGB source never waits for the classifier. No injected masks/states.
module tb_hand_binary_stream;
reg clk=0;always #5 clk=~clk;
reg rst=0,valid=0,frame_done=0;reg[9:0]x=0,y=0;reg[95:0]rgb=0;
wire result,box,fault,drop;wire[1:0]id,raw;wire[2:0]tips;
wire[7:0]bx,bw;wire[6:0]by,bh;wire[31:0]cycles;
ua_hand_binary_native dut(clk,rst,1'b0,valid,frame_done,x,y,rgb,result,id,raw,tips,box,bx,bw,by,bh,fault,drop,cycles);
`ifdef COMPARE_V47
wire ref_result,ref_box,ref_fault,ref_drop;wire[1:0]ref_id,ref_raw;wire[2:0]ref_tips;
wire[7:0]ref_x,ref_w;wire[6:0]ref_y,ref_h;wire[31:0]ref_cycles;
v47_ua_hand_binary_native reference_core(clk,rst,1'b0,valid,frame_done,x,y,rgb,
 ref_result,ref_id,ref_raw,ref_tips,ref_box,ref_x,ref_w,ref_y,ref_h,ref_fault,ref_drop,ref_cycles);
always @(negedge clk)if(rst)
 if({result,id,raw,tips,box,bx,bw,by,bh,fault,drop,cycles}!==
    {ref_result,ref_id,ref_raw,ref_tips,ref_box,ref_x,ref_w,ref_y,ref_h,ref_fault,ref_drop,ref_cycles})
  $fatal(1,"Resource-compact core differs from frozen v47 at time=%t",$time);
`endif
reg[31:0]samples[0:172799];reg[4095:0]path;
integer fd,rc,n,rr,cc,source,idx,cls,accepted=0,completed=0,dropped=0,ticks=0;
function[95:0]rgb4(input[9:0]r,g,b);
 integer k;reg[7:0]a,bb,c;
 begin for(k=0;k<4;k=k+1)begin
  a=(r>>2)+(k<r[1:0]);bb=(g>>2)+(k<g[1:0]);c=(b>>2)+(k<b[1:0]);
  rgb4[95-k*24-:24]={a,bb,c};end end
endfunction
always @(negedge clk)begin
 if(dut.native_valid && dut.state!=0)$display("STREAM_NATIVE_OWNER_COLLISION state=%d address=%d",dut.state,dut.native_address);
 if(dut.shape_done && (dut.shape_fault || dut.shape_area!=dut.candidate_area))$display("STREAM_COMPONENT_FAULT area=%d descriptor=%d fault=%d",dut.shape_area,dut.candidate_area,dut.shape_fault);
 if(dut.ccl_done && dut.ccl_fault)$display("STREAM_CCL_FAULT");
 if(drop)dropped=dropped+1;
 if(result)begin
  completed=completed+1;
  if(fault)$fatal(1,"stream fault");
  $display("STREAM_RESULT id=%d raw=%d box=%d tips=%d x=%d y=%d w=%d h=%d",id,raw,box,tips,bx,by,bw,bh);
 end
end
initial begin
 if(!$value$plusargs("INPUT=%s",path))$fatal(1,"path");
 fd=$fopen(path,"rb");
 rc=$fseek(fd,130*230400,0);n=$fread(samples,fd,0,57600);if(n!=230400)$fatal(1,"fist bytes");
 rc=$fseek(fd,180*230400,0);n=$fread(samples,fd,57600,57600);if(n!=230400)$fatal(1,"open bytes");
 rc=$fseek(fd,0,0);n=$fread(samples,fd,115200,57600);if(n!=230400)$fatal(1,"none bytes");
 $fclose(fd);repeat(5)@(negedge clk);rst=1;
 for(source=0;source<96;source=source+1)begin
  cls=source/32;
  for(rr=0;rr<180;rr=rr+1)begin
   for(cc=0;cc<320;cc=cc+1)begin
    @(negedge clk);
    // x=0,y=7 was consumed on the preceding rising edge.
    if(rr==1 && cc==1 && dut.frontend.capture_active)begin
     accepted=accepted+1;$display("STREAM_ACCEPT class=%d source=%d",cls,source);
    end
    valid=1;x=cc;y=rr*4+3;idx=cls*57600+rr*320+cc;
    rgb=rgb4(samples[idx][29:20],samples[idx][19:10],samples[idx][9:0]);
   end
   @(negedge clk);valid=0;repeat(4)@(negedge clk);
  end
  repeat(3)@(negedge clk);frame_done=1;@(negedge clk);frame_done=0;
 end
 ticks=0;
 while((completed<accepted || dut.state!=0) && ticks<5000000)begin @(negedge clk);ticks=ticks+1;end
 if(completed!=accepted || accepted<12 || dropped==0)$fatal(1,"stream lost results a=%d c=%d drop=%d",accepted,completed,dropped);
 $display("HAND_BINARY_CONTINUOUS_RGB_PASS accepted=%d completed=%d dropped=%d",accepted,completed,dropped);$finish;
end
initial begin #200000000;$fatal(1,"stream timeout");end
endmodule
