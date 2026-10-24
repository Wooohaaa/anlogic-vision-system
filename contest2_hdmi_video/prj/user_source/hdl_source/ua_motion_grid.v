// 32x32-pixel tiles; sampled 4px groups / every fourth row.
// Four changed samples qualify a tile. No additional frame RAM.
// Packed result: {camera_moving,box_valid,percent[6:0],xmin,xmax,ymin,ymax}.
`timescale 1ns/1ps
module ua_motion_grid #(
 parameter integer WIDTH=1280, HEIGHT=720, MIN_HITS=4
)(
 input clk,rst_n,sample_valid,hit,frame_done,camera_step,
 input [9:0] x_grp,y,
 output reg result_valid,
 output reg [52:0] result
);
 localparam integer COLS=(WIDTH+31)/32, ROWS=(HEIGHT+31)/32;
 localparam integer TILES=COLS*ROWS;
 reg [2:0] votes[0:COLS-1];
 reg [10:0] count;
 reg [10:0] xmin,xmax,ymin,ymax;
 wire [6:0] col=x_grp[9:3];
 wire first_sample=sample_valid && x_grp==0 && y<4;
 wire last_in_tile=(x_grp[2:0]==7 || x_grp==WIDTH/4-1) &&
                   (y[4:0]==31 || y==HEIGHT-1);
 wire qualifies=({1'b0,votes[col]}+{3'b0,hit})>=MIN_HITS;
 wire [10:0] tile_x0={1'b0,x_grp[9:3],5'b0};
 wire [10:0] tile_y0={y[9:5],5'b0};
 wire [10:0] tile_x1=(tile_x0+11'd31>=WIDTH)?WIDTH-1:tile_x0+11'd31;
 wire [10:0] tile_y1=(tile_y0+11'd31>=HEIGHT)?HEIGHT-1:tile_y0+11'd31;
 reg step_seen,finish;
 reg [1:0] camera_hold,box_hold;
 reg [10:0] held_count,accum;
 reg [6:0] iterations,percent;
 reg busy,output_camera,output_box;
 reg [43:0] output_bounds,last_bounds;
 wire [11:0] sum={1'b0,accum}+{1'b0,held_count};
 integer i;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin
   for(i=0;i<COLS;i=i+1)votes[i]<=0;
   count<=0;xmin<=WIDTH-1;xmax<=0;ymin<=HEIGHT-1;ymax<=0;
   step_seen<=0;finish<=0;camera_hold<=0;box_hold<=0;
   held_count<=0;accum<=0;iterations<=0;percent<=0;busy<=0;
   output_camera<=0;output_box<=0;output_bounds<=0;last_bounds<=0;
   result_valid<=0;result<=0;
  end else begin
   result_valid<=0;
   finish<=frame_done;
   if(camera_step)step_seen<=1;
   if(first_sample)begin
    for(i=0;i<COLS;i=i+1)votes[i]<=0;
    votes[0]<=hit?3'd1:3'd0;
    count<=0;xmin<=WIDTH-1;xmax<=0;ymin<=HEIGHT-1;ymax<=0;
   end else if(sample_valid && col<COLS)begin
    if(last_in_tile)begin
     votes[col]<=0;
     if(qualifies)begin
      count<=count+11'd1;
      if(tile_x0<xmin)xmin<=tile_x0;
      if(tile_x1>xmax)xmax<=tile_x1;
      if(tile_y0<ymin)ymin<=tile_y0;
      if(tile_y1>ymax)ymax<=tile_y1;
     end
    end else if(hit && votes[col]<MIN_HITS)votes[col]<=votes[col]+3'd1;
   end
   // One extra clock includes the last sample even without blanking.
   if(finish)begin
    output_camera<=step_seen || camera_step || camera_hold!=0;
    step_seen<=camera_step;
    if(step_seen || camera_step)camera_hold<=3;
    else if(camera_hold!=0)camera_hold<=camera_hold-1'b1;
    if(step_seen || camera_step || camera_hold!=0)begin
     held_count<=0;output_box<=0;box_hold<=0;
    end else begin
     held_count<=count;
     if(count!=0)begin
      output_box<=1;output_bounds<={xmin,xmax,ymin,ymax};
      last_bounds<={xmin,xmax,ymin,ymax};box_hold<=2;
     end else if(box_hold!=0)begin
      box_hold<=box_hold-1'b1;output_box<=1;output_bounds<=last_bounds;
     end else output_box<=0;
    end
    accum<=0;iterations<=0;percent<=0;busy<=1;
   end else if(busy)begin
    // Exactly 100 inexpensive add/compare cycles: floor(100*count/TILES).
    accum<=(sum>=TILES)?sum-TILES:sum;
    if(sum>=TILES)percent<=percent+7'd1;
    iterations<=iterations+7'd1;
    if(iterations==99)begin
     busy<=0;result_valid<=1;
     result<={output_camera,output_box,
       (sum>=TILES?percent+7'd1:percent),output_bounds};
    end
   end
  end
 end
endmodule

// Coherent bundled-data request/acknowledge mailbox. Source payload remains
// stable until acknowledgement; busy submissions drop, never tear a result.
module ua_motion_mailbox #(parameter integer WIDTH=53)(
 input src_clk,src_rst_n,src_valid,input [WIDTH-1:0] src_data,
 input dst_clk,dst_rst_n,output reg dst_valid,output reg [WIDTH-1:0] dst_data
);
 reg [WIDTH-1:0] held;
 reg request,ack;
 (* async_reg="true" *) reg ack0,ack1,req0,req1;
 reg req2;
 always @(posedge src_clk or negedge src_rst_n)begin
  if(!src_rst_n)begin request<=0;ack0<=0;ack1<=0;held<=0;end
  else begin
   ack0<=ack;ack1<=ack0;
   if(src_valid && request==ack1)begin held<=src_data;request<=~request;end
  end
 end
 always @(posedge dst_clk or negedge dst_rst_n)begin
  if(!dst_rst_n)begin req0<=0;req1<=0;req2<=0;ack<=0;dst_valid<=0;dst_data<=0;end
  else begin
   req0<=request;req1<=req0;req2<=req1;dst_valid<=0;
   if(req2!=ack)begin dst_data<=held;dst_valid<=1;ack<=req2;end
  end
 end
endmodule
