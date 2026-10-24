`timescale 1ns/1ps
// Export exact maintained RTL assets for a labelled illustration, not HDMI capture.
module tb_osd_visual_assets;
 reg clk=0;always #5 clk=~clk;
 reg [7:0] code=0;reg [3:0] row=0;
 reg [14:0] addr=0;
 wire [15:0] bits;wire [24:0] pixel;wire present;
 osd_char_lib #(.SYNC_READ(1)) font(clk,code,row,bits);
 anlogic_logo_rom logo(clk,addr,pixel,present);
 integer f,g,c,r,a;
 initial begin
  f=$fopen("tmp/v25_resource/osd_font.hex","w");
  g=$fopen("tmp/v25_resource/osd_logo.hex","w");
  for(c=0;c<256;c=c+1)for(r=0;r<16;r=r+1)begin
   @(negedge clk);code=c;row=r;
   @(posedge clk);#1;$fdisplay(f,"%04h",bits);
  end
  for(a=0;a<25600;a=a+1)begin
   @(negedge clk);addr=a;
   repeat(2) @(posedge clk);
   #1;$fdisplay(g,"%07h",pixel);
  end
  $fclose(f);$fclose(g);
  $display("OSD_VISUAL_ASSETS_EXPORTED_NOT_HDMI_CAPTURE");$finish;
 end
endmodule
