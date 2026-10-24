`timescale 1ns/1ps
module tb_hand_tip_width;
reg clk=0;always #5 clk=~clk;
reg rst=0,clear=0,start=0;reg[7:0]w,cx,tx;reg[6:0]h,cy,ty;reg[10:0]radius;
wire sr,probe,busy,done,fault,narrow;wire[7:0]px;wire[6:0]py;wire[1:0]valid;wire[8:0]wa,wb;
reg rv=0,pixel=0;reg[15:0]rng=16'h3157;
integer pending=0,pending_x=0,pending_y=0,delay_count=0,aborted=0;
wire pr=!pending && rng[2:0]!=0;
ua_hand_tip_width dut(clk,rst,clear,start,w,cx,tx,h,cy,ty,radius,sr,probe,px,py,pr,rv,pixel,busy,done,fault,narrow,valid,wa,wb);
reg mask[0:14399];reg[2047:0]path;
integer iw,ih,icx,icy,itx,ity,ir,ev,ewa,ewb,en,abort_stage=0,invalid=0,ticks=0,requests=0;
reg held=0;reg[14:0]held_xy;
always @(posedge clk)begin
 rng<={rng[14:0],rng[15]^rng[13]^rng[12]^rng[10]};rv<=0;ticks=ticks+1;
 if(ticks>40000)$fatal(1,"timeout");
 if(probe && pr)begin
  if(pending || px>=iw || py>=ih)$fatal(1,"probe outstanding/bounds");
  pending=1;pending_x=px;pending_y=py;delay_count=abort_stage==2 && !aborted ? 60 : 1+rng[1:0];requests=requests+1;
 end
 if(pending)begin
  if(delay_count==0)begin rv<=1;pixel<=mask[pending_y*iw+pending_x];pending=0;end
  else delay_count=delay_count-1;
 end
 if(!clear && rst)begin
  if(held && (!probe || {py,px}!==held_xy))$fatal(1,"probe changed while not accepted");
  held=probe && !pr;held_xy={py,px};
 end else held=0;
end
task launch;
begin while(!sr)@(negedge clk);start=1;@(negedge clk);start=0;end endtask
initial begin
 if(!$value$plusargs("INPUT=%s",path)||!$value$plusargs("W=%d",iw)||!$value$plusargs("H=%d",ih)||
    !$value$plusargs("CX=%d",icx)||!$value$plusargs("CY=%d",icy)||!$value$plusargs("TX=%d",itx)||!$value$plusargs("TY=%d",ity)||
    !$value$plusargs("R=%d",ir)||!$value$plusargs("VALID=%d",ev)||!$value$plusargs("WA=%d",ewa)||!$value$plusargs("WB=%d",ewb)||!$value$plusargs("NARROW=%d",en))$fatal(1,"arguments");
 if($value$plusargs("ABORT=%d",abort_stage))begin end
 if($value$plusargs("FAULT=%d",invalid))begin end
 w=iw;h=ih;cx=icx;cy=icy;tx=itx;ty=ity;radius=ir;
 $readmemb(path,mask,0,iw*ih-1);repeat(5)@(negedge clk);rst=1;
 if(abort_stage)begin
  launch();
  case(abort_stage)
   1:repeat(5)@(negedge clk);
   2:while(!pending || delay_count<20)@(negedge clk);
   3:while(!dut.cut || dut.state!=15)@(negedge clk);
  endcase
  @(negedge clk);clear=1;@(negedge clk);clear=0;aborted=1;
  if(busy||done||probe)$fatal(1,"clear incomplete");
  if(abort_stage==2)begin
   if(sr)$fatal(1,"stale response not fenced");start=1;repeat(3)@(negedge clk);start=0;
   if(busy||probe)$fatal(1,"accepted start before old response drained");
  end
  while(!sr)begin @(negedge clk);if(done)$fatal(1,"late done after clear");end
 end
 launch();while(!done)@(negedge clk);
 if(fault!==invalid[0] || (!invalid && (valid!=ev || wa!=ewa || wb!=ewb || narrow!==en[0])))
  $fatal(1,"tip width valid=%0d/%0d width=%0d,%0d/%0d,%0d narrow=%0d/%0d fault=%0d",valid,ev,wa,wb,ewa,ewb,narrow,en,fault);
 @(negedge clk);if(done)$fatal(1,"done not pulse");
 $display("HAND_TIP_WIDTH_PASS requests=%0d cycles=%0d",requests,ticks);$finish;
end
endmodule
