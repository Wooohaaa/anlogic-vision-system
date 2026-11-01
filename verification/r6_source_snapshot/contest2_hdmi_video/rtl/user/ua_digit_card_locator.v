// Dark ink runs bounded by nearby neutral light pixels. Row clusters locate
// the digit itself, independently of tilted phone/card outer corners.
`timescale 1ns/1ps
module ua_digit_card_locator #(
 parameter integer WIDTH=1280,HEIGHT=720,MIN_GROUPS=2,MAX_GROUPS=128,GAP_GROUPS=4
)(input clk,rst_n,valid,sof,eol,white,dark,input[9:0]x,y,
 output reg found,output reg[9:0]x0,x1,y0,y1);
 localparam integer IMAGE_XW=(WIDTH/4<=2)?1:$clog2(WIDTH/4);
 localparam integer LIMIT_XW=(MAX_GROUPS<=2)?1:$clog2(MAX_GROUPS+1);
 localparam integer XW=(IMAGE_XW>LIMIT_XW)?IMAGE_XW:LIMIT_XW;
 localparam[XW:0]MIN_W=MIN_GROUPS,MAX_W=MAX_GROUPS;
 reg run_on,run_two,row_on,cand_on,best_on;
 reg[XW-1:0]run0,run1,row0,row1,cx0,cx1,bx0,bx1;
 reg[9:0]cy0,cy1,by0,by1;
 reg[2:0]white_age,tail_gap;
 reg[7:0]rows;
 wire[XW:0]run_w={1'b0,run1}-{1'b0,run0}+1'b1;
 wire[XW:0]row_w={1'b0,row1}-{1'b0,row0}+1'b1;
 wire close_run=white && run_on && run_two && run_w>=MIN_W && run_w<=MAX_W;
 wire[XW-1:0]join0=(run0<row0)?run0:row0,join1=(run1>row1)?run1:row1;
 wire[XW:0]join_w={1'b0,join1}-{1'b0,join0}+1'b1;
 wire run_matches=cand_on && ({1'b0,run1}+11'd4>={1'b0,cx0}) && ({1'b0,cx1}+11'd4>={1'b0,run0});
 wire row_matches=cand_on && ({1'b0,row1}+11'd4>={1'b0,cx0}) && ({1'b0,cx1}+11'd4>={1'b0,row0});
 wire near_runs=({1'b0,run0}<={1'b0,row1}+11'd16) && ({1'b0,row0}<={1'b0,run1}+11'd16);
 wire use_join=close_run && row_on && join_w<=MAX_W && (near_runs || (run_matches && row_matches));
 wire use_new=close_run && (!row_on || (!use_join && ((run_matches && !row_matches) || (run_matches==row_matches && run_w>row_w))));
 wire[XW-1:0]rx0=use_join?join0:use_new?run0:row0;
 wire[XW-1:0]rx1=use_join?join1:use_new?run1:row1;
 wire row_good=row_on || close_run;
 wire[XW:0]cw={1'b0,cx1}-{1'b0,cx0}+1'b1;
 wire[10:0]ch={1'b0,cy1}-{1'b0,cy0}+11'd4;
 wire[10:0]bh={1'b0,by1}-{1'b0,by0}+11'd4;
 wire[XW+1:0]twice_cw={cw,1'b0};
 wire[XW+4:0]sixteen_cw={cw,4'b0000};
 wire cand_good=cand_on && rows>=8'd12 && cw>=MIN_W && cw<=MAX_W &&
  ch>=11'd64 && ch<=11'd640 && (cw+twice_cw)<=ch && ch<=sixteen_cw &&
  rows>=(ch>>3) && cx0>0 && cx1<WIDTH/4-1 && cy0>0 && cy1<HEIGHT-3;
 wire[10:0]row_gap={1'b0,y}-{1'b0,cy1};
 wire[XW-1:0]merged0=(rx0<cx0)?rx0:cx0,merged1=(rx1>cx1)?rx1:cx1;
 wire[XW:0]merged_w={1'b0,merged1}-{1'b0,merged0}+1'b1;
 // Successive stroke rows must overlap horizontally (16px tolerance).
 // Width alone used to join unrelated background bands to the digit.
 wire row_overlaps=({1'b0,rx1}+11'd4>={1'b0,cx0}) &&
                   ({1'b0,cx1}+11'd4>={1'b0,rx0});
 wire associate=cand_on && row_good && row_overlaps && row_gap<=11'd32 && merged_w<=MAX_W;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   run_on<=0;run_two<=0;row_on<=0;cand_on<=0;best_on<=0;
   run0<=0;run1<=0;row0<=0;row1<=0;cx0<=0;cx1<=0;cy0<=0;cy1<=0;
   bx0<=0;bx1<=0;by0<=0;by1<=0;white_age<=7;tail_gap<=0;rows<=0;
   found<=0;x0<=0;x1<=0;y0<=0;y1<=0;
  end else if(valid)begin
   if(sof)begin
    run_on<=0;run_two<=0;row_on<=0;cand_on<=0;best_on<=0;
    white_age<=7;tail_gap<=0;rows<=0;
   end else if(eol)begin
    run_on<=0;run_two<=0;row_on<=0;white_age<=7;tail_gap<=0;
    if(y[1:0]==0)begin
     if(associate)begin
      cx0<=merged0;cx1<=merged1;cy1<=y;if(rows!=255)rows<=rows+1'b1;
     end else if(row_good || (cand_on && row_gap>11'd32))begin
      if(cand_good && (!best_on || ch>bh))begin
       bx0<=cx0;bx1<=cx1;by0<=cy0;by1<=cy1;best_on<=1;
      end
      cand_on<=row_good;cx0<=rx0;cx1<=rx1;cy0<=y;cy1<=y;rows<=1;
     end
    end
    if(y==HEIGHT-1)begin
     found<=best_on || cand_good;
     if(cand_good && (!best_on || ch>bh))begin x0<=cx0;x1<=cx1;y0<=cy0;y1<=cy1+10'd3;end
     else begin x0<=bx0;x1<=bx1;y0<=by0;y1<=by1+10'd3;end
    end
   end else if(y[1:0]==0)begin
    if(white)white_age<=0;else if(white_age!=7)white_age<=white_age+1'b1;
    if(close_run)begin row_on<=1;row0<=rx0;row1<=rx1;end
    if(run_on)begin
     if(dark)begin run1<=x;run_two<=1;tail_gap<=0;end
     else if(white || tail_gap==3)begin run_on<=0;run_two<=0;tail_gap<=0;end
     else tail_gap<=tail_gap+1'b1;
    end else if(dark && white_age<4)begin run_on<=1;run_two<=0;run0<=x;run1<=x;tail_gap<=0;end
   end
  end
 end
endmodule
