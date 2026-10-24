`timescale 1ns/1ps
module tb_hand_motion_capture;
reg clk=0;always #5 clk=~clk;
reg rst=0,valid=0,last=0,user=0;reg[95:0]rgb=0;
wire sv,fd;wire[9:0]x,y;wire[95:0]aligned_rgb;
ua_motion_detect #(.IMG_WIDTH(1280),.IMG_HEIGHT(720),.Y_DOWNSAMPLE(4),.ROI_ENABLE(0),.COMPACT_REFERENCE_RAM(1)) adapter(
 .I_clk(clk),.I_rst_n(rst),.I_tlast(last),.I_tuser(user),.I_tdata(rgb),.I_tvalid(valid),.I_tready(1'b1),.I_background_restart(1'b0),
 .O_tlast(),.O_tuser(),.O_tdata(aligned_rgb),.O_tvalid(),.O_tready(),.O_motion_sample_valid(),
 .O_hand_sample_valid(sv),.O_hand_frame_done(fd),.O_motion_hit(),.O_motion_x_grp(x),.O_motion_y(y),.O_motion_valid(),.O_motion_count());
wire result,box,fault,drop;wire[1:0]id,raw;wire[2:0]tips;
wire[7:0]bx,bw;wire[6:0]by,bh;wire[31:0]cycles;
ua_hand_binary_native dut(clk,rst,1'b0,sv,fd,x,y,aligned_rgb,result,id,raw,tips,box,bx,bw,by,bh,fault,drop,cycles);
reg[31:0]samples[0:57599];reg[4095:0]path;
integer f,r,c,k,idx,source,handle,rc,bytes,preroll=0,completed=0,sampled=0,frames_done=0;
function[95:0]rgb4(input[31:0]p);
 integer j;reg[9:0]a,b,cc;reg[7:0]ra,ga,ba;
 begin a=p[29:20];b=p[19:10];cc=p[9:0];for(j=0;j<4;j=j+1)begin
  ra=(a>>2)+(j<a[1:0]);ga=(b>>2)+(j<b[1:0]);ba=(cc>>2)+(j<cc[1:0]);
  rgb4[95-j*24-:24]={ra,ga,ba};end end
endfunction
always @(negedge clk)if(rst)begin
 if(sv)begin
  if(y[1:0]!=3 || x>=320 || y>=720)$fatal(1,"Adapter coordinate phase x=%d y=%d",x,y);
  if(aligned_rgb!==rgb4(samples[(y>>2)*320+x]))$fatal(1,"Adapter RGB skew x=%d y=%d",x,y);
  sampled=sampled+1;
 end
 if(fd)begin frames_done=frames_done+1;if(sampled!=57600*frames_done)$fatal(1,"Adapter frame/sample count %d frame=%d",sampled,frames_done);end
 if(dut.front_input_fault)$fatal(1,"Integrated input fault state=%d",dut.state);
 if(result)begin
  if(fault)$fatal(1,"Integrated detector fault state=%d ccl=%d shape=%d",dut.state,dut.ccl.state,dut.shape.state);
  completed=completed+1;
  $display("INTEGRATED_RESULT n=%d id=%d raw=%d box=%d bbox=%d,%d,%d,%d",completed,id,raw,box,bx,by,bw,bh);
  if(raw!=3 || bx!=74 || by!=45 || bw!=56 || bh!=45)$fatal(1,"Integrated RGB differs from isolated frame 210");
 end
end
initial begin
 if(!$value$plusargs("INPUT=%s",path))$fatal(1,"INPUT required");
 handle=$fopen(path,"rb");rc=$fseek(handle,210*230400,0);bytes=$fread(samples,handle);$fclose(handle);
 if(bytes!=230400)$fatal(1,"Short input");repeat(5)@(negedge clk);rst=1;
 // A partial startup line before SOF must not permanently shift coordinates.
 rc=$value$plusargs("PREROLL=%d",preroll);
 for(k=0;k<preroll;k=k+1)begin @(negedge clk);valid=1;user=0;last=0;rgb=0;end
 for(f=0;f<8;f=f+1)begin
  for(r=0;r<720;r=r+1)begin
   for(c=0;c<320;c=c+1)begin
    @(negedge clk);valid=1;user=(r==0&&c==0);last=(c==319);rgb=rgb4(samples[(r>>2)*320+c]);
   end
   @(negedge clk);valid=0;last=0;user=0;repeat(4)@(negedge clk);
  end
  repeat(100)@(negedge clk);
 end
 repeat(1000000)@(negedge clk);
 if(completed<2 || id!=3 || !box || frames_done!=8)$fatal(1,"Integrated incomplete results=%d id=%d frames=%d",completed,id,frames_done);
 $display("HAND_MOTION_CAPTURE_INTEGRATION_PASS results=%d samples=%d",completed,sampled);$finish;
end
endmodule
