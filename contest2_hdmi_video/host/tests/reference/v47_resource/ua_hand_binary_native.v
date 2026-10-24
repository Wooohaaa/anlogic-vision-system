// Frozen verified v47 baseline. Test-only; not a production compilation unit.
`timescale 1ns/1ps
// Pure-FPGA two-pose resource variant. New mask frontend + BOTH seed/grown
// CCL passes + exact isolated component run support + RGB confidence + vote.
// No persistent label map, overlap matrix, MCU or expensive palm/defect chain.
// This is a deliberately different binary algorithm, not three-class parity.
// CCL descriptors are stored as six 16-bit words in one shared 1024x16 ERAM.
module v47_ua_hand_binary_native #(parameter IMG_WIDTH=1280,IMG_HEIGHT=720,MAX_CYCLES=32000000)(
 input I_clk,I_rst_n,I_clear,I_sample_valid,I_frame_done,
 input[9:0]I_x_grp,I_y,input[95:0]I_rgb,
 output reg O_result_valid,output reg[1:0]O_id,O_raw,
 output reg[2:0]O_tips,output reg O_box_valid,
 output reg[7:0]O_x,O_width,output reg[6:0]O_y,O_height,
 output reg O_fault,output O_drop,output reg[31:0]O_cycles
);
localparam WAIT_FRAME=0,CCL_START=1,CCL_WAIT=2,DRAIN=3,CANDIDATE_READ=4,CANDIDATE_WAIT=5,
 PREFILTER=6,SHAPE_START=7,SHAPE_WAIT=8,DIV_START=9,DIV_WAIT=10,MUL_START=11,MUL_WAIT=12,
 NEXT=13,VOTE=14,VOTE_WAIT=15,RECYCLE=16,FAIL=17;
reg[4:0]state;reg mode,backlit,best_valid,capture_owned;
reg[7:0]count,index;reg[2:0]write_field,read_field;reg writer_busy;
reg[95:0]write_record,record,best_record;
reg[15:0]descriptor_q;
/* fehdl force_ram=1, ram_style="bram" */ reg[15:0]descriptor_memory[0:1023];
reg[13:0]bright;reg[22:0]best_score;reg[9:0]mean;
reg[1:0]best_raw;
wire abort=I_clear || state==FAIL;
wire ccl_phase=state==CCL_START || state==CCL_WAIT || state==DRAIN;
wire shape_phase=state==SHAPE_START || state==SHAPE_WAIT;
wire mask_valid,mask_rv,native_valid,native_bright,front_input_fault;
wire[17:0]mask_data;wire[13:0]native_address;wire[9:0]native_red;
wire ccl_read,ccl_done,ccl_fault,blob,red_read;
wire[11:0]ccl_addr;wire[13:0]red_addr,area;
wire[23:0]red_sum;wire[7:0]xmin,xmax,ax;wire[6:0]ymin,ymax,ay;
wire shape_ready,shape_done,shape_fault,shape_read;
wire[11:0]shape_addr;wire[13:0]shape_area;wire[1:0]shape_raw;
wire scratch_ready,scratch_valid;wire[15:0]scratch_q;
// Only ONE R scratch image exists. WAIT_FRAME also covers mask preprocessing,
// so WAIT_FRAME alone is not permission to capture another frame into it.
wire capture_allow=state==WAIT_FRAME && shape_ready && !capture_owned;
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)capture_owned<=0;
 else if(I_clear || state==RECYCLE || state==FAIL)capture_owned<=0;
 else if(capture_allow && I_sample_valid && I_x_grp==0 && I_y==7)capture_owned<=1;
end
wire source_read=ccl_phase ? ccl_read : shape_phase ? shape_read : 1'b0;
wire[11:0]source_addr=ccl_phase ? ccl_addr : shape_addr;
// Record: mode[83], R[82:59], area[58:45], anchor x[44:37],
// anchor y[36:30], width[29:22], x[21:14], height[13:7], y[6:0].
wire[8:0]blob_width={1'b0,xmax}-{1'b0,xmin}+9'd1;
wire[7:0]blob_height={1'b0,ymax}-{1'b0,ymin}+8'd1;
wire[23:0]blob_threshold=backlit ? (({10'd0,area}<<7)+({10'd0,area}<<5)) : (({10'd0,area}<<6)+({10'd0,area}<<5));
wire blob_eligible=area>=200 && area<=2500 && blob_width>=12 && blob_height>=10 && xmin>1 && xmax<158 &&
 ({3'd0,blob_height}<<1)<=(({2'd0,blob_width}<<2)+({2'd0,blob_width}<<1)+{2'd0,blob_width}) &&
 {2'd0,blob_width}<=(({3'd0,blob_height}<<1)+{3'd0,blob_height}) &&
 (({3'd0,blob_height}<<2)+{3'd0,blob_height})>=(({2'd0,blob_width}<<1)+{2'd0,blob_width}) && red_sum>=blob_threshold;
wire accepting=blob && ccl_phase && blob_eligible;
wire can_accept=!writer_busy || write_field==5;
wire[8:0]effective_count={1'b0,count}+{8'd0,(writer_busy && write_field==5)};
wire[83:0]blob_record={mode,red_sum,area,ax,ay,blob_width[7:0],xmin,blob_height[6:0],ymin};
wire[13:0]candidate_area=record[58:45];
wire math_done,math_fault;wire[31:0]math_q;
wire product_done;wire[22:0]score;
wire vote_valid,vote_box;wire[1:0]vote_id;
wire[14:0]anchor_key={record[36:30],record[44:37]};
wire[14:0]best_anchor_key={best_record[36:30],best_record[44:37]};
wire[9:0]memory_write_address={count[6:0],write_field};
wire[9:0]memory_read_address={index[6:0],read_field};
always @(posedge I_clk)begin
 if(writer_busy && !abort)descriptor_memory[memory_write_address]<=write_record[15:0];
 if(state==CANDIDATE_READ && !abort)descriptor_q<=descriptor_memory[memory_read_address];
end
v47_ua_hand_mask_frame #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT),.EXTERNAL_CAPTURE_GATE(1)) frontend(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(abort),.I_sample_valid(I_sample_valid),.I_frame_done(I_frame_done),
 .I_x_grp(I_x_grp),.I_y(I_y),.I_rgb(I_rgb),.O_mask_valid(mask_valid),.O_mask_bank(),.O_frame_id(),
 .I_mask_release(state==RECYCLE || state==FAIL),.I_read(source_read),.I_read_addr(source_addr),
 .O_read_valid(mask_rv),.O_read_data(mask_data),.O_drop_pulse(O_drop),.O_input_fault(front_input_fault),.O_process_cycles(),
 .I_capture_allow(capture_allow),.O_native_valid(native_valid),.O_native_bank(),.O_native_bright(native_bright),
 .O_native_address(native_address),.O_native_red(native_red));
ua_hand_blob_scan #(.RGB_STATS(1)) ccl(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(I_clear || state==RECYCLE || state==FAIL),.I_start(state==CCL_START),.I_mode(mode),
 .O_read(ccl_read),.O_read_addr(ccl_addr),.I_read_valid(mask_rv && ccl_phase),.I_read_data(mask_data),
 .O_busy(),.O_done(ccl_done),.O_overflow(ccl_fault),.O_blob_valid(blob),.O_area(area),.O_seed_count(),
 .O_xmin(xmin),.O_xmax(xmax),.O_ymin(ymin),.O_ymax(ymax),.O_anchor_x(ax),.O_anchor_y(ay),
 .O_red_read(red_read),.O_red_addr(red_addr),.I_red_valid(scratch_valid && ccl_phase),.I_red_data(scratch_q[9:0]),.O_red_sum(red_sum));
v47_ua_hand_binary_shape shape(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(abort),.I_start(state==SHAPE_START),.I_mode(record[83]),
 .I_xmin(record[21:14]),.I_width(record[29:22]),.I_anchor_x(record[44:37]),.I_ymin(record[6:0]),.I_height(record[13:7]),.I_anchor_y(record[36:30]),
 .O_start_ready(shape_ready),.O_read(shape_read),.O_read_addr(shape_addr),.I_read_valid(mask_rv && shape_phase),.I_read_data(mask_data),
 .O_busy(),.O_done(shape_done),.O_fault(shape_fault),.O_raw(shape_raw),.O_area(shape_area),.O_rows3(),.O_cycles(),
 .I_scratch_read(ccl_phase && red_read),.I_scratch_write(native_valid),.I_scratch_address(native_valid ? native_address : red_addr),
 .I_scratch_data({6'd0,native_red}),.O_scratch_ready(scratch_ready),.O_scratch_valid(scratch_valid),.O_scratch_data(scratch_q));
ua_hand_integer_math divider(.I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(abort),.I_start(state==DIV_START),.I_sqrt(1'b0),
 .I_a({8'd0,record[82:59]}),.I_b({18'd0,candidate_area}),.O_busy(),.O_done(math_done),.O_fault(math_fault),.O_result(math_q),.O_remainder());
// Compare area*min(floor(mean R),384); common factor 100 cancels exactly.
ua_hand_product_serial #(.A_BITS(14),.B_BITS(9),.HARD_MULTIPLY(1)) product_core(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(abort),.I_start(state==MUL_START),.I_a(candidate_area),.I_b(mean>=384 ? 9'd384 : mean[8:0]),
 .O_busy(),.O_done(product_done),.O_product(score));
ua_hand_temporal_vote votes(.I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(abort),
 .I_frame_valid(state==VOTE),.I_raw(best_valid ? best_raw : 2'd0),.I_best_present(best_valid),.O_valid(vote_valid),.O_id(vote_id),.O_box_valid(vote_box));
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
  state<=WAIT_FRAME;mode<=0;count<=0;index<=0;write_field<=0;read_field<=0;writer_busy<=0;
  write_record<=0;record<=0;best_record<=0;bright<=0;backlit<=0;best_score<=0;best_valid<=0;best_raw<=0;mean<=0;
  O_result_valid<=0;O_id<=0;O_raw<=0;O_tips<=0;O_box_valid<=0;O_x<=0;O_y<=0;O_width<=0;O_height<=0;O_fault<=0;O_cycles<=0;
 end else if(I_clear)begin
  state<=WAIT_FRAME;writer_busy<=0;count<=0;backlit<=0;bright<=0;O_result_valid<=0;O_id<=0;O_raw<=0;O_tips<=0;O_box_valid<=0;O_fault<=0;O_cycles<=0;
 end else begin
  O_result_valid<=0;
  if(native_valid)bright<=native_address==0 ? {13'd0,native_bright} : bright+{13'd0,native_bright};
  if(state!=WAIT_FRAME && state!=RECYCLE)O_cycles<=O_cycles+32'd1;
  if(writer_busy)begin
   write_record<=write_record>>16;
   if(write_field==5)begin writer_busy<=0;count<=count+8'd1;end else write_field<=write_field+3'd1;
  end
  if(accepting && can_accept && effective_count<128)begin write_record<={12'd0,blob_record};write_field<=0;writer_busy<=1;end
  if(state!=FAIL && state!=RECYCLE && (front_input_fault || (state!=WAIT_FRAME && O_cycles>=MAX_CYCLES) ||
   (native_valid && (state!=WAIT_FRAME || !scratch_ready)) || (accepting && (!can_accept || effective_count>=128))))state<=FAIL;
  else case(state)
  WAIT_FRAME:if(mask_valid)begin mode<=0;count<=0;index<=0;writer_busy<=0;O_cycles<=0;O_fault<=0;best_valid<=0;best_score<=0;state<=CCL_START;end
  CCL_START:state<=CCL_WAIT;
  CCL_WAIT:if(ccl_done)begin
   if(ccl_fault)state<=FAIL;else if(!mode)begin mode<=1;state<=CCL_START;end else state<=DRAIN;
  end
  DRAIN:if(!writer_busy)begin index<=0;read_field<=0;state<=count==0 ? VOTE : CANDIDATE_READ;end
  CANDIDATE_READ:state<=CANDIDATE_WAIT;
  CANDIDATE_WAIT:begin
   record[read_field*16 +:16]<=descriptor_q;
   if(read_field==5)state<=PREFILTER;else begin read_field<=read_field+3'd1;state<=CANDIDATE_READ;end
  end
  PREFILTER:state<=SHAPE_START;
  SHAPE_START:if(shape_ready)state<=SHAPE_WAIT;
  SHAPE_WAIT:if(shape_done)begin
   if(shape_fault || shape_area!=candidate_area)state<=FAIL;else state<=shape_raw==0 ? NEXT : DIV_START;
  end
  DIV_START:state<=DIV_WAIT;
  DIV_WAIT:if(math_done)begin mean<=math_q[9:0];state<=math_fault || math_q>1023 ? FAIL : MUL_START;end
  MUL_START:state<=MUL_WAIT;
  MUL_WAIT:if(product_done)begin
   if(!best_valid || score>best_score || (score==best_score && anchor_key<best_anchor_key))begin
    best_valid<=1;best_record<=record;best_raw<=shape_raw;best_score<=score;
   end
   state<=NEXT;
  end
  NEXT:if(index+8'd1==count)state<=VOTE;
   else begin index<=index+8'd1;read_field<=0;state<=CANDIDATE_READ;end
  VOTE:state<=VOTE_WAIT;
  VOTE_WAIT:if(vote_valid)begin
   O_id<=vote_id;O_raw<=best_valid ? best_raw : 2'd0;O_tips<=best_valid && best_raw==3 ? 3'd3 : 3'd0;O_box_valid<=vote_box;
   O_x<=best_valid ? best_record[21:14] : 8'd0;O_y<=best_valid ? best_record[6:0] : 7'd0;
   O_width<=best_valid ? best_record[29:22] : 8'd0;O_height<=best_valid ? best_record[13:7] : 7'd0;
   if(bright>=450)backlit<=1;else if(bright<225)backlit<=0;
   O_result_valid<=1;state<=RECYCLE;
  end
  RECYCLE:state<=WAIT_FRAME;
  FAIL:begin writer_busy<=0;O_fault<=1;O_id<=0;O_raw<=0;O_tips<=0;O_box_valid<=0;O_result_valid<=1;state<=RECYCLE;end
  default:state<=FAIL;
  endcase
 end
end
endmodule
