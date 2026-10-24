`timescale 1ns/1ps
// Production AWB + finite 5x5 finishing + display algorithm + real 96/128
// packing. Compare complete rasters to an already-repaired reference source.
module tb_v85_awb_photo_pack #(parameter W=1280,H=720,FRAMES=2,RECOVERY=0);
 localparam G=W/4,N=G*H*FRAMES,WORDS=N*3/4,CB=9;
 reg clk=0,rst=0,v=0,u=0,l=0;reg[95:0]src=0,reference_rgb=0;
 always #5 clk=~clk;
 wire[95:0]repaired;wire rv,ru,rl;
 ua_top_row_repair_v85 #(.IMG_WIDTH(W),.IMG_HEIGHT(H))repair(clk,rst,src,v,u,l,repaired,rv,ru,rl);
 wire[1:0]av,au,al,pv,pu,pl,uv,uu,ul,packed_v,packed_u;
 wire[12*CB-1:0]a[0:1];wire[95:0]p[0:1],d[0:1];wire[127:0]word_data[0:1];
 genvar g;
 generate for(g=0;g<2;g=g+1)begin:path
  ua_awb_frame #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.OUTPUT_CHANNEL_BITS(CB),.GREEN_CAST_RECOVERY(RECOVERY))awb(
   .I_clk(clk),.I_rst_n(rst),.I_tdata(g==0?reference_rgb:repaired),.I_tvalid(g==0?v:rv),
   .I_tuser(g==0?u:ru),.I_tlast(g==0?l:rl),.I_enable(1'b0),.O_tready(1'b1),
   .O_tvalid(av[g]),.O_tuser(au[g]),.O_tlast(al[g]),.O_tdata(a[g]));
  reg pending=0;
  always @(posedge clk)if(!rst)pending<=0;else begin
   if(au[g])pending<=1;if(av[g] && (pending || au[g]))pending<=0;
  end
  ua_photo_finish_96 #(.IMG_WIDTH(W),.INPUT_BITS(CB),.TONE_ENABLE(1),.WINDOW5(1),.SHADOW_COLOR_DENOISE(1),
   .GENTLE_SHADOW_LIFT(1),.SELECTIVE_SHADOW_BOOST(1))photo(
   clk,rst,av[g],av[g]&&(pending||au[g]),al[g],a[g],2'd0,pv[g],pu[g],pl[g],p[g]);
  ua_user_algo_96 #(.IMG_WIDTH(W),.IMG_HEIGHT(H))algo(
   clk,rst,pl[g],pu[g],p[g],pv[g],3'd0,1'b1,ul[g],uu[g],d[g],uv[g],);
  data_96bit_to_128bit packer(clk,rst,au[g],uv[g],d[g],packed_u[g],packed_v[g],word_data[g]);
 end endgenerate
 reg[95:0]expected_pixels[0:N-1];reg[127:0]expected_words[0:WORDS-1];
 integer pc0=0,pc1=0,wc0=0,wc1=0,lines0=0,lines1=0,width1=0,sof0=0,sof1=0,margin=0;
 always @(negedge clk)if(rst)begin
  if(uv[0])begin expected_pixels[pc0]=d[0];pc0=pc0+1;if(ul[0])lines0=lines0+1;end
  if(uv[1])begin
   if(pc1>=pc0 || d[1]!==expected_pixels[pc1])$fatal(1,"pixel order/data mismatch group=%d",pc1);
   if(uu[1]!==((pc1%(G*H))==0))$fatal(1,"SOF mismatch %d",pc1);
   width1=width1+1;
   if(ul[1])begin if(width1!=G)$fatal(1,"bad downstream width %d",width1);width1=0;lines1=lines1+1;end
   pc1=pc1+1;
  end
  if(packed_v[0])begin expected_words[wc0]=word_data[0];wc0=wc0+1;end
  if(packed_u[0])sof0=sof0+1;
  if(packed_u[1])begin sof1=sof1+1;margin=9;end
  else if(margin>0)margin=margin-1;
  if(packed_v[1])begin
   if(margin!=0)$fatal(1,"DDR FIFO reset margin lost");
   if(wc1>=wc0 || word_data[1]!==expected_words[wc1])$fatal(1,"packed word mismatch %d",wc1);
   wc1=wc1+1;
  end
 end
 function[95:0]pattern(input integer f,y,x);
  integer val;begin val=40+((f*7+y/8+x/8)%100);pattern={12{8'(val)}};end
 endfunction
 task idle(input integer n);integer k;begin for(k=0;k<n;k=k+1)begin @(posedge clk);#1;v=0;u=0;l=0;end end endtask
 integer f,y,x;
 initial begin
  repeat(4)@(posedge clk);#1;rst=1;
  for(f=0;f<FRAMES;f=f+1)begin
   for(y=0;y<H;y=y+1)begin
    for(x=0;x<G;x=x+1)begin
     @(posedge clk);#1;v=1;u=(x==0&&y==0);l=x==G-1;
     src=y==0?{4{24'hff0000}}:pattern(f,y,x);reference_rgb=pattern(f,y==0?1:y,x);
    end
    idle(100);
   end
   idle(2*G+650);
  end
  idle(600);
  if(pc0!=N || pc1!=N || wc0!=WORDS || wc1!=WORDS || lines0!=H*FRAMES || lines1!=H*FRAMES || sof0!=FRAMES || sof1!=FRAMES)
   $fatal(1,"coverage pixels=%d/%d words=%d/%d lines=%d/%d sof=%d/%d",pc0,pc1,wc0,wc1,lines0,lines1,sof0,sof1);
  $display("V85_PRODUCTION_AWB_PHOTO_PACK_PASS W=%d H=%d frames=%d groups=%d words=%d",W,H,FRAMES,pc1,wc1);$finish;
 end
 initial begin #100000000;$fatal(1,"timeout");end
endmodule
