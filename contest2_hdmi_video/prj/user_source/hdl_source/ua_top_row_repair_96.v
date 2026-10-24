`ifndef UA_TOP_ROW_REPAIR_96_V
`define UA_TOP_ROW_REPAIR_96_V
// Conservative legacy-demosaic boundary repair. Row 0 is replaced by row 1;
// rows 1..H-1 are bit-exact. Three circular rows / two-row lookahead avoid
// a 96-bit bypass mux and two 96-bit pipeline registers in the tight LUT budget.
// Complete raster, no backpressure; allow 2*WIDTH/4+2 blank clocks after EOF.
// SOF aborts any stale/partial frame. RAM is never reset or read as valid
// before a complete preceding row has been written in the current frame.
module ua_top_row_repair_96 #(parameter IMG_WIDTH=1280,IMG_HEIGHT=720)(
 input clk,rst_n,input[95:0]rgb,input valid,sof,eol,
 output wire[95:0]out_rgb,output reg out_valid,out_sof,out_eol
);
 localparam G=IMG_WIDTH/4,AW=(G<=1)?1:$clog2(G),YW=(IMG_HEIGHT<=1)?1:$clog2(IMG_HEIGHT),MAW=$clog2(3*G);
 /* fehdl force_ram=1, ram_style="bram" */ reg[95:0] row_mem[0:3*G-1];
 reg[AW-1:0]x,flush_x;
 reg[MAW-1:0]read_addr;
 reg[YW-1:0]y;
 reg flushing,frame_live,flush_last;
 reg[1:0]write_bank,read_bank;
 wire[AW-1:0]ix=sof?{AW{1'b0}}:x;
 wire[YW-1:0]iy=sof?{YW{1'b0}}:y;
 wire take_input=valid && (sof || frame_live);
 wire take_flush=flushing && !take_input;
 wire[1:0]wb=sof?2'd0:write_bank;
 wire[1:0]rb=sof?2'd1:read_bank;
 wire[MAW-1:0]write_base=wb==0?0:wb==1?G:2*G;
 wire[MAW-1:0]read_base=rb==0?0:rb==1?G:2*G;
 wire emit_input=take_input && iy>=2;
 assign out_rgb=row_mem[read_addr];
 always @(posedge clk)begin
  if(emit_input || take_flush)read_addr<=read_base+(take_input?ix:flush_x);
  if(take_input)row_mem[write_base+ix]<=rgb;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   x<=0;y<=0;flush_x<=0;flushing<=0;frame_live<=0;flush_last<=0;
   write_bank<=0;read_bank<=1;
   out_valid<=0;out_sof<=0;out_eol<=0;
  end else begin
   out_valid<=emit_input || take_flush;
   out_sof<=(emit_input && iy==2 && ix==0) ||
       (IMG_HEIGHT==2 && take_flush && !flush_last && flush_x==0);
   out_eol<=emit_input?(ix==G-1):(take_flush && flush_x==G-1);
   if(take_input)begin
    if(sof)begin frame_live<=1;flushing<=0;write_bank<=0;read_bank<=1;end
    if(ix==G-1)begin
     x<=0;
     write_bank<=wb==2?2'd0:wb+1'b1;
     // input row2 -> output row0 using row1; row3 -> output row1,
     // then advance the circular read bank once per output row.
     if(iy>=3)read_bank<=rb==2?2'd0:rb+1'b1;
     if(iy==IMG_HEIGHT-1)begin
      y<=0;flushing<=1;flush_x<=0;frame_live<=0;flush_last<=0;
     end else y<=iy+1'b1;
    end else begin x<=ix+1'b1;y<=iy;end
    // An early EOL makes the frame unusable; wait for a new SOF.
    if(eol && ix!=G-1)begin frame_live<=0;flushing<=0;end
   end else if(take_flush)begin
    if(flush_x==G-1)begin
     flush_x<=0;
     if(flush_last)flushing<=0;
     else begin
      flush_last<=1;
      // H=2 repeats row1 for both rows; otherwise flush the final two.
      if(IMG_HEIGHT!=2)read_bank<=rb==2?2'd0:rb+1'b1;
     end
    end
    else flush_x<=flush_x+1'b1;
   end
  end
 end
endmodule
`endif
