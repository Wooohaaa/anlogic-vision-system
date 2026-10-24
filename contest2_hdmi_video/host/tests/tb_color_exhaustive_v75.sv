`timescale 1ns/1ps
module tb_color_exhaustive_v75;
reg clk=0;always #5 clk=~clk;
wire [95:0] rgb;
reg [7:0] expected[0:2047];integer i;
ua_photo_finish_96 #(.INPUT_BITS(9),.IMG_WIDTH(16),.RUNTIME_STRENGTH(1),
 .HIGHLIGHT_SAFE_LIFT(1),.SHADOW_COLOR_DENOISE(1),.COLOR_RESTORE(0),.GENTLE_SHADOW_LIFT(1)) dut(
 .I_clk(clk),.I_rst_n(1'b0),.I_tvalid(1'b0),.I_tuser(1'b0),.I_tlast(1'b0),
 .I_tdata(108'b0),.I_strength(2'b0),.O_tdata(rgb));
initial begin
 $readmemh("tmp/v75_exhaustive/lut.hex",expected);#1;
 for(i=0;i<2048;i=i+1)begin
  if(dut.gen_tone_rom.bank_pair[0].lut[i]!==expected[i] ||
     dut.gen_tone_rom.bank_pair[1].lut[i]!==expected[i] ||
     dut.gen_tone_rom.bank_pair[2].lut[i]!==expected[i] ||
     dut.gen_tone_rom.bank_pair[3].lut[i]!==expected[i] ||
     dut.gen_tone_rom.bank_pair[4].lut[i]!==expected[i] ||
     dut.gen_tone_rom.bank_pair[5].lut[i]!==expected[i])$fatal(1,"Independent LUT mismatch %0d",i);
 end
 $display("COLOR_V75_EXHAUSTIVE_PASS independent_python_all_12288_ROM_bytes");$finish;
end
endmodule
