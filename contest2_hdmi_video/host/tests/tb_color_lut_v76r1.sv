`timescale 1ns/1ps
module tb_color_lut_v76r1;
reg clk=0;always #5 clk=~clk;
wire [95:0] rgb;
ua_photo_finish_96 #(.INPUT_BITS(9),.IMG_WIDTH(16),.RUNTIME_STRENGTH(1),
 .HIGHLIGHT_SAFE_LIFT(1),.SHADOW_COLOR_DENOISE(1),.COLOR_RESTORE(0),.GENTLE_SHADOW_LIFT(1),.SELECTIVE_SHADOW_BOOST(1)) dut(
 .I_clk(clk),.I_rst_n(1'b0),.I_tvalid(1'b0),.I_tuser(1'b0),.I_tlast(1'b0),
 .I_tdata(108'b0),.I_strength(2'b0),.O_tdata(rgb));
integer i,s,base,room,lift,value,previous;reg [23:0] neutral;
reg [31:0] rng=32'h1076;reg [23:0] pixel,actual,old;integer hi,extra,j,channel_expected;reg [23:0] expected_pixel;
initial begin
 #1;
 // Exhaust every channel/midpoint pair and every nonnegative shadow delta.
 for(i=0;i<256;i=i+1)begin
  for(j=0;j<256;j=j+1)
   if(dut.finish_channel(i,j,1'b1,5'd0)!==dut.sat_channel(i,j))$fatal(1,"rounding carry mismatch");
  for(j=0;j<32;j=j+1)begin
   channel_expected=(i+j)&255;
   if(dut.finish_channel(i,0,1'b0,j)!==channel_expected[7:0])$fatal(1,"shadow carry mismatch");
  end
 end
 for(s=0;s<4;s=s+1)begin
  previous=-1;
  for(i=0;i<512;i=i+1)begin
   base=dut.tone(i,0);room=(base<96)?base:(base<192)?192-base:0;
   lift=(s==0)?0:(s==1)?room/16:room/8;
   value=dut.gen_tone_rom.bank_pair[0].lut[s*512+i];
   if(value!==base+lift)$fatal(1,"ROM %0d %0d",s,i);
   if(value<previous || value>255)$fatal(1,"Nonmonotone or overflow");
   neutral=dut.saturate_pixel({3{value[7:0]}});
   if(neutral!=={3{value[7:0]}})$fatal(1,"Neutral tint");
   if(i==0 && value!=0)$fatal(1,"Black pedestal");
   if(base>=192 && value!==base)$fatal(1,"Highlight lift");
   previous=value;
  end
 end
 for(s=0;s<4;s=s+1)begin
  previous=0;
  for(i=0;i<256;i=i+1)begin
   neutral=dut.finish_pixel({3{i[7:0]}},s);
   if(neutral[23:16]!=neutral[15:8] || neutral[15:8]!=neutral[7:0] || neutral[7:0]<previous)$fatal(1,"neutral monotonicity s=%0d i=%0d result=%h previous=%0d",s,i,neutral,previous);
   previous=neutral[7:0];
  end
  for(i=0;i<65536;i=i+1)begin
   rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};pixel=rng[23:0];
   hi=pixel[23:16];if(pixel[15:8]>hi)hi=pixel[15:8];if(pixel[7:0]>hi)hi=pixel[7:0];
   extra=(s==0 || hi>=128)?0:(hi<64)?hi/2:(127-hi)/2;if(s==1)extra=extra/2;
   old=dut.saturate_pixel(pixel);expected_pixel={8'(old[23:16]+extra),8'(old[15:8]+extra),8'(old[7:0]+extra)};
   actual=dut.finish_pixel(pixel,s);
   if(actual!==expected_pixel)$fatal(1,"pixel mismatch %h %h %h",pixel,actual,expected_pixel);
   if((s==0 || hi>=128) && actual!==old)$fatal(1,"off/mid/high altered");
   if(hi<128 && (($signed({1'b0,actual[23:16]})-$signed({1'b0,actual[15:8]}))!==
       ($signed({1'b0,pixel[23:16]})-$signed({1'b0,pixel[15:8]}))))$fatal(1,"chroma difference changed");
  end
 end
 $display("COLOR_V76R1_LUT_PASS all_2048_codes monotone neutral black highlight_no_lift");$finish;
end
endmodule
