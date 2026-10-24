`timescale 1ns/1ps
module tb_hand_capture_rgb;
reg clk=0;always #5 clk=~clk;
reg rst=0,clear=0,valid=0,frame_done=0;reg[9:0]x=0,y=0;reg[95:0]rgb=0;
wire result_valid,box_valid,fault,drop;wire[1:0]id,raw;wire[2:0]tips;
wire[7:0]bx,bw;wire[6:0]by,bh;wire[31:0]cycles;
`ifdef HAND_BINARY
ua_hand_binary_native dut(clk,rst,clear,valid,frame_done,x,y,rgb,result_valid,id,raw,tips,box_valid,bx,bw,by,bh,fault,drop,cycles);
`else
ua_hand_native_classifier dut(clk,rst,clear,valid,frame_done,x,y,rgb,result_valid,id,raw,tips,box_valid,bx,bw,by,bh,fault,drop,cycles);
`endif
always @(posedge clk)if(rst && !clear)begin
 if(dut.front_input_fault && dut.state!=17)$display("CAPTURE_FAULT input state=%d x=%d y=%d",dut.state,x,y);
 if(dut.ccl_fault)$display("CAPTURE_FAULT CCL state=%d x=%d y=%d active=%h",dut.ccl.state,dut.ccl.x,dut.ccl.y,dut.ccl.active);
 if(dut.shape_fault)$display("CAPTURE_FAULT SHAPE state=%d",dut.shape.state);
end
reg[31:0]samples[0:57599];reg[4095:0]input_path,expected_path;
integer fd,ef,source_frame,bytes,rc,rr,cc,idx,repeat_id,wait_cycles,ei,er,eb,et,ex,ey,ew,eh;
function[95:0]reconstruct(input[9:0]r,g,b);
 integer k;reg[7:0]a,bb,c;
 begin for(k=0;k<4;k=k+1)begin
  a=(r>>2)+(k<r[1:0]);bb=(g>>2)+(k<g[1:0]);c=(b>>2)+(k<b[1:0]);
  reconstruct[95-k*24-:24]={a,bb,c};end end
endfunction
initial begin
 if(!$value$plusargs("INPUT=%s",input_path)||!$value$plusargs("EXPECTED=%s",expected_path)||
 !$value$plusargs("FRAME=%d",source_frame))$fatal(1,"paths");
 fd=$fopen(input_path,"rb");rc=$fseek(fd,source_frame*230400,0);bytes=$fread(samples,fd);$fclose(fd);
 if(bytes!=230400)$fatal(1,"short RGB input");ef=$fopen(expected_path,"r");
 repeat(5)@(negedge clk);rst=1;
 for(repeat_id=0;repeat_id<2;repeat_id=repeat_id+1)begin
  rc=$fscanf(ef,"%d %d %d %d %d %d %d %d\n",ei,er,eb,et,ex,ey,ew,eh);if(rc!=8)$fatal(1,"expected row");
`ifdef HAND_BINARY
  while(dut.state!=0 || !dut.shape_ready)@(negedge clk);
`else
  while(dut.state!=0 || !dut.assoc_ready || !dut.build_ready || !dut.frame_ready)@(negedge clk);
`endif
  for(rr=0;rr<180;rr=rr+1)begin
   for(cc=0;cc<320;cc=cc+1)begin
    @(negedge clk);valid=1;x=cc;y=rr*4+3;idx=rr*320+cc;
    rgb=reconstruct(samples[idx][29:20],samples[idx][19:10],samples[idx][9:0]);
    if(cc%73==0)begin @(negedge clk);valid=0;repeat(2)@(negedge clk);end
   end
   @(negedge clk);valid=0;repeat(4)@(negedge clk);
  end
  repeat(3)@(negedge clk);frame_done=1;@(negedge clk);frame_done=0;
  wait_cycles=0;
  while(!result_valid && wait_cycles<5000000)begin @(negedge clk);wait_cycles=wait_cycles+1;end
`ifdef HAND_BINARY
  if(!result_valid)$fatal(1,"binary native timeout state=%d ccl=%d shape=%d",dut.state,dut.ccl.state,dut.shape.state);
`else
  if(!result_valid)$fatal(1,"native timeout state=%d ccl=%d labels=%d builder=%d assoc=%d frame=%d",
   dut.state,dut.ccl.state,dut.labels.state,dut.builder.state,dut.association.state,dut.classifier.state);
`endif
  if(fault || id!=ei || raw!=er || box_valid!=eb || tips!=et || bx!=ex || by!=ey || bw!=ew || bh!=eh)
   $fatal(1,"native mismatch frame=%d repeat=%d fault=%d id=%d/%d raw=%d/%d box=%d/%d tips=%d/%d bbox=%d,%d,%d,%d/%d,%d,%d,%d",
    source_frame,repeat_id,fault,id,ei,raw,er,box_valid,eb,tips,et,bx,by,bw,bh,ex,ey,ew,eh);
  $display("NATIVE_FRAME_PASS source=%d repeat=%d cycles=%d raw=%d id=%d",source_frame,repeat_id,cycles,raw,id);
  @(negedge clk);
 end
 $display("HAND_NATIVE_RGB_CLASSIFIER_PASS");$finish;
end
endmodule
