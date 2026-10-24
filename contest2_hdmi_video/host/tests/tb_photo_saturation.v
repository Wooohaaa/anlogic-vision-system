`timescale 1ns/1ps
module tb_photo_saturation;
  wire v,u,l; wire [95:0] d;
  ua_photo_finish_96 #(.IMG_WIDTH(16)) dut(1'b0,1'b0,1'b0,1'b0,1'b0,96'd0,2'd0,v,u,l,d);
  integer r,g,b,lo,hi,mid,rr,gg,bb,checked=0;
  reg [23:0] p,expected;
  initial begin
    for(r=0;r<256;r=r+7) for(g=0;g<256;g=g+7) for(b=0;b<256;b=b+7) begin
      lo=r;hi=r;
      if(g<lo)lo=g;if(b<lo)lo=b;
      if(g>hi)hi=g;if(b>hi)hi=b;
      mid=(lo+hi)/2;
      rr=r;gg=g;bb=b;
      if(lo>24 && hi<224 && hi>80 && hi-lo>16) begin
        // Signed integer division truncates towards zero, independent oracle.
        rr=r+(r-mid)/4;gg=g+(g-mid)/4;bb=b+(b-mid)/4;
        if(rr<0)rr=0;if(rr>255)rr=255;
        if(gg<0)gg=0;if(gg>255)gg=255;
        if(bb<0)bb=0;if(bb>255)bb=255;
      end
      p={r[7:0],g[7:0],b[7:0]};
      expected={rr[7:0],gg[7:0],bb[7:0]};
      if(dut.saturate_pixel(p)!==expected) $fatal(1,"saturation mismatch %h",p);
      checked=checked+1;
    end
    for(r=0;r<256;r=r+1)
      if(dut.saturate_pixel({3{r[7:0]}})!=={3{r[7:0]}})
        $fatal(1,"neutral changed %0d",r);
    // Exhaust all channel/midpoint pairs reachable under the RGB guard.
    // max-min<=198 => |channel-floor((max+min)/2)|<=99.
    for(r=25;r<=223;r=r+1) for(g=25;g<=223;g=g+1)
      if((r-g<=99) && (g-r<=99)) begin
        rr=r+(r-g)/4;
        if(rr<0 || rr>255 || dut.sat_channel(r,g)!==rr[7:0])
          $fatal(1,"unreachable clamp proof failed channel=%0d midpoint=%0d",r,g);
      end
    $display("PHOTO_SATURATION_PASS rgb_samples=%0d neutral=256 gamut_guards signed_rounding",checked);
    $finish;
  end
endmodule
