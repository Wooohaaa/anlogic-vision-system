`timescale 1ns/1ps
module tb_hand_native_capture_gate;
reg clk=0;always #5 clk=~clk;
reg rst=0,clear=0,valid=0,frame_done=0,release_mask=0,allow=0;
reg[9:0]x=0,y=0;reg[95:0]rgb={4{24'ha06840}};
wire mv,bank,rv,drop,fault,nv,nb,bright;wire[15:0]fid;wire[17:0]data;wire[31:0]cycles;wire[13:0]na;wire[9:0]nr;
ua_hand_mask_frame #(.IMG_WIDTH(96),.IMG_HEIGHT(64),.EXTERNAL_CAPTURE_GATE(1)) dut(
 clk,rst,clear,valid,frame_done,x,y,rgb,mv,bank,fid,release_mask,1'b0,12'd0,rv,data,drop,fault,cycles,
 allow,nv,nb,bright,na,nr);
integer row,col,samples=0,drops=0,wait_cycles;
reg checking=0,expected_bank;
always @(posedge clk)begin
 #1;
 if(drop)drops=drops+1;
 if(nv)begin
  if(!checking || na!=samples || nr!=640 || bright)$fatal(1,"native tap ordering/data/permission");
  if(samples==0)expected_bank=nb;else if(nb!==expected_bank)$fatal(1,"bank changed");
  samples=samples+1;
 end
end
task send(input integer toggle_midway);
begin
 for(row=0;row<8;row=row+1)begin
  for(col=0;col<24;col=col+1)begin
   @(negedge clk);valid=1;x=col;y=row*8+7;
   if(toggle_midway && row==3 && col==0)allow=0;
   if(col%7==0)begin @(negedge clk);valid=0;repeat(2)@(negedge clk);end
  end
  @(negedge clk);valid=0;
 end
 repeat(3)@(negedge clk);frame_done=1;@(negedge clk);frame_done=0;
end endtask
initial begin
 repeat(5)@(negedge clk);rst=1;
 send(0);repeat(1500)@(negedge clk);
 if(mv || samples || drops!=1 || fault)$fatal(1,"denied capture allocated/published");
 allow=1;checking=1;send(1);
 wait_cycles=0;while(!mv && wait_cycles<10000)begin @(negedge clk);wait_cycles=wait_cycles+1;end
 if(!mv || samples!=96 || fid!=1 || bank!==expected_bank || fault)$fatal(1,"mid-frame permission corrupted transaction");
 checking=0;release_mask=1;@(negedge clk);release_mask=0;
 send(0);repeat(1500)@(negedge clk);
 if(mv || samples!=96 || drops!=2)$fatal(1,"new denied frame overwrote native data");
 clear=1;@(negedge clk);clear=0;if(mv || nv || fault)$fatal(1,"clear");
 $display("HAND_NATIVE_CAPTURE_GATE_PASS denied_frames=2 allowed_pixels=96");$finish;
end
initial begin #2000000;$fatal(1,"timeout");end
endmodule
