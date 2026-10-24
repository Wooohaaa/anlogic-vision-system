`timescale 1ns/1ps
// Independent model of the used generated-IP contract: synchronous port B,
// no output register/reset, old data on coincident read and write clocks.
module demosaic_legacy_contract #(parameter BITS=33)(
 input clka,wea,input [10:0]addra,input [BITS-1:0]dia,
 input clkb,input [10:0]addrb,output reg [BITS-1:0]dob);
 reg [BITS-1:0] mem[0:2047];
 always @(posedge clka) if(wea)mem[addra]<=dia;
 always @(posedge clkb)dob<=mem[addrb];
endmodule
module blk_mem_gen_demosaic(input clka,wea,input[10:0]addra,input[32:0]dia,
 input clkb,input[10:0]addrb,output[32:0]dob);
 demosaic_legacy_contract #(.BITS(33))m(.*);
endmodule
module blk_mem_gen_zhenghe(input clka,wea,input[10:0]addra,input[31:0]dia,
 input clkb,input[10:0]addrb,output[31:0]dob);
 demosaic_legacy_contract #(.BITS(32))m(.*);
endmodule
module tb_demosaic_compact;
 parameter W=1280,H=720;
 localparam G=W/4;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,user=0,valid=0,last=0;
 reg[32:0]data=0;
 wire lv0,lv1;wire[32:0]ld0,ld1;
 wire zv0,zv1,zu0,zu1,zl0,zl1;wire[31:0]zd0,zd1;
 line_buffer_demosaic #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.COMPACT_RAM(0))old_line
 (clk,rst,user,valid,data,lv0,ld0);
 line_buffer_demosaic #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.COMPACT_RAM(1))new_line
 (clk,rst,user,valid,data,lv1,ld1);
 zhenghe #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.DATA_WIDTH(32),.COMPACT_RAM(0))old_z
 (clk,rst,last,user,data[31:0],valid,zl0,zu0,zd0,zv0);
 zhenghe #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.DATA_WIDTH(32),.COMPACT_RAM(1))new_z
 (clk,rst,last,user,data[31:0],valid,zl1,zu1,zd1,zv1);
 integer cycle=0,lc=0,zc=0,collisions=0,invalid_data=0;
 always @(negedge clk) if(rst)begin
  cycle=cycle+1;
  if(lv0!==lv1 || {zv0,zu0,zl0}!=={zv1,zu1,zl1})$fatal(1,"sidebands cycle %0d",cycle);
  if(ld0!==ld1 || zd0!==zd1)$fatal(1,"RAM outputs cycle %0d",cycle);
  if(lv1)begin lc=lc+1;if($isunknown(ld1))invalid_data=invalid_data+1;end
  if(zv1)begin zc=zc+1;if($isunknown(zd1))invalid_data=invalid_data+1;end
  if(new_line.valid_d0 && new_line.addra==new_line.addrb)collisions=collisions+1;
  if(new_line.addra>=G || new_line.addrb>=G || new_z.addra>=G || new_z.addrb>=G)
   $fatal(1,"active line address exceeds exact depth");
 end
 task tick(input v,u,l,input[32:0]d);
 begin @(posedge clk);#1;valid=v;user=u;last=l;data=d;end endtask
 integer f,y,x,gap;
 initial begin
  repeat(5)@(posedge clk);#1;rst=1;
  for(f=0;f<6;f=f+1)begin
   // Reset without clearing RAM, including after a partial previous frame.
   if(f==3)begin tick(0,0,0,0);rst=0;repeat(3)tick(0,0,0,0);rst=1;end
   for(y=0;y<H;y=y+1)begin
    for(x=0;x<G;x=x+1)begin
     // Irregular packet gaps, while preserving the original line width.
     if(f%2 && x!=0 && (x%29==0))repeat((x%3)+1)tick(0,0,0,0);
     tick(1,y==0 && x==0,x==G-1,{(y==0 && x==0),32'((f*1234567)^(y*941)^(x*2221))});
    end
    repeat(90+(y%7))tick(0,0,0,0);
    if(f==2 && y==H/2)begin
     tick(0,0,0,0);rst=0;repeat(4)tick(0,0,0,0);rst=1;
     y=H;
    end
   end
   repeat(130)tick(0,0,0,0);
  end
  repeat(200)tick(0,0,0,0);
  if(lc<4*G*(H-1) || zc<4*G*(H-1) || collisions==0 || invalid_data!=0)
   $fatal(1,"coverage lc=%0d zc=%0d collisions=%0d unknown=%0d",lc,zc,collisions,invalid_data);
  $display("DEMOSAIC_COMPACT_EQUIVALENCE_PASS W=%0d H=%0d cycles=%0d line=%0d merged=%0d collisions=%0d",W,H,cycle,lc,zc,collisions);
  $finish;
 end
 initial begin #200000000;$fatal(1,"timeout");end
endmodule
