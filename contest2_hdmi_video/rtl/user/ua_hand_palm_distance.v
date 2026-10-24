`timescale 1ns/1ps
// Serial native-grid palm distance transform. The caller supplies one selected
// component's cropped, raster-ordered mask. Pixel transfer is valid && ready;
// last must be asserted exactly on the final pixel. No bulk RAM reset is used.
// Distances use chamfer weights 955/1369 and round to pixel Q4, matching the
// integer software reference. A shared synchronous RAM serves both passes.
// Results are valid with done && !fault. clear aborts the current transaction.
module ua_hand_palm_distance #(
    parameter MAX_WIDTH=160, MAX_HEIGHT=90, EXTERNAL_MEMORY=0
)(
    input I_clk, I_rst_n, I_clear, I_start,
    input [7:0] I_width,
    input [6:0] I_height,
    input I_mask_valid, I_mask, I_mask_last,
    output O_mask_ready,
    output reg O_busy, O_done, O_fault, O_has_palm,
    output reg [7:0] O_center_x,
    output reg [6:0] O_center_y,
    output reg [10:0] O_radius_q4,
    output reg O_distance_valid,
    output reg [7:0] O_distance_x,
    output reg [6:0] O_distance_y,
    output reg [10:0] O_distance_q4,
    output reg [31:0] O_cycles,
    output O_scratch_read,O_scratch_write,
    output [13:0] O_scratch_address,
    output [15:0] O_scratch_data,
    input [15:0] I_scratch_data
);
localparam WORDS=MAX_WIDTH*MAX_HEIGHT;
localparam IDLE=0, LOAD=1, CURRENT_READ=2, CURRENT_EVAL=3,
           NEIGHBOR_READ=4, NEIGHBOR_EVAL=5, COMMIT=6, ADVANCE=7,
           LOBE_READ=8, LOBE_EVAL=9, FINISH=10, FAIL=11, SETUP=12;
reg [3:0] state;
reg [7:0] width, x;
reg [6:0] height, y, search_rows;
reg [13:0] address, last_address;
reg reverse_pass;
reg [1:0] neighbor;
reg [15:0] best;
reg [6:0] setup_left,setup_remainder;
wire [7:0] setup_sum={1'b0,setup_remainder}+8'd82;
(* ram_style="dram" *) reg [18:0] row_info[0:MAX_HEIGHT-1];
wire [15:0] ram_q;
reg neighbor_inside;
reg [13:0] neighbor_address;
wire [15:0] neighbor_weight=neighbor[1] ? 16'd1369 : 16'd955;
wire [16:0] neighbor_sum={1'b0,(neighbor_inside ? ram_q : 16'd0)}+
                         {1'b0,neighbor_weight};
wire [15:0] neighbor_value=neighbor_sum[16] ? 16'hffff : neighbor_sum[15:0];
reg [10:0] row_max, global_max;
reg [7:0] row_x;
reg [6:0] lobe_y;
reg [2:0] lobe_sample;
reg [10:0] e0,e1,e2,e3,e4,e5,e6;
reg [7:0] lobe_x;
reg signed [8:0] envelope_y;
wire [18:0] envelope_info=row_info[envelope_y[6:0]];
wire envelope_inside=envelope_y>=0 && envelope_y<$signed({2'b0,height});
wire [10:0] envelope_value=envelope_inside ? envelope_info[10:0] : 11'd0;
wire [13:0] smooth_prev={3'd0,e0}+{3'd0,e1}+{3'd0,e2}+{3'd0,e3}+{3'd0,e4};
wire [13:0] smooth_here={3'd0,e1}+{3'd0,e2}+{3'd0,e3}+{3'd0,e4}+{3'd0,e5};
wire [13:0] smooth_next={3'd0,e2}+{3'd0,e3}+{3'd0,e4}+{3'd0,e5}+{3'd0,e6};
wire [15:0] smooth_scaled={smooth_here,2'b00};
wire [15:0] global_scaled=({5'd0,global_max}<<3)+
                          ({5'd0,global_max}<<2)+{5'd0,global_max};

// Exact division by 125 for all 16-bit input distances: 524/65536 is
// slightly low, and one remainder correction recovers the exact quotient.
// (d*16+500)/1000 == (d*2+62)/125 for integer d. Explicit shifts avoid DSPs.
wire [16:0] quant_n={best,1'b0}+17'd62;
wire [26:0] quant_product=({10'd0,quant_n}<<9)+
                          ({10'd0,quant_n}<<3)+({10'd0,quant_n}<<2);
wire [10:0] quant_est=quant_product[26:16];
wire [11:0] quant_plus={1'b0,quant_est}+12'd1;
wire [19:0] quant_threshold=({8'd0,quant_plus}<<7)-
                            ({8'd0,quant_plus}<<1)-{8'd0,quant_plus};
wire [10:0] quant_value=quant_est+{10'd0,(quant_threshold<={3'd0,quant_n})};
wire [10:0] next_row_max=quant_value>=row_max ? quant_value : row_max;
wire [7:0] next_row_x=quant_value>=row_max ? x : row_x;

wire ram_read=state==CURRENT_READ || (state==NEIGHBOR_READ && neighbor_inside);
wire [13:0] ram_address=state==NEIGHBOR_READ ? neighbor_address : address;
wire load_transfer=state==LOAD && I_mask_valid;
assign O_mask_ready=state==LOAD;
assign O_scratch_read=ram_read && I_rst_n && !I_clear;
assign O_scratch_write=(load_transfer || state==COMMIT) && I_rst_n && !I_clear;
assign O_scratch_address=O_scratch_write ? address : ram_address;
assign O_scratch_data=load_transfer ? (I_mask ? 16'hffff : 16'd0) : best;
generate if(EXTERNAL_MEMORY)begin:gen_external_memory
 assign ram_q=I_scratch_data;
end else begin:gen_private_memory
 ua_hand_scratch_ram #(.WORDS(WORDS)) storage(I_clk,O_scratch_read,O_scratch_write,
                    O_scratch_address,O_scratch_data,ram_q);
end endgenerate

always @* begin
    neighbor_inside=0;neighbor_address=0;
    if(!reverse_pass) begin
        case(neighbor)
        0:begin neighbor_inside=x!=0;neighbor_address=address-14'd1;end
        1:begin neighbor_inside=y!=0;neighbor_address=address-{6'd0,width};end
        2:begin neighbor_inside=x!=0 && y!=0;neighbor_address=address-{6'd0,width}-14'd1;end
        3:begin neighbor_inside=x+9'd1<{1'b0,width} && y!=0;
                neighbor_address=address-{6'd0,width}+14'd1;end
        endcase
    end else begin
        case(neighbor)
        0:begin neighbor_inside=x+9'd1<{1'b0,width};neighbor_address=address+14'd1;end
        1:begin neighbor_inside=y+8'd1<{1'b0,height};neighbor_address=address+{6'd0,width};end
        2:begin neighbor_inside=x+9'd1<{1'b0,width} && y+8'd1<{1'b0,height};
                neighbor_address=address+{6'd0,width}+14'd1;end
        3:begin neighbor_inside=x!=0 && y+8'd1<{1'b0,height};
                neighbor_address=address+{6'd0,width}-14'd1;end
        endcase
    end
    envelope_y=$signed({2'b0,lobe_y})+$signed({6'd0,lobe_sample})-9'sd3;
end

always @(posedge I_clk or negedge I_rst_n) begin
    if(!I_rst_n) begin
        state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_has_palm<=0;
        O_center_x<=0;O_center_y<=0;O_radius_q4<=0;
        O_distance_valid<=0;O_distance_x<=0;O_distance_y<=0;O_distance_q4<=0;O_cycles<=0;
        width<=0;height<=0;x<=0;y<=0;address<=0;last_address<=0;
        reverse_pass<=0;neighbor<=0;best<=0;row_max<=0;row_x<=0;global_max<=0;
        search_rows<=0;lobe_y<=0;lobe_sample<=0;lobe_x<=0;
        setup_left<=0;setup_remainder<=0;
        e0<=0;e1<=0;e2<=0;e3<=0;e4<=0;e5<=0;e6<=0;
    end else if(I_clear) begin
        state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_has_palm<=0;
        O_distance_valid<=0;O_cycles<=0;
    end else begin
        O_done<=0;O_distance_valid<=0;
        if(O_busy)O_cycles<=O_cycles+32'd1;
        case(state)
        IDLE:if(I_start)begin
            O_busy<=1;O_fault<=0;O_has_palm<=0;O_cycles<=0;
            O_center_x<=0;O_center_y<=0;O_radius_q4<=0;
            if(I_width==0 || I_width>MAX_WIDTH || I_height==0 || I_height>MAX_HEIGHT)state<=FAIL;
            else begin
                width<=I_width;height<=I_height;search_rows<=0;
                setup_left<=I_height;setup_remainder<=0;
                x<=0;y<=0;address<=0;reverse_pass<=0;row_max<=0;row_x<=0;global_max<=0;
                state<=SETUP;
            end
        end
        // floor(0.82*height) once per transaction, using one small adder.
        SETUP:begin
            if(setup_sum>=8'd100)begin
                setup_remainder<=setup_sum-8'd100;search_rows<=search_rows+7'd1;
            end else setup_remainder<=setup_sum[6:0];
            setup_left<=setup_left-7'd1;
            if(setup_left==1)state<=LOAD;
        end
        LOAD:if(I_mask_valid)begin
            if(I_mask_last!=(x==width-1 && y==height-1))state<=FAIL;
            else if(x==width-1 && y==height-1)begin
                last_address<=address;x<=0;y<=0;address<=0;state<=CURRENT_READ;
            end else begin
                address<=address+14'd1;
                if(x==width-1)begin x<=0;y<=y+7'd1;end
                else x<=x+8'd1;
            end
        end
        CURRENT_READ:state<=CURRENT_EVAL;
        CURRENT_EVAL:begin
            best<=ram_q;neighbor<=0;
            state<=ram_q==0 ? COMMIT : NEIGHBOR_READ;
        end
        NEIGHBOR_READ:state<=NEIGHBOR_EVAL;
        NEIGHBOR_EVAL:begin
            if(neighbor_value<best)best<=neighbor_value;
            if(neighbor==3)state<=COMMIT;
            else begin neighbor<=neighbor+2'd1;state<=NEIGHBOR_READ;end
        end
        COMMIT:begin
            if(reverse_pass)begin
                O_distance_valid<=1;O_distance_x<=x;O_distance_y<=y;O_distance_q4<=quant_value;
                row_max<=next_row_max;row_x<=next_row_x;
                if(x==0)begin
                    row_info[y]<={next_row_x,(y<search_rows ? next_row_max : 11'd0)};
                    if(y<search_rows && next_row_max>=global_max)begin
                        global_max<=next_row_max;O_radius_q4<=next_row_max;
                        O_center_x<=next_row_x;O_center_y<=y;
                    end
                end
            end
            state<=ADVANCE;
        end
        ADVANCE:begin
            if(!reverse_pass)begin
                if(x==width-1 && y==height-1)begin
                    reverse_pass<=1;x<=width-1;y<=height-1;address<=last_address;
                    row_max<=0;row_x<=0;state<=CURRENT_READ;
                end else begin
                    address<=address+14'd1;
                    if(x==width-1)begin x<=0;y<=y+7'd1;end
                    else x<=x+8'd1;
                    state<=CURRENT_READ;
                end
            end else if(x==0 && y==0)begin
                lobe_y<=2;lobe_sample<=0;state<=height>=5 ? LOBE_READ : FINISH;
            end else begin
                address<=address-14'd1;
                if(x==0)begin x<=width-1;y<=y-7'd1;row_max<=0;row_x<=0;end
                else x<=x-8'd1;
                state<=CURRENT_READ;
            end
        end
        LOBE_READ:begin
            case(lobe_sample)
            0:e0<=envelope_value;1:e1<=envelope_value;2:e2<=envelope_value;
            3:begin e3<=envelope_value;lobe_x<=envelope_info[18:11];end
            4:e4<=envelope_value;5:e5<=envelope_value;6:e6<=envelope_value;
            endcase
            if(lobe_sample==6)state<=LOBE_EVAL;
            else lobe_sample<=lobe_sample+3'd1;
        end
        LOBE_EVAL:begin
            if(smooth_scaled>=global_scaled && smooth_here>=smooth_prev && smooth_here>smooth_next)begin
                O_center_x<=lobe_x;O_center_y<=lobe_y;O_radius_q4<=e3;state<=FINISH;
            end else if(lobe_y+7'd3>=height)state<=FINISH;
            else begin lobe_y<=lobe_y+7'd1;lobe_sample<=0;state<=LOBE_READ;end
        end
        FINISH:begin O_has_palm<=O_radius_q4>=11'd80;O_done<=1;O_busy<=0;state<=IDLE;end
        FAIL:begin O_fault<=1;O_has_palm<=0;O_done<=1;O_busy<=0;state<=IDLE;end
        default:state<=FAIL;
        endcase
    end
end
`ifndef SYNTHESIS
initial begin
    if(MAX_WIDTH<1 || MAX_WIDTH>160 || MAX_HEIGHT<1 || MAX_HEIGHT>90)
        $fatal(1,"palm distance geometry");
end
`endif
endmodule
