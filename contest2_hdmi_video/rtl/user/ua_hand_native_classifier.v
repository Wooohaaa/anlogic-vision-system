`timescale 1ns/1ps
// Complete independent RGB -> masks -> CCL red sums -> persistent labels ->
// descriptors -> exact association -> actual geometry/policy/vote pipeline.
// All storage/logic is FPGA RTL. No reference frame and no injected features.
// Backend runs only on a published immutable bank; whole detection frames
// are dropped while busy. Main video never stalls. SRAM/Flash not controlled.
module ua_hand_native_classifier #(parameter IMG_WIDTH=1280,IMG_HEIGHT=720,MAX_CYCLES=16000000)(
 input I_clk,I_rst_n,I_clear,I_sample_valid,I_frame_done,
 input[9:0]I_x_grp,I_y,input[95:0]I_rgb,
 output reg O_result_valid,output reg[1:0]O_id,O_raw,
 output reg[2:0]O_tips,output reg O_box_valid,
 output reg[7:0]O_x,O_width,output reg[6:0]O_y,O_height,
 output reg O_fault,output O_drop,output reg[31:0]O_cycles
);
localparam WAIT_FRAME=0,CCL_START=1,CCL_WAIT=2,LABEL_START=3,LABEL_WAIT=4,
 BUILD_START=5,BUILD_WAIT=6,ASSOC_START=7,ASSOC_WAIT=8,
 FRAME_START=9,FRAME_FEED=10,FRAME_WAIT=11,RECYCLE=12,FAIL=13;
reg[3:0]state;reg mode;reg[4:0]count,index;reg[13:0]bright;
wire abort=I_clear || state==FAIL;
wire recycle=I_clear || state==RECYCLE || state==FAIL;
wire mask_valid,mask_rv,native_valid,native_bright,input_fault;
wire[17:0]mask_data;wire[13:0]native_address;wire[9:0]native_red;
wire ccl_read,ccl_done,ccl_fault,blob,red_read;
wire[11:0]ccl_addr;wire[13:0]red_addr;wire[23:0]red_sum;
wire[7:0]anchor_x;wire[6:0]anchor_y;
wire label_read,label_done,label_fault,label_mr,label_mw;
wire[11:0]label_addr;wire[13:0]label_ma;wire[15:0]label_md;
wire build_ready,build_done,build_fault,blob_ready,build_mr;
wire[13:0]build_ma;
wire query,query_mode,query_ready,query_valid,descriptor_valid,descriptor_mode,descriptor_ready;
wire[6:0]query_root,descriptor_root;wire[95:0]query_data,descriptor_data;
wire assoc_ready,assoc_done,assoc_fault,assoc_mr,assoc_cv,assoc_mode;
wire[13:0]assoc_ma;wire[95:0]assoc_data;
wire frame_ready,candidate_ready,frame_read,frame_done,frame_fault,frame_box;
wire[11:0]frame_addr;wire[1:0]frame_id,frame_raw;wire[2:0]frame_tips;
wire[7:0]frame_x,frame_width;wire[6:0]frame_y,frame_height;
wire scratch_ready,scratch_valid;wire[15:0]scratch_q;
wire ccl_phase=state==CCL_START || state==CCL_WAIT;
wire label_phase=state==LABEL_START || state==LABEL_WAIT;
wire build_phase=state==BUILD_START || state==BUILD_WAIT;
wire assoc_phase=state==ASSOC_START || state==ASSOC_WAIT;
wire frame_phase=state==FRAME_START || state==FRAME_FEED || state==FRAME_WAIT;
wire source_read=ccl_phase ? ccl_read : label_phase ? label_read : frame_phase ? frame_read : 1'b0;
wire[11:0]source_addr=ccl_phase ? ccl_addr : label_phase ? label_addr : frame_addr;
wire scratch_read=ccl_phase ? red_read : label_phase ? label_mr : build_phase ? build_mr : assoc_phase ? assoc_mr : 1'b0;
wire scratch_write=native_valid || (label_phase && label_mw);
wire[13:0]scratch_address=native_valid ? native_address : ccl_phase ? red_addr : label_phase ? label_ma : build_phase ? build_ma : assoc_ma;
wire[15:0]scratch_data=native_valid ? {6'd0,native_red} : label_md;
(* ram_style="dram" *) reg[96:0]candidates[0:15];
wire[96:0]candidate=candidates[index[3:0]];
wire[8:0]candidate_width={1'b0,candidate[30:23]}-{1'b0,candidate[22:15]}+9'd1;
wire[7:0]candidate_height={1'b0,candidate[14:8]}-{1'b0,candidate[7:1]}+8'd1;
ua_hand_mask_frame #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT),.EXTERNAL_CAPTURE_GATE(1)) frontend(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(I_clear),.I_sample_valid(I_sample_valid),.I_frame_done(I_frame_done),
 .I_x_grp(I_x_grp),.I_y(I_y),.I_rgb(I_rgb),.O_mask_valid(mask_valid),.O_mask_bank(),.O_frame_id(),
 .I_mask_release(state==RECYCLE || state==FAIL),.I_read(source_read),.I_read_addr(source_addr),
 .O_read_valid(mask_rv),.O_read_data(mask_data),.O_drop_pulse(O_drop),.O_input_fault(input_fault),.O_process_cycles(),
 .I_capture_allow(state==WAIT_FRAME && frame_ready && assoc_ready && build_ready),
 .O_native_valid(native_valid),.O_native_bank(),.O_native_bright(native_bright),.O_native_address(native_address),.O_native_red(native_red));
ua_hand_blob_scan #(.RGB_STATS(1)) ccl(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(recycle),.I_start(state==CCL_START),.I_mode(mode),
 .O_read(ccl_read),.O_read_addr(ccl_addr),.I_read_valid(mask_rv && ccl_phase),.I_read_data(mask_data),
 .O_busy(),.O_done(ccl_done),.O_overflow(ccl_fault),.O_blob_valid(blob),.O_area(),.O_seed_count(),
 .O_xmin(),.O_xmax(),.O_ymin(),.O_ymax(),.O_anchor_x(anchor_x),.O_anchor_y(anchor_y),
 .O_red_read(red_read),.O_red_addr(red_addr),.I_red_valid(scratch_valid && ccl_phase),.I_red_data(scratch_q[9:0]),.O_red_sum(red_sum));
ua_hand_label_map labels(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(recycle),.I_start(state==LABEL_START),.I_mode(mode),
 .O_start_ready(),.O_read(label_read),.O_read_addr(label_addr),.I_read_valid(mask_rv && label_phase),.I_read_data(mask_data),
 .O_memory_read(label_mr),.O_memory_write(label_mw),.O_memory_address(label_ma),.O_memory_data(label_md),
 .I_memory_ready(scratch_ready && label_phase),.I_memory_data(scratch_q),.O_busy(),.O_done(label_done),.O_fault(label_fault),.O_labels(),.O_cycles());
ua_hand_descriptor_build builder(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(recycle),.I_start(state==BUILD_START),
 .I_blob_valid(blob && ccl_phase),.I_blob_mode(mode),.I_blob_anchor_x(anchor_x),.I_blob_anchor_y(anchor_y),.I_blob_red_sum(red_sum),
 .O_blob_ready(blob_ready),.O_start_ready(build_ready),.O_memory_read(build_mr),.O_memory_address(build_ma),
 .I_memory_ready(scratch_ready && build_phase),.I_memory_data(scratch_q),
 .O_query(query),.O_query_mode(query_mode),.O_query_root(query_root),.I_query_ready(query_ready),.I_query_valid(query_valid),.I_query_data(query_data),
 .O_descriptor_valid(descriptor_valid),.O_descriptor_mode(descriptor_mode),.O_descriptor_root(descriptor_root),.O_descriptor_data(descriptor_data),
 .I_descriptor_ready(descriptor_ready),.O_busy(),.O_done(build_done),.O_fault(build_fault),.O_cycles());
ua_hand_associate #(.EXTERNAL_DESCRIPTOR(1)) association(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(recycle),.I_start(state==ASSOC_START),
 .I_descriptor_valid(descriptor_valid),.I_descriptor_mode(descriptor_mode),.I_descriptor_root(descriptor_root),.I_descriptor_data(descriptor_data),
 .O_descriptor_ready(descriptor_ready),.O_start_ready(assoc_ready),.O_memory_read(assoc_mr),.O_memory_address(assoc_ma),
 .I_memory_ready(scratch_ready && assoc_phase),.I_memory_data(scratch_q),
 .O_candidate_valid(assoc_cv),.I_candidate_ready(state==ASSOC_WAIT && count<16),.O_candidate_mode(assoc_mode),.O_candidate_data(assoc_data),
 .O_busy(),.O_done(assoc_done),.O_fault(assoc_fault),.O_candidates(),.O_cycles(),
 .I_query(query),.I_query_mode(query_mode),.I_query_root(query_root),.O_query_ready(query_ready),.O_query_valid(query_valid),.O_query_data(query_data));
ua_hand_frame_classifier #(.EXTERNAL_SCRATCH(1)) classifier(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(abort),.I_start(state==FRAME_START),
 .I_candidate_valid(state==FRAME_FEED && index<count),.I_finish(state==FRAME_FEED && index==count),.I_mode(candidate[96]),
 .I_x(candidate[22:15]),.I_width(candidate_width[7:0]),.I_anchor_x(candidate[45:38]),
 .I_y(candidate[7:1]),.I_height(candidate_height[6:0]),.I_anchor_y(candidate[37:31]),
 .I_area(candidate[59:46]),.I_red_sum(candidate[83:60]),.I_bright_count(bright),
 .O_start_ready(frame_ready),.O_candidate_ready(candidate_ready),.O_read(frame_read),.O_read_addr(frame_addr),
 .I_read_valid(mask_rv && frame_phase),.I_read_data(mask_data),.O_busy(),.O_done(frame_done),.O_fault(frame_fault),
 .O_id(frame_id),.O_raw(frame_raw),.O_box_valid(frame_box),.O_tips(frame_tips),
 .O_x(frame_x),.O_width(frame_width),.O_y(frame_y),.O_height(frame_height),.O_radius_q4(),.O_mean_r(),.O_backlit(),
 .I_scratch_read(scratch_read),.I_scratch_write(scratch_write),.I_scratch_address(scratch_address),.I_scratch_data(scratch_data),
 .O_scratch_ready(scratch_ready),.O_scratch_valid(scratch_valid),.O_scratch_data(scratch_q));
always @(posedge I_clk)if(state==ASSOC_WAIT && assoc_cv && count<16)candidates[count[3:0]]<={assoc_mode,assoc_data};
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
  state<=WAIT_FRAME;mode<=0;count<=0;index<=0;bright<=0;O_result_valid<=0;O_id<=0;O_raw<=0;
  O_tips<=0;O_box_valid<=0;O_x<=0;O_y<=0;O_width<=0;O_height<=0;O_fault<=0;O_cycles<=0;
 end else if(I_clear)begin
  state<=WAIT_FRAME;O_result_valid<=0;O_id<=0;O_raw<=0;O_tips<=0;O_box_valid<=0;O_fault<=0;O_cycles<=0;bright<=0;
 end else begin
  O_result_valid<=0;
  if(native_valid)bright<=native_address==0 ? {13'd0,native_bright} : bright+{13'd0,native_bright};
  if(state!=WAIT_FRAME && state!=RECYCLE)O_cycles<=O_cycles+32'd1;
  if(state!=FAIL && state!=RECYCLE && ((state!=WAIT_FRAME && O_cycles>=MAX_CYCLES) ||
    (native_valid && (state!=WAIT_FRAME || !scratch_ready)) || (blob && ccl_phase && !blob_ready)))state<=FAIL;
  else case(state)
  WAIT_FRAME:if(mask_valid)begin mode<=0;count<=0;index<=0;O_cycles<=0;O_fault<=0;state<=CCL_START;end
  CCL_START:state<=CCL_WAIT;
  CCL_WAIT:if(ccl_done)begin
   if(ccl_fault)state<=FAIL;
   else if(!mode)begin mode<=1;state<=CCL_START;end
   else begin mode<=0;state<=LABEL_START;end
  end
  LABEL_START:state<=LABEL_WAIT;
  LABEL_WAIT:if(label_done)begin
   if(label_fault)state<=FAIL;
   else if(!mode)begin mode<=1;state<=LABEL_START;end
   else state<=BUILD_START;
  end
  BUILD_START:if(build_ready)state<=BUILD_WAIT;
  BUILD_WAIT:if(build_done)state<=build_fault ? FAIL : ASSOC_START;
  ASSOC_START:if(assoc_ready)state<=ASSOC_WAIT;
  ASSOC_WAIT:begin
   if(assoc_cv && count<16)count<=count+5'd1;
   if(assoc_done)state<=assoc_fault ? FAIL : FRAME_START;
  end
  FRAME_START:if(frame_ready)begin index<=0;state<=FRAME_FEED;end
  FRAME_FEED:if(candidate_ready)begin
   if(index<count)index<=index+5'd1;else state<=FRAME_WAIT;
  end
  FRAME_WAIT:if(frame_done)begin
   if(frame_fault)state<=FAIL;
   else begin
    O_id<=frame_id;O_raw<=frame_raw;O_tips<=frame_tips;O_box_valid<=frame_box;
    O_x<=frame_x;O_y<=frame_y;O_width<=frame_width;O_height<=frame_height;O_result_valid<=1;state<=RECYCLE;
   end
  end
  RECYCLE:state<=WAIT_FRAME;
  FAIL:begin O_fault<=1;O_id<=0;O_raw<=0;O_tips<=0;O_box_valid<=0;O_result_valid<=1;state<=RECYCLE;end
  default:state<=FAIL;
  endcase
 end
end
endmodule
