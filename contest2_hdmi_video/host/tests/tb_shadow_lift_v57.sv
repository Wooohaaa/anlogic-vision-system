`timescale 1ns/1ps
module tb_shadow_lift_v57;
 reg clk=0,rst=0,v=0,u=0,l=0;always #5 clk=~clk;
 reg [107:0] data=0;reg [1:0] strength=0;wire ov;wire [95:0] rgb;
 ua_photo_finish_96 #(.IMG_WIDTH(16),.INPUT_BITS(9),.RUNTIME_STRENGTH(1),.HIGHLIGHT_SAFE_LIFT(1)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_tvalid(v),.I_tuser(u),.I_tlast(l),.I_tdata(data),.I_strength(strength),.O_tvalid(ov),.O_tdata(rgb));
 integer i,j,base,room,expected,outputs=0;
 always @(posedge clk)begin #1;if(ov)begin
  outputs=outputs+1;if(rgb!=={12{8'd225}})$fatal(1,"highlight lifted %h",rgb);
 end end
 initial begin
  // Check generated LUT directly and use a uniform bright frame through FIR.
  #1;
  for(j=0;j<3;j=j+1)for(i=0;i<512;i=i+1)begin
   base=dut.tone(i,0);room=(base<96)?base:(base<192)?192-base:0;
   expected=base+((j==0)?0:(j==1)?room/4:room/2);
   if(dut.gen_tone_rom.bank_pair[0].lut[j*512+i]!==expected)$fatal(1,"shadow table");
   if(base>=192 && expected!=base)$fatal(1,"bright values changed");
   if(i && dut.gen_tone_rom.bank_pair[0].lut[j*512+i]<dut.gen_tone_rom.bank_pair[0].lut[j*512+i-1])$fatal(1,"curve inversion");
  end
  i=0;while(dut.tone(i,0)!=225 && i<511)i=i+1;
  if(i==511)$fatal(1,"fixture code not found");data={12{i[8:0]}};
  repeat(4)@(negedge clk);rst=1;
  for(j=0;j<3;j=j+1)begin
   strength=j;
   for(i=0;i<16;i=i+1)begin @(negedge clk);v=1;u=(i==0);l=(i%4==3);end
   @(negedge clk);v=0;u=0;l=0;repeat(20)@(negedge clk);
  end
  if(outputs!=48)$fatal(1,"output count");
  $display("SHADOW_LIFT_V57_PASS 1536_entries monotone bright_ge192_unchanged three_live_frames");$finish;
 end
endmodule
