`timescale 1ns/1ps
module tb_hand_blob_rgb;
reg clk=0;always #5 clk=~clk;
reg rst=0,clear=0,start=0,mode=0,mv=0,rv=0;reg[17:0]md;reg[9:0]rd;
wire mr,rr,busy,done,overflow,blob;wire[11:0]ma;wire[13:0]ra,area,seeds;
wire[7:0]xmin,xmax,ax;wire[6:0]ymin,ymax,ay;wire[23:0]sum;
ua_hand_blob_scan #(.RGB_STATS(1)) dut(clk,rst,clear,start,mode,mr,ma,mv,md,busy,done,overflow,blob,
 area,seeds,xmin,xmax,ymin,ymax,ax,ay,rr,ra,rv,rd,sum);
reg[17:0]mask[0:2429];reg[9:0]red[0:14399];reg[2047:0]mp,rp;
reg[15:0]rng=16'ha371;
integer pending_m=0,pending_r=0,addr_m=0,addr_r=0,delay_m=0,delay_r=0;
integer ticks=0,reads=0,pass,do_clear=0,word_index,pixel_slot,checking=0;
always @(posedge clk)begin
 rng<={rng[14:0],rng[15]^rng[13]^rng[12]^rng[10]};ticks=ticks+1;mv<=0;rv<=0;
 if(ticks>2000000)$fatal(1,"timeout");
 if(clear)begin pending_m=0;pending_r=0;end
 else begin
  if(mr)begin
   if(pending_m || ma>=2430)$fatal(1,"mask overlap/bounds");
   pending_m=1;addr_m=ma;delay_m=1+rng[1:0];
  end
  if(rr)begin
   if(pending_r || ra>=14400)$fatal(1,"red overlap/bounds");
   word_index=(ra/160)*27+(ra%160)/6;pixel_slot=(ra%160)%6;
   if(!mask[word_index][pixel_slot*3+(mode ? 2 : 0)])$fatal(1,"red read for background");
   pending_r=1;addr_r=ra;delay_r=1+rng[2:0];reads=reads+1;
  end
  if(pending_m)begin
   if(!delay_m)begin pending_m=0;mv<=1;md<=mask[addr_m];end else delay_m=delay_m-1;
  end
  if(pending_r)begin
   if(!delay_r)begin pending_r=0;rv<=1;rd<=red[addr_r];end else delay_r=delay_r-1;
  end
 end
end
always @(negedge clk)if(checking && blob)
 $display("BLOB %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",mode,area,seeds,xmin,xmax,ymin,ymax,ax,ay,sum);
task launch;
begin start=1;@(negedge clk);start=0;end endtask
initial begin
 if(!$value$plusargs("MASK=%s",mp)||!$value$plusargs("RED=%s",rp))$fatal(1,"files");
 if($value$plusargs("CLEAR=%d",do_clear))begin end
 $readmemh(mp,mask);$readmemh(rp,red);repeat(5)@(negedge clk);rst=1;
 if(do_clear)begin
  launch();while(!pending_r)@(negedge clk);clear=1;@(negedge clk);clear=0;
  if(busy || mr || rr || blob || done)$fatal(1,"clear incomplete");
 end
 for(pass=0;pass<2;pass=pass+1)begin
  mode=pass;reads=0;checking=1;launch();while(!done)@(negedge clk);
  checking=0;$display("DONE %0d %0d %0d",mode,overflow,reads);@(negedge clk);
 end
 $display("HAND_BLOB_RGB_PASS cycles=%0d",ticks);$finish;
end
endmodule
