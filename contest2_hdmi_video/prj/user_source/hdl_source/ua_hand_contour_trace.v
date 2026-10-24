`timescale 1ns/1ps
// Moore 8-neighbour external contour. Anchor must be the chosen component's
// earliest raster pixel (CCL output), NOT its bounding-box corner.
// One outstanding variable-latency mask read; bank is immutable for the walk.
// Emits every boundary step, including repeated articulation points. The final
// duplicate start pixel is not emitted (directed-edge/Jacob stopping criterion).
// No frame/contour RAM here. Geometry consumer supplies its own bounded storage.
module ua_hand_contour_trace #(
    parameter WIDTH=160, HEIGHT=90, MAX_STEPS=8192, OPENCV_ORDER=0
)(
    input I_clk,I_rst_n,I_clear,I_start,I_mode,
    input [7:0] I_anchor_x,
    input [6:0] I_anchor_y,
    output reg O_read,
    output reg [11:0] O_read_addr,
    input I_read_valid,
    input [17:0] I_read_data,
    output reg O_busy,O_done,O_fault,O_vertex_valid,
    output reg [7:0] O_x,
    output reg [6:0] O_y,
    output reg [13:0] O_count
);
localparam ROW_WORDS=(WIDTH+5)/6;
localparam IDLE=0, CHECK_ANCHOR=1, REQUEST=2, RESPONSE=3,
           PREPARE=4, EVALUATE=5, NEXT=6, FAIL=7;
reg [2:0] state,after_read;
reg mode,foreground,started;
reg [7:0] px,sx;
reg [6:0] py,sy;
reg [2:0] direction,backtrack,attempt,first_direction,read_slot;
reg signed [9:0] nx,ny;
reg signed [9:0] dx,dy;
always @* begin
    dx=0;dy=0;
    case(direction)
    0:dx=1;
    1:begin dx=1;dy=1;end
    2:dy=1;
    3:begin dx=-1;dy=1;end
    4:dx=-1;
    5:begin dx=-1;dy=-1;end
    6:dy=-1;
    7:begin dx=1;dy=-1;end
    endcase
    nx=$signed({2'd0,px})+dx;
    ny=$signed({3'd0,py})+dy;
end
wire [17:0] read_pixel=I_read_data >> (read_slot*3);
always @(posedge I_clk or negedge I_rst_n) begin
    if(!I_rst_n) begin
        state<=IDLE;O_read<=0;O_read_addr<=0;O_busy<=0;O_done<=0;
        O_fault<=0;O_vertex_valid<=0;O_x<=0;O_y<=0;O_count<=0;
    end else if(I_clear) begin
        state<=IDLE;O_read<=0;O_busy<=0;O_done<=0;O_fault<=0;
        O_vertex_valid<=0;O_count<=0;
    end else begin
        O_read<=0;O_done<=0;O_vertex_valid<=0;
        case(state)
        IDLE:if(I_start)begin
            O_busy<=1;O_fault<=0;O_count<=0;mode<=I_mode;
            px<=I_anchor_x;py<=I_anchor_y;sx<=I_anchor_x;sy<=I_anchor_y;
            started<=0;backtrack<=4;state<=CHECK_ANCHOR;
        end
        CHECK_ANCHOR:begin
            if(px>=WIDTH || py>=HEIGHT)state<=FAIL;
            else begin
                O_read_addr<=py*ROW_WORDS+px/6;read_slot<=px%6;
                after_read<=NEXT;state<=REQUEST;
            end
        end
        REQUEST:begin O_read<=1;state<=RESPONSE;end
        RESPONSE:if(I_read_valid)begin
            foreground<=mode ? read_pixel[2] : read_pixel[0];state<=after_read;
        end
        NEXT:begin
            if(!foreground)state<=FAIL;
            else begin direction<=OPENCV_ORDER ? backtrack-3'd1 : backtrack+3'd1;attempt<=0;state<=PREPARE;end
        end
        PREPARE:begin
            if(nx<0 || ny<0 || nx>=WIDTH || ny>=HEIGHT)begin
                foreground<=0;state<=EVALUATE;
            end else begin
                O_read_addr<=ny*ROW_WORDS+nx/6;read_slot<=nx%6;
                after_read<=EVALUATE;state<=REQUEST;
            end
        end
        EVALUATE:begin
            if(foreground)begin
                if(started && px==sx && py==sy && direction==first_direction)begin
                    O_busy<=0;O_done<=1;state<=IDLE;
                end else if(O_count==MAX_STEPS)state<=FAIL;
                else begin
                    O_vertex_valid<=1;O_x<=px;O_y<=py;O_count<=O_count+14'd1;
                    if(!started)begin first_direction<=direction;started<=1;end
                    px<=nx[7:0];py<=ny[6:0];
                    backtrack<=OPENCV_ORDER ? {(direction[2:1]+2'd1+{1'b0,direction[0]}),1'b0} :
                                              {(direction[2:1]+2'd3),1'b0};
                    // Every accepted neighbour is known foreground.
                    state<=NEXT;
                end
            end else if(attempt==7)begin
                if(started)state<=FAIL;
                else begin
                    // Single-pixel component is a valid degenerate contour.
                    O_vertex_valid<=1;O_x<=px;O_y<=py;O_count<=1;
                    O_busy<=0;O_done<=1;state<=IDLE;
                end
            end else begin
                direction<=OPENCV_ORDER ? direction-3'd1 : direction+3'd1;attempt<=attempt+3'd1;state<=PREPARE;
            end
        end
        FAIL:begin O_busy<=0;O_done<=1;O_fault<=1;state<=IDLE;end
        default:state<=FAIL;
        endcase
    end
end
`ifndef SYNTHESIS
initial begin
    if(WIDTH<2 || WIDTH>160 || HEIGHT<2 || HEIGHT>90 || MAX_STEPS<1 || MAX_STEPS>8192)
        $fatal(1,"contour geometry/limit");
end
`endif
endmodule
