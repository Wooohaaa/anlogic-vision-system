`timescale 1ns/1ps
// Extract exactly the anchor's 8-connected component from an immutable mask
// bank. The bbox is inclusive-origin + width/height. A serial flood fill marks
// only the selected component; unrelated objects inside its bbox stay zero.
// One external mask read may be outstanding. Queue overflow aborts explicitly.
// Output is cropped raster order and holds stable while valid && !ready.
module ua_hand_component_mask #(
    parameter WIDTH=160, HEIGHT=90, QUEUE_CAPACITY=2500, EXTERNAL_MEMORY=0
)(
    input I_clk,I_rst_n,I_clear,I_start,I_mode,
    input [7:0] I_xmin,I_width,I_anchor_x,
    input [6:0] I_ymin,I_height,I_anchor_y,
    output reg O_read,
    output reg [11:0] O_read_addr,
    input I_read_valid,
    input [17:0] I_read_data,
    output O_pixel_valid,O_pixel,O_pixel_last,
    input I_pixel_ready,
    output reg O_busy,O_done,O_fault,O_overflow,
    output reg [13:0] O_area,
    output reg [31:0] O_cycles,
    output O_scratch_read,O_scratch_write,
    output [13:0] O_scratch_address,
    output [15:0] O_scratch_data,
    input [15:0] I_scratch_data,
    input I_probe,
    input [7:0] I_probe_x,
    input [6:0] I_probe_y,
    output O_probe_ready,
    output reg O_probe_valid,
    output O_probe_pixel
);
localparam ROW_WORDS=(WIDTH+5)/6;
localparam IDLE=0, CLEAR_MAP=1, VISIT_READ=2, VISIT_EVAL=3,
           MASK_REQUEST=4, MASK_WAIT=5, FOREGROUND=6, MARK=7,
           QUEUE_NEXT=8, QUEUE_READ=9, QUEUE_EVAL=10,
           NEIGHBOR=11, NEXT_NEIGHBOR=12, OUTPUT_READ=13,
           OUTPUT_PRESENT=14, FINISH=15, FAIL=16;
reg [4:0] state;
reg mode,initial_anchor,foreground;
reg [7:0] xmin,width,vx,cx,ox;
reg [6:0] ymin,height,vy,cy,oy;
reg [13:0] clear_address;
reg [11:0] head,tail;
reg [2:0] direction,read_slot;
reg signed [9:0] step_x,step_y,next_x,next_y;
wire [8:0] global_x={1'b0,xmin}+{1'b0,vx};
wire [7:0] global_y={1'b0,ymin}+{1'b0,vy};
// Exact floor(x/6), 0<=x<=159. 42/256 is low by <1; correct once.
wire [13:0] gx_scaled=({5'd0,global_x}<<5)+({5'd0,global_x}<<3)+({5'd0,global_x}<<1);
wire [5:0] gx_est=gx_scaled[13:8];
wire [6:0] gx_next={1'b0,gx_est}+7'd1;
wire [9:0] gx_boundary=({3'd0,gx_next}<<2)+({3'd0,gx_next}<<1);
wire [5:0] gx_word=gx_est+{5'd0,(gx_boundary<={1'b0,global_x})};
wire [9:0] gx_word6=({4'd0,gx_word}<<2)+({4'd0,gx_word}<<1);
wire [2:0] gx_slot=global_x-gx_word6;
wire [11:0] gy_words=({4'd0,global_y}<<4)+({4'd0,global_y}<<3)+
                          ({4'd0,global_y}<<1)+{4'd0,global_y};
wire [13:0] visit_address=({7'd0,vy}<<7)+({7'd0,vy}<<5)+{6'd0,vx};
wire [13:0] output_address=({7'd0,oy}<<7)+({7'd0,oy}<<5)+{6'd0,ox};
wire [17:0] response_pixel=I_read_data>>(read_slot*3);
/* fehdl force_ram=1, ram_style="bram" */ reg visited[0:14399];
reg visited_q;wire [14:0] queue_q;
reg probe_inside;
assign O_probe_ready=state==IDLE && !I_start && I_rst_n && !I_clear;
wire probe_accept=I_probe && O_probe_ready;
wire probe_in_bounds=I_probe_x<width && I_probe_y<height;
wire [13:0]probe_address=({7'd0,I_probe_y}<<7)+({7'd0,I_probe_y}<<5)+{6'd0,I_probe_x};
wire visited_read=state==VISIT_READ || state==OUTPUT_READ || probe_accept;
wire [13:0] visited_address=probe_accept ? (probe_in_bounds ? probe_address : 14'd0) :
                          state==OUTPUT_READ ? output_address : visit_address;
assign O_probe_pixel=O_probe_valid && probe_inside && visited_q;
assign O_scratch_read=state==QUEUE_READ && I_rst_n && !I_clear;
assign O_scratch_write=state==MARK && I_rst_n && !I_clear;
assign O_scratch_address={2'd0,(O_scratch_write ? tail : head)};
assign O_scratch_data={1'b0,vy,vx};
generate if(EXTERNAL_MEMORY)begin:gen_external_memory
 assign queue_q=I_scratch_data[14:0];
end else begin:gen_private_memory
 /* fehdl force_ram=1, ram_style="bram" */ reg[14:0]queue[0:QUEUE_CAPACITY-1];
 reg[14:0]q;
 always @(posedge I_clk)begin
  if(O_scratch_read)q<=queue[head];
  if(O_scratch_write)queue[tail]<={vy,vx};
 end
 assign queue_q=q;
end endgenerate
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin O_probe_valid<=0;probe_inside<=0;end
 else if(I_clear)begin O_probe_valid<=0;probe_inside<=0;end
 else begin O_probe_valid<=probe_accept;probe_inside<=probe_in_bounds;end
end
always @(posedge I_clk)begin
    if(visited_read)visited_q<=visited[visited_address];
    if(state==CLEAR_MAP)visited[clear_address]<=0;
    else if(state==MARK)visited[visit_address]<=1;
end
assign O_pixel_valid=state==OUTPUT_PRESENT;
assign O_pixel=visited_q;
assign O_pixel_last=ox==width-1 && oy==height-1;
always @* begin
    step_x=0;step_y=0;
    case(direction)
    0:step_x=1;1:begin step_x=1;step_y=1;end
    2:step_y=1;3:begin step_x=-1;step_y=1;end
    4:step_x=-1;5:begin step_x=-1;step_y=-1;end
    6:step_y=-1;7:begin step_x=1;step_y=-1;end
    endcase
    next_x=$signed({2'd0,cx})+step_x;
    next_y=$signed({3'd0,cy})+step_y;
end
always @(posedge I_clk or negedge I_rst_n)begin
    if(!I_rst_n)begin
        state<=IDLE;O_read<=0;O_read_addr<=0;O_busy<=0;O_done<=0;
        O_fault<=0;O_overflow<=0;O_area<=0;O_cycles<=0;
        mode<=0;initial_anchor<=0;foreground<=0;xmin<=0;ymin<=0;
        width<=0;height<=0;vx<=0;vy<=0;cx<=0;cy<=0;ox<=0;oy<=0;
        clear_address<=0;head<=0;tail<=0;direction<=0;read_slot<=0;
    end else if(I_clear)begin
        state<=IDLE;O_read<=0;O_busy<=0;O_done<=0;O_fault<=0;O_overflow<=0;O_area<=0;O_cycles<=0;
    end else begin
        O_read<=0;O_done<=0;
        if(O_busy)O_cycles<=O_cycles+32'd1;
        case(state)
        IDLE:if(I_start)begin
            O_busy<=1;O_fault<=0;O_overflow<=0;O_area<=0;O_cycles<=0;
            if(I_width==0 || I_height==0 || {1'b0,I_xmin}+{1'b0,I_width}>WIDTH ||
               {1'b0,I_ymin}+{1'b0,I_height}>HEIGHT || I_anchor_x<I_xmin ||
               I_anchor_y<I_ymin || {1'b0,I_anchor_x}>={1'b0,I_xmin}+{1'b0,I_width} ||
               {1'b0,I_anchor_y}>={1'b0,I_ymin}+{1'b0,I_height})state<=FAIL;
            else begin
                xmin<=I_xmin;ymin<=I_ymin;width<=I_width;height<=I_height;
                vx<=I_anchor_x-I_xmin;vy<=I_anchor_y-I_ymin;mode<=I_mode;
                clear_address<=0;head<=0;tail<=0;initial_anchor<=1;state<=CLEAR_MAP;
            end
        end
        CLEAR_MAP:if(clear_address==14'd14399)state<=VISIT_READ;
                  else clear_address<=clear_address+14'd1;
        VISIT_READ:state<=VISIT_EVAL;
        VISIT_EVAL:state<=visited_q ? NEXT_NEIGHBOR : MASK_REQUEST;
        MASK_REQUEST:begin
            O_read<=1;O_read_addr<=gy_words+{6'd0,gx_word};read_slot<=gx_slot;state<=MASK_WAIT;
        end
        MASK_WAIT:if(I_read_valid)begin
            foreground<=mode ? response_pixel[2] : response_pixel[0];state<=FOREGROUND;
        end
        FOREGROUND:begin
            if(!foreground)state<=initial_anchor ? FAIL : NEXT_NEIGHBOR;
            else if(tail==QUEUE_CAPACITY)begin O_overflow<=1;state<=FAIL;end
            else state<=MARK;
        end
        MARK:begin
            tail<=tail+12'd1;O_area<=O_area+14'd1;
            if(initial_anchor)begin initial_anchor<=0;state<=QUEUE_NEXT;end
            else state<=NEXT_NEIGHBOR;
        end
        QUEUE_NEXT:begin
            if(head==tail)begin ox<=0;oy<=0;state<=OUTPUT_READ;end
            else state<=QUEUE_READ;
        end
        QUEUE_READ:state<=QUEUE_EVAL;
        QUEUE_EVAL:begin
            cx<=queue_q[7:0];cy<=queue_q[14:8];head<=head+12'd1;
            direction<=0;state<=NEIGHBOR;
        end
        NEIGHBOR:begin
            if(next_x<0 || next_y<0 || next_x>=$signed({2'd0,width}) || next_y>=$signed({3'd0,height}))
                state<=NEXT_NEIGHBOR;
            else begin vx<=next_x[7:0];vy<=next_y[6:0];state<=VISIT_READ;end
        end
        NEXT_NEIGHBOR:begin
            if(direction==7)state<=QUEUE_NEXT;
            else begin direction<=direction+3'd1;state<=NEIGHBOR;end
        end
        OUTPUT_READ:state<=OUTPUT_PRESENT;
        OUTPUT_PRESENT:if(I_pixel_ready)begin
            if(ox==width-1 && oy==height-1)state<=FINISH;
            else begin
                if(ox==width-1)begin ox<=0;oy<=oy+7'd1;end else ox<=ox+8'd1;
                state<=OUTPUT_READ;
            end
        end
        FINISH:begin O_done<=1;O_busy<=0;state<=IDLE;end
        FAIL:begin O_fault<=1;O_done<=1;O_busy<=0;state<=IDLE;end
        default:state<=FAIL;
        endcase
    end
end
`ifndef SYNTHESIS
initial begin
    // Address packing is intentionally fixed to the production 160x90 grid.
    if(WIDTH!=160 || HEIGHT!=90 || QUEUE_CAPACITY<1 || QUEUE_CAPACITY>2500)
        $fatal(1,"component extraction geometry/queue capacity");
end
`endif
endmodule
