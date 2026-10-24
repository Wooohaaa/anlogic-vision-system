`timescale 1ns/1ps
module tb_algo_ram_v70;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,valid=0,sof=0,eol=0;reg[95:0]rgb=0;reg[2:0]mode=0;
 wire av,au,al,bv,bu,bl;wire[95:0]a,b;
 ua_user_algo_96 #(.IMG_WIDTH(1280),.IMG_HEIGHT(720)) dut(clk,rst,eol,sof,rgb,valid,mode,1'b1,al,au,a,av,);
 ua_user_algo_v69_reference #(.IMG_WIDTH(1280),.IMG_HEIGHT(720)) ref_dut(clk,rst,eol,sof,rgb,valid,mode,1'b1,bl,bu,b,bv,);
 integer frame,x,y,k,seed=70,count=0;
 always @(negedge clk)begin
   if({av,au,al}!=={bv,bu,bl} || a!==b)$fatal(1,"Cycle mismatch mode=%d count=%d a=%h b=%h av=%b bv=%b",mode,count,a,b,av,bv);
   if(av)count=count+1;
 end
 task sample(input v,input s,input l);
   begin @(posedge clk);#1;valid=v;sof=s;eol=l;rgb={$random(seed),$random(seed),$random(seed)};end
 endtask
 initial begin
  repeat(3)@(posedge clk);#1;rst=1;
  for(frame=0;frame<7;frame=frame+1)begin
   mode=frame;repeat(4)sample(0,0,0);
   for(y=0;y<720;y=y+1)for(x=0;x<320;x=x+1)begin
    if((x+y)%71==0)sample(0,0,0);
    sample(1,x==0 && y==0,x==319);
   end
   repeat(16)sample(0,0,0);
   // Reset with filled memories: stale RAM contents must never become valid.
   @(posedge clk);#1;rst=0;valid=0;sof=0;eol=0;
   repeat(3)@(posedge clk);#1;rst=1;
  end
  repeat(16)sample(0,0,0);
  if(count!=7*320*720)$fatal(1,"Missing pixels %d",count);
  $display("ALGO_RAM_V70_BIT_EXACT_PASS seven_full_720p_modes bubbles resets pixels=%d",count);$finish;
 end
 initial begin #50000000;$fatal(1,"timeout");end
endmodule
