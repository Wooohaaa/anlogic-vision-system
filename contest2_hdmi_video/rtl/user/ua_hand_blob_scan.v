// Serial 8-connected run-length CCL for the 160x90 detection raster.
// No video backpressure: the caller owns a completed, immutable mask bank.
// Read protocol: O_read is a one-cycle request; response may be delayed but
// must occur once, in order. Only one request is outstanding. start when idle.
// mode=0 selects seed bit, mode=1 selects grown bit; seed_count always uses bit0.
// Inclusive bounding boxes. Blob pulses are provisional until done && !overflow.
// Bounded storage: 16 runs/row, 15 live union labels; overflow aborts explicitly.
// Distributed metadata is never bulk-reset; validity and parent roots are reset.
module ua_hand_blob_scan #(
    parameter WIDTH=160, HEIGHT=90, RGB_STATS=0
) (
    input I_clk, I_rst_n, I_clear, I_start, I_mode,
    output reg O_read,
    output reg [11:0] O_read_addr,
    input I_read_valid,
    input [17:0] I_read_data,
    output reg O_busy, O_done, O_overflow, O_blob_valid,
    output reg [13:0] O_area, O_seed_count,
    output reg [7:0] O_xmin, O_xmax,
    output reg [6:0] O_ymin, O_ymax,
    output reg [7:0] O_anchor_x,
    output reg [6:0] O_anchor_y,
    // Optional exact selected-component red statistics. Read only foreground
    // pixels, address y*WIDTH+x, one outstanding variable-latency response.
    // Output (like all blob fields) is provisional until done&&!overflow.
    output reg O_red_read,output reg[13:0]O_red_addr,
    input I_red_valid,input[9:0]I_red_data,output reg[23:0]O_red_sum
);
localparam ROW_WORDS=(WIDTH+5)/6,META_BITS=RGB_STATS ? 24 : 18;
localparam[2:0]LAST_FIELD=RGB_STATS ? 3'd5 : 3'd4;
localparam IDLE=0, REQUEST=1, RECEIVE=2, PIXEL=3, ADVANCE=4,
           OVERLAP=5, ROOT=6, RESOLVED=7, MERGE_KEEP=8, MERGE_DROP=9,
           ALLOC=10, ADD=11, APPEND=12, COMPRESS=13, COMPRESSED=14,
           RETIRE=15, EMIT=16, NEXT_ROW=17, FAIL=18,RED_CHECK=19,RED_WAIT=20;
reg [4:0] state, return_state;
reg mode, prev_role, run_active, new_label;
reg [7:0] x, run_start, run_end;
reg [6:0] y;
reg [2:0] slot;
reg [11:0] address;
reg [17:0] word_data;
reg [7:0] run_seeds;
reg[17:0]run_red_sum;reg[9:0]pixel_red;
reg [4:0] prev_count, cur_count, scan_index, compress_index;
reg [3:0] label_run, root_label, keep_label, drop_label, label_index;
reg [3:0] root_depth;
reg [2:0] field;
reg [META_BITS-1:0] keep_value;
reg [15:0] active, seen;
reg [3:0] parent [0:15];
(* ram_style="dram" *) reg [19:0] runs [0:31];
(* ram_style="dram" *) reg [META_BITS-1:0] metadata [0:127];
wire [19:0] previous_run=runs[{prev_role,scan_index[3:0]}];
wire [19:0] current_run=runs[{!prev_role,compress_index[3:0]}];
wire [2:0] pixel_bits=(word_data >> (slot*3));
wire foreground=mode ? pixel_bits[2] : pixel_bits[0];
wire [8:0] run_length={1'b0,run_end}-{1'b0,run_start}+9'd1;
// Native raster address is constant 160*y+x. Spell the shifts explicitly so
// TD does not allocate a DSP for a frame-statistics address generator.
wire[13:0]red_row_address=WIDTH==160 ? (({7'd0,y}<<7)+({7'd0,y}<<5)) : y*WIDTH;
// The FSM reads only one metadata label per cycle. Express that as one port,
// rather than letting synthesis replicate DRAM for three simultaneous ports.
wire [3:0] metadata_label=state==MERGE_KEEP ? keep_label :
                          state==MERGE_DROP ? drop_label :
                          state==EMIT ? label_index : label_run;
wire [META_BITS-1:0] metadata_value=metadata[{metadata_label,field}];
wire [META_BITS-1:0] add_value=metadata_value;
wire [META_BITS-1:0] drop_value=metadata_value;
integer i;
always @(posedge I_clk or negedge I_rst_n) begin
    if(!I_rst_n) begin
        state<=IDLE; O_busy<=0; O_done<=0; O_overflow<=0;
        O_blob_valid<=0; O_read<=0; O_read_addr<=0;
        O_area<=0; O_seed_count<=0; O_xmin<=0; O_xmax<=0;
        O_ymin<=0; O_ymax<=0; active<=0; seen<=0;
        O_anchor_x<=0; O_anchor_y<=0;
        O_red_read<=0;O_red_addr<=0;O_red_sum<=0;run_red_sum<=0;pixel_red<=0;
    end else if(I_clear) begin
        state<=IDLE; O_busy<=0; O_done<=0; O_overflow<=0;
        O_blob_valid<=0; O_read<=0; active<=0; seen<=0;
        O_red_read<=0;O_red_sum<=0;
    end else begin
        O_done<=0; O_read<=0; O_blob_valid<=0;O_red_read<=0;
        case(state)
        IDLE: if(I_start) begin
            O_busy<=1; O_overflow<=0; active<=0; seen<=0;
            for(i=0;i<16;i=i+1) parent[i]<=i;
            mode<=I_mode; x<=0; y<=0; slot<=0; address<=0;
            prev_role<=0; prev_count<=0; cur_count<=0;
            run_active<=0; run_seeds<=0;run_red_sum<=0;O_red_sum<=0;state<=REQUEST;
        end
        REQUEST: begin O_read<=1; O_read_addr<=address; state<=RECEIVE; end
        RECEIVE: if(I_read_valid) begin word_data<=I_read_data;state<=RGB_STATS ? RED_CHECK : PIXEL;end
        RED_CHECK:if(foreground)begin O_red_read<=1;O_red_addr<=red_row_address+{6'd0,x};state<=RED_WAIT;end
                  else state<=PIXEL;
        RED_WAIT:if(I_red_valid)begin pixel_red<=I_red_data;state<=PIXEL;end
        PIXEL: begin
            if(foreground) begin
                if(!run_active) begin
                    run_start<=x; run_seeds<={7'd0,pixel_bits[0]};
                    if(RGB_STATS)run_red_sum<={8'd0,pixel_red};
                end else begin
                    run_seeds<=run_seeds+{7'd0,pixel_bits[0]};
                    if(RGB_STATS)run_red_sum<=run_red_sum+{8'd0,pixel_red};
                end
                run_active<=1; run_end<=x;
            end
            if((!foreground && run_active) || (foreground && x==WIDTH-1)) begin
                scan_index<=0; label_run<=0; new_label<=0;
                run_active<=0; state<=OVERLAP;
            end else state<=ADVANCE;
        end
        ADVANCE: begin
            if(x==WIDTH-1) begin
                compress_index<=0; seen<=0; state<=COMPRESS;
            end else begin
                x<=x+8'd1;
                if(slot==5) begin slot<=0; address<=address+12'd1; state<=REQUEST; end
                else begin slot<=slot+3'd1;state<=RGB_STATS ? RED_CHECK : PIXEL;end
            end
        end
        OVERLAP: begin
            if(scan_index==prev_count) begin
                if(label_run==0) begin label_index<=1; state<=ALLOC; end
                else begin field<=0; new_label<=0; state<=ADD; end
            end else if(({1'b0,previous_run[15:8]}+9'd1 >= {1'b0,run_start}) &&
                        ({1'b0,run_end}+9'd1 >= {1'b0,previous_run[7:0]})) begin
                root_label<=previous_run[19:16]; root_depth<=0;
                return_state<=RESOLVED; state<=ROOT;
            end else scan_index<=scan_index+5'd1;
        end
        ROOT: begin
            if(parent[root_label]==root_label) state<=return_state;
            else if(root_depth==15) state<=FAIL;
            else begin root_label<=parent[root_label]; root_depth<=root_depth+4'd1; end
        end
        RESOLVED: begin
            if(label_run==0) begin
                label_run<=root_label; scan_index<=scan_index+5'd1; state<=OVERLAP;
            end else if(label_run==root_label) begin scan_index<=scan_index+5'd1; state<=OVERLAP; end
            else begin
                keep_label<=label_run<root_label ? label_run : root_label;
                drop_label<=label_run<root_label ? root_label : label_run;
                label_run<=label_run<root_label ? label_run : root_label;
                field<=0; state<=MERGE_KEEP;
            end
        end
        MERGE_KEEP: begin keep_value<=metadata_value; state<=MERGE_DROP; end
        MERGE_DROP: begin
            case(field)
            0,1,5: metadata[{keep_label,field}]<=keep_value+drop_value;
            2: metadata[{keep_label,field}]<={2'd0,
                 keep_value[15:8]>drop_value[15:8] ? keep_value[15:8] : drop_value[15:8],
                 keep_value[7:0]<drop_value[7:0] ? keep_value[7:0] : drop_value[7:0]};
            3: metadata[{keep_label,field}]<={4'd0,
                 keep_value[13:7]>drop_value[13:7] ? keep_value[13:7] : drop_value[13:7],
                 keep_value[6:0]<drop_value[6:0] ? keep_value[6:0] : drop_value[6:0]};
            4: metadata[{keep_label,field}]<=keep_value<drop_value ? keep_value : drop_value;
            endcase
            if(field==LAST_FIELD) begin
                parent[drop_label]<=keep_label;
                scan_index<=scan_index+5'd1; state<=OVERLAP;
            end else begin field<=field+3'd1; state<=MERGE_KEEP; end
        end
        ALLOC: begin
            if(!active[label_index]) begin
                active[label_index]<=1; parent[label_index]<=label_index;
                label_run<=label_index; new_label<=1; field<=0; state<=ADD;
            end else if(label_index==15) state<=FAIL;
            else label_index<=label_index+4'd1;
        end
        ADD: begin
            case(field)
            0: metadata[{label_run,field}] <= (new_label ? 18'd0 : add_value)+{9'd0,run_length};
            1: metadata[{label_run,field}] <= (new_label ? 18'd0 : add_value)+{10'd0,run_seeds};
            2: metadata[{label_run,field}] <= {2'd0,
                (new_label || run_end>add_value[15:8]) ? run_end : add_value[15:8],
                (new_label || run_start<add_value[7:0]) ? run_start : add_value[7:0]};
            3: metadata[{label_run,field}] <= {4'd0,y,new_label ? y : add_value[6:0]};
            // Earliest raster pixel, not the bounding-box corner. Required to
            // trace the selected component even when another lies in its box.
            4: metadata[{label_run,field}] <= new_label ? {3'd0,y,run_start} : add_value;
            5: metadata[{label_run,field}] <= (new_label ? {META_BITS{1'b0}} : add_value)+run_red_sum;
            endcase
            if(field==LAST_FIELD) state<=APPEND;
            else field<=field+3'd1;
        end
        APPEND: begin
            if(cur_count==16) state<=FAIL;
            else begin
                runs[{!prev_role,cur_count[3:0]}]<={label_run,run_end,run_start};
                cur_count<=cur_count+5'd1; state<=ADVANCE;
            end
        end
        COMPRESS: begin
            if(compress_index==cur_count) begin label_index<=1; state<=RETIRE; end
            else begin
                root_label<=current_run[19:16]; root_depth<=0;
                return_state<=COMPRESSED; state<=ROOT;
            end
        end
        COMPRESSED: begin
            runs[{!prev_role,compress_index[3:0]}]<={root_label,current_run[15:0]};
            seen[root_label]<=1; compress_index<=compress_index+5'd1; state<=COMPRESS;
        end
        RETIRE: begin
            if(active[label_index]) begin
                if(parent[label_index]!=label_index) active[label_index]<=0;
                else if(!seen[label_index] || y==HEIGHT-1) begin
                    field<=0; state<=EMIT;
                end
            end
            if(!(active[label_index] && parent[label_index]==label_index &&
                 (!seen[label_index] || y==HEIGHT-1))) begin
                if(label_index==15) state<=NEXT_ROW;
                else label_index<=label_index+4'd1;
            end
        end
        EMIT: begin
            case(field)
            0: O_area<=metadata_value[13:0];
            1: O_seed_count<=metadata_value[13:0];
            2: begin O_xmin<=metadata_value[7:0]; O_xmax<=metadata_value[15:8]; end
            3: begin O_ymin<=metadata_value[6:0]; O_ymax<=metadata_value[13:7]; end
            4: begin O_anchor_x<=metadata_value[7:0]; O_anchor_y<=metadata_value[14:8]; end
            5:O_red_sum<=metadata_value;
            endcase
            if(field==LAST_FIELD) begin
                O_blob_valid<=1; active[label_index]<=0;
                if(label_index==15) state<=NEXT_ROW;
                else begin label_index<=label_index+4'd1; state<=RETIRE; end
            end else field<=field+3'd1;
        end
        NEXT_ROW: begin
            if(y==HEIGHT-1) begin O_done<=1; O_busy<=0; state<=IDLE; end
            else begin
                y<=y+7'd1; x<=0; slot<=0; address<=address+12'd1;
                prev_role<=!prev_role; prev_count<=cur_count; cur_count<=0;
                run_active<=0; run_seeds<=0; state<=REQUEST;
            end
        end
        FAIL: begin O_overflow<=1; O_done<=1; O_busy<=0; state<=IDLE; end
        default: state<=FAIL;
        endcase
    end
end
`ifndef SYNTHESIS
initial begin
    if(WIDTH<2 || WIDTH>160 || HEIGHT<2 || HEIGHT>90) $fatal(1,"CCL geometry");
end
`endif
endmodule
