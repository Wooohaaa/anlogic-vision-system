`timescale 1ns/1ps
// Wrist direction from a replay of the selected component's cropped mask.
// All coordinates are local to its bbox. Match the integer reference exactly:
// foreground below cy+0.3R and below 0.8*height; independent median x and y.
// Odd/even medians are represented in half-pixel units, without division RAM.
// One transaction at a time; valid && ready transfers a pixel, exact last.
// clear aborts; start is accepted only idle. Histogram storage is cleared by
// the FSM, not reset; outputs are meaningful with done && !fault.
module ua_hand_wrist_median(
 input I_clk,I_rst_n,I_clear,I_start,
 input[7:0] I_width,I_center_x,
 input[6:0] I_height,I_center_y,
 input[10:0] I_radius_q4,
 input I_mask_valid,I_mask,I_mask_last,
 output O_mask_ready,
 output reg O_busy,O_done,O_fault,
 output reg[13:0] O_lower_count,
 output reg[8:0] O_wrist_x2,O_wrist_y2,
 output reg signed[9:0] O_direction_x2,O_direction_y2
);
localparam IDLE=0,CLEAR=1,LOAD=2,XREAD=3,XWRITE=4,YREAD=5,YWRITE=6,
           NEXT=7,SCAN_READ=8,SCAN_EVAL=9,FINISH=10,FAIL=11;
reg[3:0]state;
reg[7:0]width,cx,x,index;
reg[6:0]height,cy,y;
reg[10:0]radius;
reg last_pixel,axis;
reg[4:0]hist_x_q;
reg[7:0]hist_y_q;
wire[7:0]hist_q=axis ? hist_y_q : {3'd0,hist_x_q};
reg[14:0]prefix;
reg[7:0]low_index,high_index;
reg low_found,high_found;
// The lower-fifth gate admits at most 18 rows. Per-column count fits 5 bits;
// each row contains at most 160 pixels, so its count fits 8 bits.
(* ram_style="dram" *) reg[4:0]hist_x[0:159];
(* ram_style="dram" *) reg[7:0]hist_y[0:89];
wire[7:0]hist_x_read_address=state==SCAN_READ ? index : x;
wire[6:0]hist_y_read_address=state==SCAN_READ ? index[6:0] : y;
wire[7:0]hist_x_write_address=state==CLEAR ? index : x;
wire[6:0]hist_y_write_address=state==CLEAR ? index[6:0] : y;
wire[15:0]y160=({9'd0,y}<<7)+({9'd0,y}<<5);
wire[15:0]cy160=({9'd0,cy}<<7)+({9'd0,cy}<<5);
wire[15:0]radius3=({5'd0,radius}<<1)+{5'd0,radius};
wire[9:0]y5=({3'd0,y}<<2)+{3'd0,y};
wire eligible=I_mask && y160>=cy160+radius3 && y5>={1'b0,height,2'b00};
wire[13:0]k_low=(O_lower_count-14'd1)>>1;
wire[13:0]k_high=O_lower_count>>1;
wire[14:0]next_prefix=prefix+{7'd0,hist_q};
wire hit_low=!low_found && next_prefix>{1'b0,k_low};
wire hit_high=!high_found && next_prefix>{1'b0,k_high};
wire[8:0]median2={1'b0,(hit_low ? index : low_index)}+
                    {1'b0,(hit_high ? index : high_index)};
assign O_mask_ready=state==LOAD;
always @(posedge I_clk)begin
 if(state==CLEAR || state==XWRITE)
  hist_x[hist_x_write_address]<=state==CLEAR ? 5'd0 : hist_x_q+5'd1;
 if((state==CLEAR && index<90) || state==YWRITE)
  hist_y[hist_y_write_address]<=state==CLEAR ? 8'd0 : hist_y_q+8'd1;
 if(state==XREAD || (state==SCAN_READ && !axis))hist_x_q<=hist_x[hist_x_read_address];
 if(state==YREAD || (state==SCAN_READ && axis))hist_y_q<=hist_y[hist_y_read_address];
end
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
  state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_lower_count<=0;
  O_wrist_x2<=0;O_wrist_y2<=0;O_direction_x2<=0;O_direction_y2<=0;
  width<=0;height<=0;cx<=0;cy<=0;radius<=0;x<=0;y<=0;index<=0;
  last_pixel<=0;axis<=0;prefix<=0;low_index<=0;high_index<=0;low_found<=0;high_found<=0;
 end else if(I_clear)begin
  state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_lower_count<=0;
 end else begin
  O_done<=0;
  case(state)
  IDLE:if(I_start)begin
   O_busy<=1;O_fault<=0;O_lower_count<=0;
   O_wrist_x2<=0;O_wrist_y2<=0;O_direction_x2<=0;O_direction_y2<=0;
   if(I_width==0 || I_width>160 || I_height==0 || I_height>90 ||
      I_center_x>=I_width || I_center_y>=I_height)state<=FAIL;
   else begin
    width<=I_width;height<=I_height;cx<=I_center_x;cy<=I_center_y;radius<=I_radius_q4;
    index<=0;x<=0;y<=0;state<=CLEAR;
   end
  end
  CLEAR:if(index==159)state<=LOAD;else index<=index+8'd1;
  LOAD:if(I_mask_valid)begin
   last_pixel<=x==width-1 && y==height-1;
   if(I_mask_last!=(x==width-1 && y==height-1))state<=FAIL;
   else state<=eligible ? XREAD : NEXT;
  end
  XREAD:state<=XWRITE;
  XWRITE:state<=YREAD;
  YREAD:state<=YWRITE;
  YWRITE:begin O_lower_count<=O_lower_count+14'd1;state<=NEXT;end
  NEXT:if(last_pixel)begin
   if(O_lower_count==0)begin
    O_wrist_x2<={cx,1'b0};O_wrist_y2<=({2'd0,cy}+{2'd0,radius[10:4]})<<1;
    state<=FINISH;
   end else begin
    axis<=0;index<=0;prefix<=0;low_found<=0;high_found<=0;
    low_index<=0;high_index<=0;state<=SCAN_READ;
   end
  end else begin
   if(x==width-1)begin x<=0;y<=y+7'd1;end else x<=x+8'd1;
   state<=LOAD;
  end
  SCAN_READ:state<=SCAN_EVAL;
  SCAN_EVAL:begin
   prefix<=next_prefix;
   if(hit_low)begin low_index<=index;low_found<=1;end
   if(hit_high)begin
    high_index<=index;high_found<=1;
    if(!axis)begin
     O_wrist_x2<=median2;axis<=1;index<=0;prefix<=0;
     low_found<=0;high_found<=0;low_index<=0;high_index<=0;state<=SCAN_READ;
    end else begin O_wrist_y2<=median2;state<=FINISH;end
   end else if((!axis && index==width-1) || (axis && index==height-1))state<=FAIL;
   else begin index<=index+8'd1;state<=SCAN_READ;end
  end
  FINISH:begin
   O_direction_x2<=$signed({1'b0,O_wrist_x2})-$signed({1'b0,cx,1'b0});
   O_direction_y2<=$signed({1'b0,O_wrist_y2})-$signed({2'd0,cy,1'b0});
   O_busy<=0;O_done<=1;state<=IDLE;
  end
  FAIL:begin O_fault<=1;O_busy<=0;O_done<=1;state<=IDLE;end
  default:state<=FAIL;
  endcase
 end
end
endmodule
