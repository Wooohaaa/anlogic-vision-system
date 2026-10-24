`timescale 1ns/1ps
module tb_hand_mask_frame;
 reg clk=0,rst=0,clear=0,valid=0,done=0,release_mask=0,read=0;
 always #5 clk=~clk;
 reg[9:0]x=0,y=0;reg[95:0]rgb=0;reg[11:0]ra=0;
 wire mv,bank,rv,drop,fault;wire[15:0]fid;wire[17:0]rd;wire[31:0]cycles;
 wire nv,nb,nbright;wire[13:0]na;wire[9:0]nr;
 wire memory_read;wire[11:0]memory_addr;
`ifdef HAND_CHAIN
 reg run_ccl=0,ccl_start=0,run_trace=0,trace_start=0;
 wire ccl_read,ccl_busy,ccl_done,ccl_overflow,blob;
 wire[11:0]ccl_addr;wire[13:0]area,seeds;wire[7:0]xmin,xmax,anchor_x;wire[6:0]ymin,ymax,anchor_y;
 wire unused_red_read;wire[13:0]unused_red_addr;wire[23:0]unused_red_sum;
`ifdef HAND_SHARED_RED
 wire red_ready,red_valid;wire[15:0]red_data;
 // Actual frontend samples and CCL requests use the classifier's existing
 // geometry scratch, not a testbench-created red array.
 ua_hand_shape_classifier #(.EXTERNAL_SCRATCH(1)) red_storage(
  .I_clk(clk),.I_rst_n(rst),.I_clear(clear),.I_start(1'b0),.I_mode(1'b0),
  .I_xmin(8'd0),.I_width(8'd0),.I_anchor_x(8'd0),.I_ymin(7'd0),.I_height(7'd0),.I_anchor_y(7'd0),
  .I_read_valid(1'b0),.I_read_data(18'd0),
  .I_scratch_read(unused_red_read),.I_scratch_write(nv),
  .I_scratch_address(nv ? na : unused_red_addr),.I_scratch_data({6'd0,nr}),
  .O_scratch_ready(red_ready),.O_scratch_valid(red_valid),.O_scratch_data(red_data));
 always @(posedge clk)if(rst && !clear && (nv || unused_red_read) && !red_ready)
  $fatal(1,"native red capture/CCL scratch request lost");
`endif
 reg[13:0]best_area=0;reg[7:0]best_x=0;reg[6:0]best_y=0;
 wire trace_read,trace_busy,trace_done,trace_fault,vertex;
 wire[11:0]trace_addr;wire[7:0]vertex_x;wire[6:0]vertex_y;wire[13:0]point_count;
 assign memory_read=run_trace ? trace_read : run_ccl ? ccl_read : read;
 assign memory_addr=run_trace ? trace_addr : run_ccl ? ccl_addr : ra;
 ua_hand_blob_scan #(.RGB_STATS(
`ifdef HAND_SHARED_RED
  1
`else
  0
`endif
 )) ccl(clk,rst,clear,ccl_start,1'b1,ccl_read,ccl_addr,
  rv&&run_ccl,rd,ccl_busy,ccl_done,ccl_overflow,blob,area,seeds,xmin,xmax,ymin,ymax,anchor_x,anchor_y,
  unused_red_read,unused_red_addr,
`ifdef HAND_SHARED_RED
  red_valid,red_data[9:0],
`else
  1'b0,10'd0,
`endif
  unused_red_sum);
 ua_hand_contour_trace trace_core(clk,rst,clear,trace_start,1'b1,best_x,best_y,
  trace_read,trace_addr,rv&&run_trace,rd,trace_busy,trace_done,trace_fault,vertex,vertex_x,vertex_y,point_count);
 always @(posedge clk)begin
  #1;
  if(blob)begin
   $display("CHAIN_BLOB %0d %0d %0d %0d %0d %0d %0d %0d",area,seeds,xmin,xmax,ymin,ymax,anchor_x,anchor_y);
`ifdef HAND_SHARED_RED
   $display("CHAIN_RED %0d %0d %0d %0d",area,anchor_x,anchor_y,unused_red_sum);
`endif
   if(area>best_area)begin best_area=area;best_x=anchor_x;best_y=anchor_y;end
  end
  if(vertex)$display("CHAIN_VERTEX %0d %0d",vertex_x,vertex_y);
 end
`else
 assign memory_read=read;assign memory_addr=ra;
`endif
 ua_hand_mask_frame dut(clk,rst,clear,valid,done,x,y,rgb,mv,bank,fid,release_mask,memory_read,memory_addr,rv,rd,drop,fault,cycles,
  1'b1,nv,nb,nbright,na,nr);
 reg[31:0] samples[0:57599];reg[17:0] expected[0:2429];
 reg[4095:0] input_path,expected_path;integer fd,start=0,bytes,result,rr,cc,idx,word_id,wait_cycles,checked=0;
 integer native_count=0,ni,nr_expected,ng_expected,nb_expected;reg native_bank;
 always @(posedge clk)begin
  #1;
  if(rst&&!clear&&nv)begin
   if(na!=native_count || na>=14400)$fatal(1,"native sample ordering");
   ni=(na/160*2+1)*320+(na%160)*2;
   nr_expected=({1'b0,samples[ni][29:20]}+{1'b0,samples[ni+1][29:20]})>>1;
   ng_expected=({1'b0,samples[ni][19:10]}+{1'b0,samples[ni+1][19:10]})>>1;
   nb_expected=({1'b0,samples[ni][9:0]}+{1'b0,samples[ni+1][9:0]})>>1;
   if(nr!=nr_expected || nbright!==(nr_expected>=960 && ng_expected>=960 && nb_expected>=960))$fatal(1,"native red/bright mismatch %0d",na);
   if(native_count==0)native_bank=nb;else if(nb!==native_bank)$fatal(1,"native bank changed within frame");
   native_count=native_count+1;
  end
 end
 always @(posedge clk)if(rst&&!clear&&dut.process_we&&(^dut.process_wd===1'bx))
  $fatal(1,"Unknown write pass=%0d row=%0d word=%0d roles=%0d/%0d/%0d cache=%h/%h/%h wd=%h",dut.pass,dut.row,dut.word_col,dut.upper_slot,dut.current_slot,dut.lower_slot,dut.line0[dut.word_col],dut.line1[dut.word_col],dut.line2[dut.word_col],dut.process_wd);
 function[95:0] reconstruct(input[9:0]r,g,b);
  integer k;reg[7:0]a,bb,c;
  begin for(k=0;k<4;k=k+1)begin
   a=(r>>2)+(k<r[1:0]);bb=(g>>2)+(k<g[1:0]);c=(b>>2)+(k<b[1:0]);
   reconstruct[95-k*24-:24]={a,bb,c};end end
 endfunction
 initial begin
  if(!$value$plusargs("input=%s",input_path)||!$value$plusargs("expected=%s",expected_path))$fatal(1,"Missing paths");
  if($value$plusargs("frame=%d",start))begin end
  fd=$fopen(input_path,"rb");if(!fd)$fatal(1,"Input open failed");
  result=$fseek(fd,start*230400,0);bytes=$fread(samples,fd);$fclose(fd);
  if(bytes!=230400)$fatal(1,"Short source");$readmemh(expected_path,expected);
  repeat(5)@(negedge clk);rst=1;
  for(rr=0;rr<180;rr=rr+1)begin
   for(cc=0;cc<320;cc=cc+1)begin
    @(negedge clk);valid=1;x=cc;y=rr*4+3;idx=rr*320+cc;
    rgb=reconstruct(samples[idx][29:20],samples[idx][19:10],samples[idx][9:0]);
    if(cc%73==0)begin @(negedge clk);valid=0;repeat(2)@(negedge clk);end
   end
   @(negedge clk);valid=0;repeat(4)@(negedge clk);
  end
  repeat(3)@(negedge clk);done=1;@(negedge clk);done=0;
  wait_cycles=0;
  while(!mv&&wait_cycles<500000)begin @(negedge clk);wait_cycles=wait_cycles+1;end
  if(!mv)$fatal(1,"Mask timeout state=%0d pass=%0d row=%0d",dut.state,dut.pass,dut.row);
  if(fault||fid!=0)$fatal(1,"Input fault or wrong source frame");
  if(native_count!=14400 || bank!==native_bank)$fatal(1,"native capture/publication mismatch");
  if(cycles>=1666667)$fatal(1,"Morphology exceeds full 60Hz clock budget");
  for(word_id=0;word_id<2430;word_id=word_id+1)begin
   @(negedge clk);read=1;ra=word_id;
   @(negedge clk);read=0;
   if(!rv||rd!==expected[word_id])$fatal(1,"Mask mismatch source=%0d word=%0d actual=%h expected=%h valid=%b",start,word_id,rd,expected[word_id],rv);
   checked=checked+1;
  end
`ifdef HAND_CHAIN
  @(negedge clk);run_ccl=1;ccl_start=1;
  @(negedge clk);ccl_start=0;wait_cycles=0;
  while(!ccl_done&&wait_cycles<500000)begin @(negedge clk);wait_cycles=wait_cycles+1;end
  if(!ccl_done||ccl_overflow)$fatal(1,"Chain CCL timeout/overflow");
  $display("CHAIN_CCL_DONE cycles=%0d",wait_cycles);
  @(negedge clk);run_ccl=0;
  if(best_area!=0)begin
   $display("CHAIN_SELECTED %0d %0d %0d",best_area,best_x,best_y);
   run_trace=1;trace_start=1;
   @(negedge clk);trace_start=0;wait_cycles=0;
   while(!trace_done&&wait_cycles<500000)begin @(negedge clk);wait_cycles=wait_cycles+1;end
   if(!trace_done||trace_fault)$fatal(1,"Chain trace timeout/fault");
   $display("CHAIN_TRACE_DONE points=%0d cycles=%0d",point_count,wait_cycles);
   @(negedge clk);run_trace=0;
  end
  $display("HAND_MASK_CCL_CONTOUR_CHAIN_COMPLETE_NOT_CLASSIFIER");
`endif
  @(negedge clk);release_mask=1;@(negedge clk);release_mask=0;
  if(mv)$fatal(1,"Release failed");
  $display("HAND_MASK_FRAME_PASS source=%0d exact_words=%0d process_cycles=%0d",start,checked,cycles);$finish;
 end
endmodule
