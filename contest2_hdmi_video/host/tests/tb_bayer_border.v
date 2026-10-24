`timescale 1ns/1ps
module tb_bayer_border;
  parameter W=32,H=6,BUBBLES=1,COALESCE=0;
  reg clk=0,rst=0,valid=0,user=0,last=0,checking=0;
  reg [39:0] raw=0;
  wire [127:0] rgb;
  wire ov,ou,ol;
  always #5 clk=~clk;
  ua_demosaic_border #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.COALESCE_INPUT(COALESCE)) dut(
    .I_clk(clk),.I_rst_n(rst),.axi4s_video_tdata(raw),
    .axi4s_video_tdest(10'd0),.axi4s_video_tvalid(valid),
    .axi4s_video_tuser(user),.axi4s_video_tlast(last),
    .axi4s_video_tready(),.O_tdata(rgb),.O_tvalid(ov),
    .O_tuser(ou),.O_tlast(ol),.O_tready(1'b1));
  integer x,y,f,k,seen=0,ox,oy,ofr,r,g,b,px;
  integer core_seen=0,ci,cx,cy,cf;
  function integer sample;
    input integer sx,sy,sf;
    integer base;
    begin
      if(sx<0) sx=1; if(sx>=W) sx=W-2;
      if(sy<0) sy=1; if(sy>=H) sy=H-2;
      // BGGR, differing channels expose incorrect CFA parity at borders.
      base=(!sy[0]&&!sx[0])?180:(sy[0]&&sx[0])?40:100;
      sample=base+((sx*3+sy*5+sf*11)%24);
    end
  endfunction
  task expected;
    input integer sx,sy,sf;
    output integer rr,gg,bb;
    integer diag,sum_cross,hor,vert;
    begin
      diag=(sample(sx-1,sy-1,sf)+sample(sx+1,sy-1,sf)+
            sample(sx-1,sy+1,sf)+sample(sx+1,sy+1,sf))/4;
      sum_cross=(sample(sx-1,sy,sf)+sample(sx+1,sy,sf)+
             sample(sx,sy-1,sf)+sample(sx,sy+1,sf))/4;
      hor=(sample(sx-1,sy,sf)+sample(sx+1,sy,sf))/2;
      vert=(sample(sx,sy-1,sf)+sample(sx,sy+1,sf))/2;
      if(!sy[0]&&!sx[0]) begin rr=diag;gg=sum_cross;bb=sample(sx,sy,sf);end
      else if(sy[0]&&sx[0]) begin rr=sample(sx,sy,sf);gg=sum_cross;bb=diag;end
      else if(!sy[0]) begin rr=vert;gg=sample(sx,sy,sf);bb=hor;end
      else begin rr=hor;gg=sample(sx,sy,sf);bb=vert;end
    end
  endtask
  always @(negedge clk) if(rst && checking && COALESCE) begin
    if(core_seen%W!=0 && !dut.core_valid) $fatal(1,"coalescer split a row burst");
    if(dut.core_valid) begin
    cf=core_seen/(W*H);cy=(core_seen%(W*H))/W;cx=core_seen%W;
    for(ci=0;ci<4;ci=ci+1)
      if(dut.core_raw[ci*10+:10]!==10'(sample(cx+ci,cy,cf)*4))
        $fatal(1,"coalescer raw mismatch f=%0d y=%0d x=%0d actual=%h",cf,cy,cx+ci,dut.core_raw);
    core_seen=core_seen+4;
    end
  end
  always @(negedge clk) if(rst && checking) begin
    if(COALESCE && seen%W!=0 && !ov) $fatal(1,"RGB split a row burst: 96->128 packing unsafe");
    if(!ov && (ou || ol)) $fatal(1,"sideband leaked into an invalid bubble");
    if(ov) begin
    ofr=seen/(W*H);oy=(seen%(W*H))/W;ox=seen%W;
    if(ou !== (ox==0 && oy==0)) $fatal(1,"SOF mismatch pixel=%0d",seen);
    if(ol !== (ox==W-4)) $fatal(1,"EOL mismatch pixel=%0d",seen);
    for(px=0;px<4;px=px+1) begin
      expected(ox+px,oy,ofr,r,g,b);
      if(rgb[px*32+:32] !== {8'd0,8'(r),8'(g),8'(b)})
        $fatal(1,"RGB f=%0d y=%0d x=%0d expected=%0d,%0d,%0d actual=%h",
               ofr,oy,ox+px,r,g,b,rgb[px*32+:32]);
    end
    seen=seen+4;
    end
  end
  initial begin
    repeat(4) @(negedge clk);rst=1;
    // Leave stale RAM and a partly occupied window, then reset mid-frame.
    for(y=0;y<2;y=y+1) begin
      for(x=0;x<W;x=x+4) begin
        @(posedge clk);#1;valid=1;user=(x==0&&y==0);last=x==W-4;
        raw=40'h123456789a;
      end
      @(posedge clk);#1;valid=0;user=0;last=0;
    end
    @(posedge clk);#1;rst=0;
    repeat(4) @(posedge clk);#1;rst=1;checking=1;
    for(f=0;f<3;f=f+1) begin
      for(y=0;y<H;y=y+1) begin
        for(x=0;x<W;x=x+4) begin
          @(posedge clk);#1;valid=1;user=(x==0&&y==0);last=x==W-4;
          for(k=0;k<4;k=k+1) raw[k*10+:10]=10'(sample(x+k,y,f)*4);
          if(BUBBLES==2 || (BUBBLES==1 && (x/4)%7==2)) begin
            @(posedge clk);#1;valid=0;user=0;last=0;
            repeat(2) @(posedge clk);
          end
        end
        @(posedge clk);#1;valid=0;user=0;last=0;
        repeat(COALESCE?100:5) @(posedge clk);
      end
      // Complete front-end row readout AND the Bayer bottom-row flush.
      repeat((COALESCE?W/2:W/4)+200) @(posedge clk);
      if(seen!=(f+1)*W*H) $fatal(1,"pixel count %0d expected %0d",seen,(f+1)*W*H);
    end
    $display("BAYER_BORDER_PASS W=%0d H=%0d bubbles=%0d pixels=%0d all_RGB_and_flags",W,H,BUBBLES,seen);
    $finish;
  end
endmodule
