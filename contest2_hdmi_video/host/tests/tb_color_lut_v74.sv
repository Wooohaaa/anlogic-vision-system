`timescale 1ns/1ps
module tb_color_lut_v74;
reg clk=0;always #5 clk=~clk;
wire [95:0] rgb;
ua_photo_finish_96 #(.INPUT_BITS(9),.IMG_WIDTH(16),.RUNTIME_STRENGTH(1),
 .HIGHLIGHT_SAFE_LIFT(1),.SHADOW_COLOR_DENOISE(1),.COLOR_RESTORE(1)) dut(
 .I_clk(clk),.I_rst_n(1'b0),.I_tvalid(1'b0),.I_tuser(1'b0),.I_tlast(1'b0),
 .I_tdata(108'b0),.I_strength(2'b0),.O_tdata(rgb));
integer i,s,base,room,lift,value,previous;reg [23:0] neutral;
initial begin
 #1;
 for(s=0;s<4;s=s+1)begin
  previous=-1;
  for(i=0;i<512;i=i+1)begin
   base=dut.tone(i,0);room=(base<96)?base:(base<192)?192-base:0;
   lift=(s==0)?0:(s==1)?room/4:room/2;
   value=dut.gen_tone_rom.bank_pair[0].lut[s*512+i];
   if(value!==dut.restore_color_code(base+lift))$fatal(1,"ROM %0d %0d",s,i);
   if(value<previous || value>255)$fatal(1,"Nonmonotone or overflow");
   neutral=dut.saturate_pixel({3{value[7:0]}});
   if(neutral!=={3{value[7:0]}})$fatal(1,"Neutral tint");
   if(i==0 && value!=0)$fatal(1,"Black pedestal");
   if(base>=192 && value!==dut.restore_color_code(base))$fatal(1,"Highlight lift");
   previous=value;
  end
 end
 $display("COLOR_V74_LUT_PASS all_2048_codes monotone neutral black highlight_no_lift");$finish;
end
endmodule
