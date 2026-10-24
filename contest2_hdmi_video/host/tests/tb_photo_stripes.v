`timescale 1ns/1ps
module tb_photo_stripes;
 parameter WIDTH=1280;
 parameter BITS=9;
 parameter LEVEL=24;
 parameter SETTLE_ROW=5;
 localparam GROUPS=WIDTH/4,HEIGHT=32,WORDS=GROUPS*HEIGHT;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,valid=0,user=0,last=0;
 reg [12*BITS-1:0] data=0;
 wire ov,ou,ol;wire [95:0] out;
 integer sent=0,received=0,pre_received=0,f,w,lane,channel,pixel,row;
 ua_photo_finish_96 #(.IMG_WIDTH(WIDTH),.INPUT_BITS(BITS),.TONE_ENABLE(0)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_tvalid(valid),.I_tuser(user),.I_tlast(last),
 .I_tdata(data),.I_strength(2'd2),.O_tvalid(ov),.O_tuser(ou),.O_tlast(ol),.O_tdata(out));
 always @(posedge clk) begin
  #1;
  if(rst && dut.v_valid)begin
   if((pre_received%WORDS)/GROUPS>=SETTLE_ROW && dut.v_data !== {12{BITS'(LEVEL)}})
    $fatal(1,"pre-tone band beat=%d rgb=%h level=%d",pre_received,dut.v_data,LEVEL);
   pre_received=pre_received+1;
  end
  if(rst && ov)begin
   row=(received%WORDS)/GROUPS;
   if(ou !== (received%WORDS==0) || ol !== (received%GROUPS==GROUPS-1))
    $fatal(1,"marker misalignment beat=%d",received);
   if(row>=SETTLE_ROW && out !== {12{8'(LEVEL>255 ? 255 : LEVEL)}})
    $fatal(1,"persistent vertical band beat=%d row=%d rgb=%h",received,row,out);
   received=received+1;
  end
 end
 initial begin
  repeat(4)@(negedge clk);rst=1;
  for(f=0;f<2;f=f+1)begin
   for(w=0;w<WORDS;w=w+1)begin
    @(negedge clk);valid=1;user=(w==0);last=(w%GROUPS==GROUPS-1);
    for(lane=0;lane<4;lane=lane+1)begin
     pixel=(w<GROUPS)?LEVEL+((w*4+lane+f)%9)-4:LEVEL;
     if(pixel<0)pixel=0;
     if(pixel>((1<<BITS)-1))pixel=(1<<BITS)-1;
     for(channel=0;channel<3;channel=channel+1)
      data[((3-lane)*3+channel)*BITS+:BITS]=pixel;
    end
    sent=sent+1;
    if(w%7==6)begin @(negedge clk);valid=0;user=0;last=0;end
   end
   @(negedge clk);valid=0;user=0;last=0;
   repeat(12)@(negedge clk);
  end
  if(received!=sent || pre_received!=sent)$fatal(1,"beat loss %d/%d",received,sent);
  $display("PHOTO_STRIPE_PASS width=%d bits=%d level=%d beats=%d settle_row=%d markers bubbles frames",WIDTH,BITS,LEVEL,received,SETTLE_ROW);
  $finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
