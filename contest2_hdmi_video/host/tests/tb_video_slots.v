`timescale 1ns/1ps
// Control-level test only; FIFO stub does not model DDR contents.
module w128_d512_fifo(input rst,clkw,we,input[127:0]di,output afull,full_flag,
 output[8:0]wrusedw,input clkr,re,output[127:0]dout,output[8:0]rdusedw,
 output valid,empty_flag,aempty);
 assign rdusedw=rst?0:9'd300;assign dout=di;
 assign wrusedw=0;assign afull=0;assign full_flag=0;assign valid=re;
 assign empty_flag=0;assign aempty=0;
endmodule
module tb_video_slots;
 reg cam=0,ddr=0,rst=1,fs=0;
 always #8 cam=~cam;always #7.5 ddr=~ddr;
 wire[1:0]rp;
 video_in dut(.I_rst_n(rst),.I_camera_clk(cam),.I_camera_frame_start(fs),
 .I_camera_valid(1'b1),.I_camera_data(128'h1234),.I_mipi_rx_error(1'b0),
 .I_ddr_clk(ddr),.I_video_out_rd_busy(1'b0),.O_video_out_rp(rp),
 .O_video_in_wr_busy(),.O_ddr_user_wr_en(),.O_ddr_user_addr(),
 .O_ddr_user_wr_data(),.I_ddr_user_ready(1'b1),.O_meta_start(),.O_meta_slot());
 integer i,previous;
 initial begin
  #1 rst=0;#104 rst=1;
  for(i=0;i<20;i=i+1) begin
   previous=dut.S_video_in_wp;
   @(negedge cam);fs=1;repeat(4) @(negedge cam);fs=0;
   repeat(1100) @(negedge ddr);
   if(dut.S_video_in_wp!==((previous+1)%4) || rp!==((previous+2)%4))
    $fatal(1,"DDR frame rotation stalled or slot mapping changed frame=%d",i);
  end
  $display("VIDEO_SLOTS_PASS 20_frames four_slots continuous_no_freeze");$finish;
 end
endmodule
