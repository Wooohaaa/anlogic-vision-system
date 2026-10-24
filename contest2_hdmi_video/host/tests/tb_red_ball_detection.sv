`timescale 1ns/1ps
// Uses the actual three-color detector, not a forced detector-result fixture.
module tb_red_ball_detection;
 parameter [23:0] BALL_COLOR=24'he02020;
 parameter integer NOISE=0;
 reg clk=0,dst=0,rst_n=0,tvalid=0,tuser=0,tlast=0;
 reg [95:0] data=0;
 wire result,v;
 wire [10:0] x,y,xmin,xmax,ymin,ymax;
 wire [1:0] shape;
 wire tx;
 always #5 clk=~clk;
 always #10 dst=~dst;
 ua_track_detect detector(.I_clk(clk),.I_rst_n(rst_n),.I_tlast(tlast),
 .I_tuser(tuser),.I_tdata(data),.I_tvalid(tvalid),.I_tready(1'b1),
 .O_track_valid(result),.O_v0(v),.O_x0(x),.O_y0(y),.O_shape0(shape),
 .O_xmin0(xmin),.O_xmax0(xmax),.O_ymin0(ymin),.O_ymax0(ymax));
 ua_red_ball_uart #(.BIT_CYCLES(4),.FRAME_CYCLES(500)) bridge(
 .src_clk(clk),.dst_clk(dst),.rst_n(rst_n),.enable(1'b1),
 .frame_valid(result),.target_valid(v),.target_shape(shape),.target_x(x),.target_y(y),
 .xmin(xmin),.xmax(xmax),.ymin(ymin),.ymax(ymax),.tx(tx));
 integer results=0,circles=0,xx,yy,f,dx,dy,n;
 reg [23:0] sample;
 always @(negedge clk) if(result) begin
   results=results+1;
   if(v&&shape==0) circles=circles+1;
 end
 initial begin
   #100;rst_n=1;
   for(f=0;f<5;f=f+1) begin
     for(yy=0;yy<720;yy=yy+1) for(xx=0;xx<320;xx=xx+1) begin
       @(negedge clk);
       tvalid=1;tuser=(xx==0&&yy==0);tlast=(xx==319);
       dx=xx*4+2-640;dy=yy-360;
       n=NOISE?((xx+yy*3+f*5)%9)-4:0;
       sample=(dx*dx+dy*dy<60*60)?
          {8'(BALL_COLOR[23:16]+n),8'(BALL_COLOR[15:8]+n),8'(BALL_COLOR[7:0]+n)}:24'h202020;
       data={4{sample}};
     end
     @(negedge clk);tvalid=0;tuser=0;tlast=0;
     repeat(100)@(negedge clk);
   end
   if(results!=5||circles!=5||!bridge.latest[22])
     $fatal(1,"Actual detector fails results=%d circles=%d valid=%b shape=%d",results,circles,v,shape);
   if(x<635||x>645||y<355||y>365)$fatal(1,"Center inaccurate %d %d",x,y);
   $display("RED_BALL_DETECTION_PASS results=%0d center=%0d,%0d",results,x,y);
   // After blank frames, held detector result must eventually be revoked.
   for(f=0;f<3;f=f+1) begin
     for(yy=0;yy<720;yy=yy+1) for(xx=0;xx<320;xx=xx+1) begin
       @(negedge clk);tvalid=1;tuser=(xx==0&&yy==0);tlast=(xx==319);data={4{24'h202020}};
     end
     @(negedge clk);tvalid=0;tuser=0;tlast=0;repeat(100)@(negedge clk);
   end
   if(v||bridge.latest[22])$fatal(1,"No-target revocation fails");
   $display("RED_BALL_DETECTION_LOSS_PASS");$finish;
 end
endmodule
