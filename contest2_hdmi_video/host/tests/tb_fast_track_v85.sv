`timescale 1ns/1ps
module tb_fast_track_v85;
 localparam W=320,H=180;
 reg clk=0,rst=0,v=0,u=0,l=0;reg[95:0]rgb=0;
 always #5 clk=~clk;
 ua_track_detect #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.FAST_TRACK_ENABLE(1)) fast(
 .I_clk(clk),.I_rst_n(rst),.I_tlast(l),.I_tuser(u),.I_tdata(rgb),.I_tvalid(v),.I_tready(1'b1));
 ua_track_detect #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.FAST_TRACK_ENABLE(0)) old(
 .I_clk(clk),.I_rst_n(rst),.I_tlast(l),.I_tuser(u),.I_tdata(rgb),.I_tvalid(v),.I_tready(1'b1));
 integer frame,x,y,x0,dy,received=0,fast_error=0,old_error=0,e,rawx;
 reg[23:0]pixel;
 always @(posedge clk)begin #1;if(rst)begin
  if({fast.O_tvalid,fast.O_tuser,fast.O_tlast,fast.O_tdata,fast.O_track_valid,fast.O_obj_cnt}!==
     {old.O_tvalid,old.O_tuser,old.O_tlast,old.O_tdata,old.O_track_valid,old.O_obj_cnt})$fatal(1,"stream/cadence altered");
  if(fast.O_track_valid)begin
   received=received+1;rawx=(x0+4)*4;
   if({fast.O_v0,fast.O_v1,fast.O_v2,fast.O_shape0,fast.O_shape1,fast.O_shape2}!==
      {old.O_v0,old.O_v1,old.O_v2,old.O_shape0,old.O_shape1,old.O_shape2})$fatal(1,"valid/shape altered");
   if(frame<4 && {fast.O_x0,fast.O_xmin0,fast.O_xmax0}!=={old.O_x0,old.O_xmin0,old.O_xmax0})$fatal(1,"stationary smoothing changed");
   if(frame>=4 && frame<16)begin
    if(!fast.O_v0 || !fast.O_v1 || !fast.O_v2)$fatal(1,"lost moving target");
    if(fast.O_x0!=rawx || fast.O_x1!=rawx || fast.O_x2!=rawx ||
       fast.O_xmin0!=x0*4 || fast.O_xmax0!=(x0+8)*4-1 || fast.O_ymin0!=20+dy || fast.O_ymax0!=39+dy)
     $fatal(1,"moving box incoherent frame=%d got x=%d want=%d",frame,fast.O_x0,rawx);
    e=fast.O_x0-rawx;if(e<0)e=-e;fast_error=fast_error+e;
    e=old.O_x0-rawx;if(e<0)e=-e;old_error=old_error+e;
   end
  end
 end end
 initial begin
  repeat(5)@(negedge clk);rst=1;
  for(frame=0;frame<20;frame=frame+1)begin
   if(frame<4)x0=10+(frame==1?1:0);
   else if(frame<10)x0=8+(frame-4)*10;
   else if(frame<16)x0=58-(frame-10)*10;
   else x0=40;
   dy=frame>=10 && frame<16?((frame-10)%2)*8:0;
   for(y=0;y<H;y=y+1)for(x=0;x<W/4;x=x+1)begin
    pixel=24'h808080;
    if(frame!=16 && frame!=17 && x>=x0 && x<x0+8)begin
     if(y>=20+dy && y<40+dy)pixel=24'hd02020;
     if(y>=75+dy && y<95+dy)pixel=24'h20d020;
     if(y>=130+dy && y<150+dy)pixel=24'h2020d0;
    end
    @(negedge clk);v=1;u=x==0 && y==0;l=x==W/4-1;rgb={4{pixel}};
   end
   @(negedge clk);v=0;u=0;l=0;repeat(32)@(negedge clk);
  end
  if(received!=20 || fast_error!=0 || old_error<=0)$fatal(1,"coverage/lag %d %d %d",received,fast_error,old_error);
  $display("FAST_TRACK_V85_RGB_PASS frames=%d moving_error_new=%d old=%d",received,fast_error,old_error);$finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
