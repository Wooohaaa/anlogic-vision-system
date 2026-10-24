// Frozen verified v47 baseline. Test-only; not a production compilation unit.
`timescale 1ns/1ps
// Resource-limited two-pose classifier: exact 8-connected component,
// debounced horizontal finger-gap support and occupied bbox fraction.
// Not a renamed three-class classifier: no palm distance, hull/defect scan,
// tip sorting, thumb tests or finger-width engine is instantiated.
// IDs retain OSD compatibility: 0 uncertain, 1 closed/fist, 3 open.
// 160x90 native raster. No MCU/background reference. Selected bank immutable.
module v47_ua_hand_binary_shape #(parameter MAX_CYCLES=4000000)(
 input I_clk,I_rst_n,I_clear,I_start,I_mode,
 input[7:0]I_xmin,I_width,I_anchor_x,input[6:0]I_ymin,I_height,I_anchor_y,
 output O_start_ready,O_read,output[11:0]O_read_addr,input I_read_valid,input[17:0]I_read_data,
 output reg O_busy,O_done,O_fault,output reg[1:0]O_raw,
 output[13:0]O_area,output reg[6:0]O_rows3,output reg[31:0]O_cycles,
 input I_scratch_read,I_scratch_write,input[13:0]I_scratch_address,input[15:0]I_scratch_data,
 output O_scratch_ready,O_scratch_valid,output[15:0]O_scratch_data
);
localparam IDLE=0,LAUNCH=1,RUN=2,MUL_START=3,MUL_WAIT=4,DECIDE=5,FINISH=6,FAIL=7;
reg[2:0]state,operation;
reg mode,source_pending,external_pending;
reg[7:0]xmin,width,anchor_x,x,run_start,run_length,previous_end;
reg[6:0]ymin,height,anchor_y;
reg[1:0]row_runs;
reg[13:0]box_area;reg[21:0]area100;reg open_low,open_high,solid;
wire abort=I_clear || state==FAIL;
wire cc_read,cc_done,cc_fault,cc_valid,cc_pixel,cc_last,cr,cw;
wire[11:0]cc_addr;wire[13:0]ca;wire[15:0]cd,scratch_q;
wire request=I_scratch_read || I_scratch_write;
assign O_scratch_ready=state==IDLE && I_rst_n && !abort && !source_pending && !external_pending &&
 I_scratch_address<14400 && !(I_scratch_read && I_scratch_write);
wire external_access=O_scratch_ready && request;
assign O_scratch_valid=state==IDLE && I_rst_n && !abort && external_pending;
assign O_scratch_data=scratch_q;
assign O_start_ready=state==IDLE && !source_pending && !external_pending && !request && I_rst_n && !abort;
assign O_read=cc_read && state==RUN && !abort && I_rst_n;
assign O_read_addr=cc_addr;
v47_ua_hand_scratch_ram storage(I_clk,
 !abort && (external_access ? I_scratch_read : cr),
 !abort && (external_access ? I_scratch_write : cw),
 external_access ? I_scratch_address : ca,external_access ? I_scratch_data : cd,scratch_q);
ua_hand_component_mask #(.EXTERNAL_MEMORY(1)) component_core(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(abort),.I_start(state==LAUNCH),.I_mode(mode),
 .I_xmin(xmin),.I_width(width),.I_anchor_x(anchor_x),.I_ymin(ymin),.I_height(height),.I_anchor_y(anchor_y),
 .O_read(cc_read),.O_read_addr(cc_addr),.I_read_valid(I_read_valid && source_pending),.I_read_data(I_read_data),
 .O_pixel_valid(cc_valid),.O_pixel(cc_pixel),.O_pixel_last(cc_last),.I_pixel_ready(state==RUN),
 .O_busy(),.O_done(cc_done),.O_fault(cc_fault),.O_overflow(),.O_area(O_area),.O_cycles(),
 .O_scratch_read(cr),.O_scratch_write(cw),.O_scratch_address(ca),.O_scratch_data(cd),.I_scratch_data(scratch_q),
 .I_probe(1'b0),.I_probe_x(8'd0),.I_probe_y(7'd0),.O_probe_ready(),.O_probe_valid(),.O_probe_pixel());
wire[8:0]length_next={1'b0,run_length}+9'd1;
wire closing=(!cc_pixel || x==width-1) && (cc_pixel ? length_next : {1'b0,run_length})>=2;
wire distinct=closing && (row_runs==0 || {1'b0,run_start}>={1'b0,previous_end}+9'd3);
wire[1:0]runs_next=(distinct && row_runs!=3) ? row_runs+2'd1 : row_runs;
wire[13:0]mul_a=operation==0 ? {6'd0,width} : operation==1 ? O_area : box_area;
wire[7:0]mul_b=operation==0 ? {1'b0,height} : operation==1 ? 8'd100 : operation==2 ? 8'd57 : operation==3 ? 8'd30 : 8'd65;
wire mul_done;wire[21:0]product;
ua_hand_product_serial #(.A_BITS(14),.B_BITS(8),.HARD_MULTIPLY(1)) product_core(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(abort),.I_start(state==MUL_START),.I_a(mul_a),.I_b(mul_b),
 .O_busy(),.O_done(mul_done),.O_product(product));
wire[9:0]support8={3'd0,O_rows3}<<3;
wire[9:0]height5=({3'd0,height}<<2)+{3'd0,height};
wire[10:0]height10=({4'd0,height}<<3)+({4'd0,height}<<1);
wire[10:0]width9=({3'd0,width}<<3)+{3'd0,width};
wire is_open=O_area>=200 && O_rows3>=3 && support8>={3'd0,height} && height5>=({2'd0,width}<<2) && open_low && open_high;
wire is_closed=O_area>=200 && ({1'b0,O_area}<<1)>={1'b0,box_area} && height10>=width9 &&
 {2'd0,height}<=({1'b0,width}<<1) && support8<{3'd0,height};
wire is_solid=mode && O_area>=300 && solid && support8<{3'd0,height};
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin source_pending<=0;external_pending<=0;end
 else begin
  if(O_read)source_pending<=1;else if(I_read_valid)source_pending<=0;
  if(abort)external_pending<=0;else external_pending<=external_access && I_scratch_read;
 end
end
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
  state<=IDLE;operation<=0;mode<=0;xmin<=0;width<=0;anchor_x<=0;ymin<=0;height<=0;anchor_y<=0;
  x<=0;run_start<=0;run_length<=0;previous_end<=0;row_runs<=0;box_area<=0;area100<=0;open_low<=0;open_high<=0;solid<=0;
  O_busy<=0;O_done<=0;O_fault<=0;O_raw<=0;O_rows3<=0;O_cycles<=0;
 end else if(I_clear)begin state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_raw<=0;O_rows3<=0;O_cycles<=0;end
 else begin
  O_done<=0;if(O_busy)O_cycles<=O_cycles+32'd1;
  if(O_busy && state!=FAIL && state!=FINISH && O_cycles>=MAX_CYCLES)state<=FAIL;
  else case(state)
  IDLE:if(I_start && O_start_ready)begin
   mode<=I_mode;xmin<=I_xmin;width<=I_width;anchor_x<=I_anchor_x;ymin<=I_ymin;height<=I_height;anchor_y<=I_anchor_y;
   x<=0;run_start<=0;run_length<=0;previous_end<=0;row_runs<=0;O_rows3<=0;O_raw<=0;
   O_busy<=1;O_fault<=0;O_cycles<=0;state<=LAUNCH;
  end
  LAUNCH:state<=RUN;
  RUN:begin
   if(cc_valid)begin
    if(cc_pixel)begin if(run_length==0)run_start<=x;run_length<=run_length+8'd1;end
    else run_length<=0;
    if(closing)begin row_runs<=runs_next;previous_end<=cc_pixel ? x : x-8'd1;end
    if(x==width-1)begin
     if(runs_next>=3)O_rows3<=O_rows3+7'd1;
     x<=0;run_length<=0;row_runs<=0;previous_end<=0;
    end else x<=x+8'd1;
   end
   if(cc_done)begin operation<=0;state<=cc_fault ? FAIL : MUL_START;end
  end
  MUL_START:state<=MUL_WAIT;
  MUL_WAIT:if(mul_done)begin
   case(operation)
   0:box_area<=product[13:0];
   1:area100<=product;
   2:open_low<=area100<=product;
   3:open_high<=area100>=product;
   4:solid<=area100>=product;
   endcase
   if(operation==4)state<=DECIDE;else begin operation<=operation+3'd1;state<=MUL_START;end
  end
  DECIDE:begin O_raw<=is_open ? 2'd3 : (is_closed || is_solid) ? 2'd1 : 2'd0;state<=FINISH;end
  FINISH:begin O_done<=1;O_busy<=0;state<=IDLE;end
  FAIL:begin O_done<=1;O_busy<=0;O_fault<=1;O_raw<=0;state<=IDLE;end
  default:state<=FAIL;
  endcase
 end
end
endmodule
