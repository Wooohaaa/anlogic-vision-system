`timescale 1ns/1ps
module tb_photo_similarity_equivalence;
  parameter BITS=9;
  parameter DARK_DENOISE=1;
  localparam P=3*BITS;
  reg [P-1:0] c,n;
  integer a,b,bright,k,cases=0;
  reg expected;
  ua_photo_finish_96 #(.IMG_WIDTH(16),.INPUT_BITS(BITS),.DARK_DENOISE(DARK_DENOISE)) dut(
    .I_clk(1'b0),.I_rst_n(1'b0),.I_tvalid(1'b0),.I_tuser(1'b0),.I_tlast(1'b0),
    .I_tdata({12*BITS{1'b0}}),.I_strength(2'b0));
  function reference_match;
    input [P-1:0] x,y;
    integer j,threshold,d,xc,yc;
    begin
      threshold=DARK_DENOISE ? 24 : 18;
      for(j=0;j<3;j=j+1) if(x[j*BITS+:BITS]>=64) threshold=12;
      reference_match=1;
      for(j=0;j<3;j=j+1) begin
        xc=x[j*BITS+:BITS];yc=y[j*BITS+:BITS];
        d=(xc>=yc)?xc-yc:yc-xc;
        if(d>threshold) reference_match=0;
      end
    end
  endfunction
  function candidate_match;
    input [P-1:0] x,y;
    reg dark,channel_ok;
    reg [BITS:0] delta;
    integer j;
    begin
      dark=1;
      for(j=0;j<3;j=j+1) if(x[j*BITS+:BITS]>=64) dark=0;
      candidate_match=1;
      for(j=0;j<3;j=j+1) begin
        delta={1'b0,x[j*BITS+:BITS]}-{1'b0,y[j*BITS+:BITS]};
        if(delta[BITS]) channel_ok=(&delta[BITS:5]) && (dark ? delta[4:0]>=(DARK_DENOISE ? 5'd8 : 5'd14) : delta[4:0]>=5'd20);
        else channel_ok=(~|delta[BITS:5]) && (dark ? delta[4:0]<=(DARK_DENOISE ? 5'd24 : 5'd18) : delta[4:0]<=5'd12);
        if(!channel_ok) candidate_match=0;
      end
    end
  endfunction
  task check;
    begin
      expected=reference_match(c,n);
      if(candidate_match(c,n)!==expected || dut.similar(c,n)!==expected)
        $fatal(1,"similarity mismatch bits=%0d c=%h n=%h",BITS,c,n);
      cases=cases+1;
    end
  endtask
  initial begin
    for(bright=0;bright<2;bright=bright+1)
      for(a=0;a<(1<<BITS);a=a+1)
        for(b=0;b<(1<<BITS);b=b+1) begin
          c=0;n=0;
          if(bright) begin c[2*BITS+:BITS]=64;n[2*BITS+:BITS]=64;end
          c[0+:BITS]=a;n[0+:BITS]=b;
          check;
        end
    for(a=0;a<20000;a=a+1) begin
      for(k=0;k<3;k=k+1) begin c[k*BITS+:BITS]=$random;n[k*BITS+:BITS]=$random;end
      check;
    end
    $display("PHOTO_SIMILARITY_EQUIVALENCE_PASS bits=%0d dark_recovery=%0d cases=%0d signed_range overflow",BITS,DARK_DENOISE,cases);
    $finish;
  end
endmodule
