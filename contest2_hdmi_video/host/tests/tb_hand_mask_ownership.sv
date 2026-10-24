`timescale 1ns/1ps
// Small legal geometry exercises the same bank allocator and processing FSM.
// Includes real synchronous frontend->CCL read handshake, not a stubbed mask.
module tb_hand_mask_ownership;
reg clk=0; always #5 clk=~clk;
reg rst=0,clear=0,valid=0,frame_done=0,release_mask=0;
reg [9:0] x=0,y=0;reg [95:0] rgb=0;
reg manual_read=0,run_ccl=0,ccl_start=0;
reg [11:0] manual_addr=0;
wire mask_valid,bank,read_valid,drop,fault;
wire [15:0] frame_id;wire [17:0] data;wire [31:0] cycles;
wire unused_nv,unused_nb,unused_bright;wire[13:0]unused_na;wire[9:0]unused_nr;
wire ccl_read,ccl_busy,ccl_done,ccl_overflow,blob;
wire [11:0] ccl_addr;wire [13:0] area,seeds;
wire [7:0] xmin,xmax;wire [6:0] ymin,ymax;
wire unused_red_read;wire[13:0]unused_red_addr;wire[23:0]unused_red_sum;
wire[7:0]unused_anchor_x;wire[6:0]unused_anchor_y;
integer drops=0,blobs=0,expected_color=0;
ua_hand_mask_frame #(.IMG_WIDTH(96),.IMG_HEIGHT(64)) frontend(
 clk,rst,clear,valid,frame_done,x,y,rgb,mask_valid,bank,frame_id,release_mask,
 run_ccl ? ccl_read : manual_read,run_ccl ? ccl_addr : manual_addr,
 read_valid,data,drop,fault,cycles,1'b1,unused_nv,unused_nb,unused_bright,unused_na,unused_nr);
ua_hand_blob_scan #(.WIDTH(12),.HEIGHT(8)) ccl(
 clk,rst,clear,ccl_start,1'b1,ccl_read,ccl_addr,
 read_valid && run_ccl,data,ccl_busy,ccl_done,ccl_overflow,blob,
 area,seeds,xmin,xmax,ymin,ymax,unused_anchor_x,unused_anchor_y,
 unused_red_read,unused_red_addr,1'b0,10'd0,unused_red_sum);
always @(posedge clk) begin
 #1;
 if(drop) drops=drops+1;
 if(blob) begin
  blobs=blobs+1;
  if(expected_color!=1 || area!=96 || seeds!=96 || xmin!=0 || xmax!=11 || ymin!=0 || ymax!=7)
   $fatal(1,"integrated CCL mismatch area=%d seeds=%d box=%d,%d,%d,%d",area,seeds,xmin,xmax,ymin,ymax);
 end
end
task send_frame(input integer color,input integer malformed);
 integer row,col;
 begin
  for(row=0;row<8;row=row+1) begin
   for(col=0;col<24;col=col+1) begin
    @(negedge clk);valid=!(malformed && row==3 && col==13);x=col;y=row*8+7;
    case(color)
     0:rgb={4{24'h142864}};
     1:rgb={4{24'ha06840}};
     2:rgb={4{24'h181614}};
    endcase
    if(col%7==0) begin @(negedge clk);valid=0;repeat(2)@(negedge clk);end
   end
   @(negedge clk);valid=0;repeat(2)@(negedge clk);
  end
  repeat(3)@(negedge clk);frame_done=1;
  @(negedge clk);frame_done=0;
 end
endtask
task wait_ready(input integer wanted);
 integer elapsed;
 begin
  elapsed=0;
  while(!mask_valid && elapsed<10000)begin @(negedge clk);elapsed=elapsed+1;end
  if(!mask_valid || frame_id!=wanted || fault)
   $fatal(1,"bad publication wanted=%d id=%d valid=%b fault=%b",wanted,frame_id,mask_valid,fault);
 end
endtask
task verify(input integer color);
 integer addr,elapsed;reg [17:0] expected;
 begin
  expected=color==1 ? 18'h3ffff : color==2 ? 18'h12492 : 18'd0;
  for(addr=0;addr<16;addr=addr+1)begin
   @(negedge clk);manual_read=1;manual_addr=addr;
   @(negedge clk);manual_read=0;
   if(!read_valid || data!==expected)$fatal(1,"bank overwritten color=%d addr=%d data=%h",color,addr,data);
   repeat(addr%3)@(negedge clk);
  end
  @(negedge clk);run_ccl=1;ccl_start=1;blobs=0;expected_color=color;
  @(negedge clk);ccl_start=0;elapsed=0;
  while(!ccl_done && elapsed<10000)begin @(negedge clk);elapsed=elapsed+1;end
  if(!ccl_done || ccl_overflow || blobs!=(color==1 ? 1 : 0))$fatal(1,"CCL completion mismatch");
  @(negedge clk);run_ccl=0;
 end
endtask
task release_frame;
 begin
  @(negedge clk);release_mask=1;@(negedge clk);release_mask=0;
  if(mask_valid)$fatal(1,"release failed");
 end
endtask
initial begin
 repeat(4)@(negedge clk);rst=1;
 send_frame(1,0);wait_ready(0);verify(1);
 send_frame(0,0); // Other bank can capture while consumer holds the first.
 send_frame(2,0); // Both banks owned: whole detection frame must be dropped.
 if(drops!=1 || frame_id!=0 || !mask_valid)$fatal(1,"busy-bank drop failed");
 verify(1);release_frame();wait_ready(1);verify(0);release_frame();
 send_frame(2,0);wait_ready(3);verify(2);release_frame();
 send_frame(1,1);repeat(3000)@(negedge clk);
 if(mask_valid || !fault || drops!=2)$fatal(1,"malformed frame published or not rejected");
 clear=1;repeat(2)@(negedge clk);clear=0;
 if(mask_valid || fault || ccl_busy)$fatal(1,"clear failed");
 send_frame(1,0);repeat(20)@(negedge clk); // Clear in the middle of morphology.
 clear=1;repeat(2)@(negedge clk);clear=0;
 send_frame(0,0);wait_ready(6);verify(0);release_frame();
 // Reset while ready must also reset frame sequence and all ownership.
 send_frame(1,0);wait_ready(7);
 rst=0;repeat(3)@(negedge clk);rst=1;
 send_frame(1,0);wait_ready(0);verify(1);release_frame();
 $display("HAND_MASK_OWNERSHIP_CCL_PASS drop_hold_clear_reset_and_real_read_handshake");$finish;
end
initial begin #2000000;$fatal(1,"ownership test watchdog");end
endmodule
