`timescale 1ns/1ps
module tb_shared_colour_chart;
  reg clk=0,rst=0,en=0,vs=0,de=0;
  reg [23:0] hdmi=24'h123456,clean=24'h654321;
  wire [23:0] a,b;
  always #5 clk=~clk;
  ua_shared_colour_diagnostic_embedded dut(clk,rst,en,vs,de,hdmi,clean,a,b);
  integer x,y,count=0,frames=0,expected_x=0,expected_y=0;
  reg vs_old=0,de_old=0,expected_enabled=0;
  reg [23:0] expected;
  function [23:0] reference;
    input integer xx,yy;
    integer value;
    begin
      if(yy<240) case(xx/160)
        0:reference=24'hff0000;1:reference=24'h00ff00;2:reference=24'h0000ff;
        3:reference=24'hffff00;4:reference=24'h00ffff;5:reference=24'hff00ff;
        6:reference=24'hffffff;default:reference=24'h000000;
      endcase
      else begin
        value=(xx>=1024)?255:((yy<480)?xx/4:xx/64);
        reference={8'(value),8'(value),8'(value)};
      end
    end
  endfunction
  always @(posedge clk) begin
    if(!rst) begin expected_enabled=0;expected_x=0;expected_y=0;vs_old=0;de_old=0;end
    else begin
      // Consumers sample prior to NBA, just like hdmi_tx and the network FIFO.
      if(expected_enabled && de) begin
        expected=reference(expected_x,expected_y);
        if(a!==expected || b!==expected)
          $fatal(1,"pattern mismatch xy=%0d/%0d expected=%h HDMI=%h ETH=%h",expected_x,expected_y,expected,a,b);
        count=count+1;
      end else if(!expected_enabled && (a!==hdmi || b!==clean))
        $fatal(1,"camera passthrough changed");
      if(vs && !vs_old) begin expected_enabled=en;expected_x=0;expected_y=0;end
      else if(de) expected_x=expected_x+1;
      else begin expected_x=0;if(de_old) expected_y=expected_y+1;end
      vs_old=vs;de_old=de;
    end
  end
  initial begin
    repeat(3) @(negedge clk);rst=1;en=1;vs=1;
    repeat(5) @(negedge clk);vs=0;
    for(y=0;y<720;y=y+1) begin
      for(x=0;x<1280;x=x+1) begin
        @(negedge clk);de=1;
        if(y==300 && x==100) en=0; // must not change this frame
      end
      @(negedge clk);de=0;
      repeat(12) @(negedge clk);
    end
    @(negedge clk);vs=1;
    repeat(5) @(negedge clk);vs=0;
    repeat(20) begin @(negedge clk);de=1;hdmi=hdmi+1;clean=clean+2;end
    @(negedge clk);de=0;
    repeat(4) @(negedge clk);
    if(count!=921600) $fatal(1,"coverage count %0d",count);
    $display("SHARED_COLOUR_CHART_PASS 921600_pixels exact_RGB gray256 dark16 frame_latched passthrough");
    $finish;
  end
endmodule
