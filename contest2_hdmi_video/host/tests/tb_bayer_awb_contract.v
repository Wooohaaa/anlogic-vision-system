`timescale 1ns/1ps
// Integration probe: real production border -> RGB packing -> real AWB RAM.
module tb_bayer_awb_contract;
  parameter W=1280,H=6,BUBBLES=2,CHANNEL_BITS=9;
  reg clk=0,rst=0,v=0,u=0,l=0;
  reg [39:0] raw=0;
  always #5 clk=~clk;
  wire [127:0] rgb;
  wire dv,du,dl;
  wire [95:0] input96;
  wire [12*CHANNEL_BITS-1:0] output96;
  wire av,au,al;
  wire pv,pu,pl,packed_v,packed_u;
  wire [95:0] photo_data;
  wire [127:0] packed_data;
  reg pending=0;
  always @(posedge clk or negedge rst)
    if(!rst) pending<=0;
    else begin
      if(au) pending<=1;
      if(av && (pending || au)) pending<=0;
    end
  ua_photo_finish_96 #(.IMG_WIDTH(W),.TONE_ENABLE(0),.INPUT_BITS(CHANNEL_BITS)) photo(
    clk,rst,av,av&&(pending||au),al,output96,2'd0,pv,pu,pl,photo_data);
  data_96bit_to_128bit packer(clk,rst,au,pv,photo_data,packed_u,packed_v,packed_data);
  reg [383:0] block_data;
  reg [127:0] expected_words[0:W*H*3*3/16-1];
  reg [127:0] actual_words[0:W*H*3*3/16-1];
  integer photo_count=0,word_count=0,words_ready=0;
  integer reset_left=0;
  always @(negedge clk) if(rst) begin
    if(packed_u) reset_left=9;
    else if(reset_left>0) reset_left=reset_left-1;
    if(pv) begin
      if(pu!==((photo_count%(W*H/4))==0) || pl!==((photo_count%(W/4))==W/4-1))
        $fatal(1,"photo marker mismatch group=%0d",photo_count);
      block_data={block_data[287:0],photo_data};
      photo_count=photo_count+1;
      if(photo_count%4==0) begin
        expected_words[words_ready]=block_data[383:256];
        expected_words[words_ready+1]=block_data[255:128];
        expected_words[words_ready+2]=block_data[127:0];
        words_ready=words_ready+3;
      end
    end
    if(packed_v) begin
      if(reset_left!=0) $fatal(1,"pixel discarded by video_in FIFO reset");
      actual_words[word_count]=packed_data;
      word_count=word_count+1;
    end
  end
  ua_demosaic_border #(.IMG_WIDTH(W),.IMG_HEIGHT(H)) border(
    .I_clk(clk),.I_rst_n(rst),.axi4s_video_tdata(raw),
    .axi4s_video_tdest(10'd0),.axi4s_video_tlast(l),
    .axi4s_video_tvalid(v),.axi4s_video_tuser(u),.axi4s_video_tready(),
    .O_tlast(dl),.O_tuser(du),.O_tvalid(dv),.O_tdata(rgb),.O_tready(1'b1));
  data128_96 converter(rgb,input96);
  ua_awb_frame #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.OUTPUT_CHANNEL_BITS(CHANNEL_BITS)) awb(
    .I_clk(clk),.I_rst_n(rst),.I_tlast(dl),.I_tuser(du),.I_tdata(input96),.I_tvalid(dv),.I_tready(),.O_tlast(al),.O_tuser(au),.O_tdata(output96),.O_tvalid(av),.O_tready(1'b1));
  reg [12*CHANNEL_BITS-1:0] expected[0:W*H*3/4-1];
  integer entered=0,exited=0,x,y,f,k,base,ch,wi;
  always @(negedge clk) if(rst) begin
    if(dv) begin
      for(ch=0;ch<12;ch=ch+1) expected[entered][ch*CHANNEL_BITS+:CHANNEL_BITS]=input96[ch*8+:8];
      entered=entered+1;
    end
    if(av) begin
      if(exited>=entered || output96!==expected[exited])
        $fatal(1,"AWB integrated RGB mismatch group=%0d entered=%0d actual=%h expected=%h hcnt=%0d rdcnt=%0d",exited,entered,output96,expected[exited],awb.u_awb_line_delay.h_cnt,awb.u_awb_line_delay.rd_cnt);
      exited=exited+1;
    end
  end
  initial begin
    force awb.gain_r=20'd65536;force awb.gain_b=20'd65536;
    repeat(4) @(negedge clk);rst=1;
    for(f=0;f<3;f=f+1) begin
      for(y=0;y<H;y=y+1) begin
        for(x=0;x<W;x=x+4) begin
          @(negedge clk);v=1;u=(x==0&&y==0);l=x==W-4;
          for(k=0;k<4;k=k+1) begin
            base=(!y[0]&&((x+k)%2==0))?180:(y[0]&&((x+k)%2!=0))?40:100;
            raw[k*10+:10]=10'((base+(x+y+f)%20)*4);
          end
          if(BUBBLES!=0) begin
            @(negedge clk);v=0;u=0;l=0;
            repeat(2) @(negedge clk);
          end
        end
        @(negedge clk);v=0;u=0;l=0;
        repeat(100) @(negedge clk);
      end
      repeat(W+300) @(negedge clk);
      if(exited!=entered || entered!=(f+1)*W*H/4 || photo_count!=entered || word_count!=(f+1)*W*H*3/16)
        $fatal(1,"AWB integrated count f=%0d entered=%0d exited=%0d expected=%0d",f,entered,exited,(f+1)*W*H/4);
      for(wi=0;wi<word_count;wi=wi+1)
        if(actual_words[wi]!==expected_words[wi]) $fatal(1,"RGB packed byte order mismatch word=%0d",wi);
    end
    $display("BAYER_AWB_INTEGRATION_PASS groups=%0d packed_words=%0d sparse=%0d",exited,word_count,BUBBLES);
    $finish;
  end
endmodule
