`timescale 1ns/1ps
module tb_photo_v60_equivalence;
 parameter W=1280,H=720,BITS=9,FIVE=1,RECURSIVE=0,TONE=1;
 localparam G=W/4;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,valid=0,user=0,last=0;reg[12*BITS-1:0]data=0;reg[1:0]strength=0;
 wire v0,u0,l0,v1,u1,l1;wire[95:0]d0,d1;
 ua_photo_finish_v59_reference #(.IMG_WIDTH(W),.INPUT_BITS(BITS),.WINDOW5(FIVE),.RECURSIVE_VERTICAL(RECURSIVE),.TONE_ENABLE(TONE),.COMPACT_FINITE_HISTORY(1),.RUNTIME_STRENGTH(1),.HIGHLIGHT_SAFE_LIFT(1))old_core
 (clk,rst,valid,user,last,data,strength,v0,u0,l0,d0);
 ua_photo_finish_96 #(.IMG_WIDTH(W),.INPUT_BITS(BITS),.WINDOW5(FIVE),.RECURSIVE_VERTICAL(RECURSIVE),.TONE_ENABLE(TONE),.COMPACT_FINITE_HISTORY(1),.RUNTIME_STRENGTH(1),.HIGHLIGHT_SAFE_LIFT(1))new_core
 (clk,rst,valid,user,last,data,strength,v1,u1,l1,d1);
 integer cycles=0,outputs=0,frames=0,lines=0,collisions=0,unknowns=0;
 always @(negedge clk)if(rst)begin
  cycles=cycles+1;
  if({v0,u0,l0,d0}!=={v1,u1,l1,d1})$fatal(1,"photo mismatch cycle=%0d old=%h new=%h",cycles,{v0,u0,l0,d0},{v1,u1,l1,d1});
  if(v1)begin
   outputs=outputs+1;if(u1)frames=frames+1;if(l1)lines=lines+1;
   if($isunknown(d1))unknowns=unknowns+1;
  end
  if(new_core.h_valid && new_core.read_addr==new_core.write_addr)collisions=collisions+1;
 end
 task tick(input v,u,l,input[12*BITS-1:0]d);
 begin @(posedge clk);#1;valid=v;user=u;last=l;data=d;end endtask
 integer f,y,x,k,value;reg[31:0]rng=32'h63902719;reg[12*BITS-1:0]word;
 initial begin
  repeat(5)tick(0,0,0,0);rst=1;
  for(f=0;f<5;f=f+1)begin
   strength=f%4;
   for(y=0;y<H;y=y+1)begin
    for(x=0;x<G;x=x+1)begin
     for(k=0;k<12;k=k+1)begin
      rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
      case(f)
      0:value=(x*4+k/3+y)%37+(rng%19); // admitted dark noise
      1:value=(x%3==0 ? (1<<BITS)-1 : ((y+x)%43)); // sharp highlights
      2:value=(x*4+y+k/3)%(1<<BITS); // full headroom ramp
      3:value=rng%(1<<BITS); // unrelated channels and range rejections
      default:value=((x+y)%2) ? 64+(rng%11) : 58+(rng%11); // threshold boundary
      endcase
      word[k*BITS+:BITS]=value;
     end
     if(f%2 && x%17==3)repeat(3)tick(0,0,0,0);
     tick(1,y==0 && x==0,x==G-1,word);
    end
    if(f%2)repeat(y%4)tick(0,0,0,0);
    if(f==2 && y==H/2)begin
     tick(0,0,0,0);rst=0;repeat(4)tick(0,0,0,0);rst=1;y=H;
    end
   end
   $display("PHOTO_V60_FRAME_DONE frame=%0d cycles=%0d outputs=%0d",f,cycles,outputs);
  end
  repeat(20)tick(0,0,0,0);
  if(outputs<4*H*G || frames<4 || lines<4*H || unknowns!=0)
   $fatal(1,"coverage outputs=%0d frames=%0d lines=%0d collisions=%0d unknowns=%0d",outputs,frames,lines,collisions,unknowns);
  $display("PHOTO_V60_EQUIVALENCE_PASS W=%0d H=%0d BITS=%0d FIVE=%0d RECURSIVE=%0d TONE=%0d cycles=%0d outputs=%0d",W,H,BITS,FIVE,RECURSIVE,TONE,cycles,outputs);$finish;
 end
 initial begin #200000000;$fatal(1,"timeout");end
endmodule
