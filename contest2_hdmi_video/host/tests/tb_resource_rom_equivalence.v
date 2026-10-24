`timescale 1ns/1ps
module tb_resource_rom_equivalence;
 reg clk=0; always #5 clk=~clk;
 reg [7:0] ch=8'hff; reg [3:0] row=4'hf; reg [14:0] addr=15'h7fff;
 wire [15:0] font,ref_font; wire [24:0] logo,ref_logo;
 osd_char_lib #(.SYNC_READ(1)) f(.I_clk(clk),.I_char(ch),.I_row(row),.O_row_bits(font));
 osd_char_v17_reference r(.I_char(ch),.I_row(row),.O_row_bits(ref_font));
 anlogic_logo_rom l(.I_clk(clk),.I_addr(addr),.O_pixel(logo));
 logo_v17_reference lr(.I_addr(addr),.O_pixel(ref_logo));
 integer c,y,a; reg [15:0] expected_font; reg [24:0] expected_logo;
 initial begin
  for(c=0;c<256;c=c+1) for(y=0;y<16;y=y+1) begin
   @(negedge clk);ch=c;row=y;#1;expected_font=ref_font;
   @(posedge clk);#1;
   if(font!==expected_font) $fatal(1,"font mismatch char=%h row=%d got=%h expected=%h",ch,row,font,expected_font);
  end
  for(a=0;a<32768;a=a+1) begin
   @(negedge clk);addr=a;#1;expected_logo=ref_logo;
   @(posedge clk);#1;
   @(posedge clk);#1;
   if(logo!==expected_logo) $fatal(1,"logo mismatch addr=%d got=%h expected=%h",addr,logo,expected_logo);
  end
  $display("RESOURCE_ROM_EQUIVALENCE_PASS glyph_rows=4096 logo_addresses=32768");$finish;
 end
endmodule
