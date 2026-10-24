`timescale 1ns/1ps
// Real AWB line RAM plus the exact ISP early-marker alignment and photo stage.
module tb_photo_alignment;
  parameter CHANNEL_BITS=8;
  reg clk=0,rst=1,valid=0,user=0,last=0;
  reg [95:0] data=0;
  always #8 clk=~clk;
  wire ready,av,au,al;wire [12*CHANNEL_BITS-1:0] ad;
  ua_awb_frame #(.IMG_WIDTH(1280),.IMG_HEIGHT(4),.OUTPUT_CHANNEL_BITS(CHANNEL_BITS)) awb(
    .I_clk(clk),.I_rst_n(rst),.I_tlast(last),.I_tuser(user),.I_tdata(data),.I_tvalid(valid),.I_tready(ready),.O_tlast(al),.O_tuser(au),.O_tdata(ad),.O_tvalid(av),.O_tready(1'b1));
  reg pending=0;
  always @(posedge clk or negedge rst)
    if(!rst) pending<=0;
    else begin
      if(au) pending<=1;
      if(av && (pending || au)) pending<=0;
    end
  wire pv,pu,pl;wire [95:0] pd;
  ua_photo_finish_96 #(.IMG_WIDTH(1280),.TONE_ENABLE(CHANNEL_BITS==9),.INPUT_BITS(CHANNEL_BITS)) photo(
    clk,rst,av,av && (pending || au),al,ad,2'd0,pv,pu,pl,pd);
  integer f,y,g,got=0;
  reg [7:0] c,e;
  reg [23:0] expected_wide[0:11];
  reg [23:0] expected_pixel;
  integer checked_awb=0;
  function [7:0] gray;
    input integer group_index,frame_index;
    begin
      case((group_index/8)%4)
        0:gray=24+frame_index;
        1:gray=60+frame_index;
        2:gray=160+frame_index;
        default:gray=240+frame_index;
      endcase
    end
  endfunction
  always @(posedge clk) begin
    #1;
    if(pv) begin
      e=gray(got%320,got/1280);
      expected_pixel=(CHANNEL_BITS==9)?expected_wide[(got/1280)*4+((got%320)/8)%4]:{3{e}};
      if(got>=3840 || pd!=={4{expected_pixel}}) $fatal(1,"RGB at word %0d got=%h expected=%h",got,pd,expected_pixel);
      if(pu!==((got%1280)==0) || pl!==((got%320)==319)) $fatal(1,"marker at word %0d",got);
      got=got+1;
    end
  end
  initial begin
    if(CHANNEL_BITS==9) begin
      $readmemh("tmp/photo_tests/alignment_wide.hex",expected_wide);
      force awb.gain_r=20'd131072;force awb.gain_b=20'd131072;
    end
    #1 rst=0;#32 rst=1;
    for(f=0;f<3;f=f+1) begin
      @(negedge clk);user=1;
      @(negedge clk);user=0;
      repeat(3) @(negedge clk);
      for(y=0;y<4;y=y+1) begin
        for(g=0;g<320;g=g+1) begin
          @(negedge clk);valid=1;last=(g==319);c=gray(g,f);data={12{c}};
        end
        @(negedge clk);valid=0;last=0;
        repeat(80) @(negedge clk);
      end
      repeat(200) @(negedge clk);
    end
    repeat(100) @(negedge clk);
    if(got!=3840) $fatal(1,"word count %0d",got);
    if(CHANNEL_BITS==9 && checked_awb!=3840) $fatal(1,"wide AWB word count");
    $display("PHOTO_ALIGNMENT_PASS pixels=15360 frames=3 width=1280 AWB_RAM early_marker line_end photo_RAM");
    $finish;
  end
  always @(posedge clk) begin
    #1;
    if(CHANNEL_BITS==9 && av) begin
      e=gray(checked_awb%320,checked_awb/1280);
      if(ad!=={4{{e,1'b0},{1'b0,e},{e,1'b0}}}) $fatal(1,"AWB lost 9-bit product");
      checked_awb=checked_awb+1;
    end
  end
  initial begin #5000000;$fatal(1,"timeout");end
endmodule
