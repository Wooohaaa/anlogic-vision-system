`timescale 1ns/1ps
module tb_track_v41_equivalence;
 parameter WIDTH=64, HEIGHT=48, FRAMES=24, FRAME_GAP=40;
 reg clk=0,rst=0,last=0,user=0,valid=0,ready=1;always #5 clk=~clk;
 reg [95:0] data=0;wire [311:0] actual,golden;
ua_track_detect #(.IMG_WIDTH(WIDTH),.IMG_HEIGHT(HEIGHT)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_tlast(last),.I_tuser(user),.I_tvalid(valid),.I_tready(ready),.I_tdata(data),
 .O_tlast(actual[311]),.O_tuser(actual[310]),.O_tdata(actual[309:214]),.O_tvalid(actual[213]),.O_tready(actual[212]),
 .O_track_valid(actual[211]),.O_obj_cnt(actual[210:207]),
 .O_v0(actual[206]),.O_x0(actual[205:195]),.O_y0(actual[194:184]),.O_shape0(actual[183:182]),
 .O_xmin0(actual[181:171]),.O_xmax0(actual[170:160]),.O_ymin0(actual[159:149]),.O_ymax0(actual[148:138]),
 .O_v1(actual[137]),.O_x1(actual[136:126]),.O_y1(actual[125:115]),.O_shape1(actual[114:113]),
 .O_xmin1(actual[112:102]),.O_xmax1(actual[101:91]),.O_ymin1(actual[90:80]),.O_ymax1(actual[79:69]),
 .O_v2(actual[68]),.O_x2(actual[67:57]),.O_y2(actual[56:46]),.O_shape2(actual[45:44]),
 .O_xmin2(actual[43:33]),.O_xmax2(actual[32:22]),.O_ymin2(actual[21:11]),.O_ymax2(actual[10:0]));
track_v40_reference #(.IMG_WIDTH(WIDTH),.IMG_HEIGHT(HEIGHT)) ref_dut(
 .I_clk(clk),.I_rst_n(rst),.I_tlast(last),.I_tuser(user),.I_tvalid(valid),.I_tready(ready),.I_tdata(data),
 .O_tlast(golden[311]),.O_tuser(golden[310]),.O_tdata(golden[309:214]),.O_tvalid(golden[213]),.O_tready(golden[212]),
 .O_track_valid(golden[211]),.O_obj_cnt(golden[210:207]),
 .O_v0(golden[206]),.O_x0(golden[205:195]),.O_y0(golden[194:184]),.O_shape0(golden[183:182]),
 .O_xmin0(golden[181:171]),.O_xmax0(golden[170:160]),.O_ymin0(golden[159:149]),.O_ymax0(golden[148:138]),
 .O_v1(golden[137]),.O_x1(golden[136:126]),.O_y1(golden[125:115]),.O_shape1(golden[114:113]),
 .O_xmin1(golden[112:102]),.O_xmax1(golden[101:91]),.O_ymin1(golden[90:80]),.O_ymax1(golden[79:69]),
 .O_v2(golden[68]),.O_x2(golden[67:57]),.O_y2(golden[56:46]),.O_shape2(golden[45:44]),
 .O_xmin2(golden[43:33]),.O_xmax2(golden[32:22]),.O_ymin2(golden[21:11]),.O_ymax2(golden[10:0]));
 integer seed=417041,frame,x,y,n=0,v;reg[23:0]pixel;
 always @(posedge clk)begin #1;if(rst && actual!==golden)$fatal(1,"TRACK cycle mismatch frame=%0d x=%0d y=%0d",frame,x,y);n=n+1;end
 initial begin
  repeat(5)@(negedge clk);rst=1;
  for(frame=0;frame<FRAMES;frame=frame+1)begin
   for(y=0;y<HEIGHT;y=y+1)for(x=0;x<WIDTH/4;x=x+1)begin
    @(negedge clk);valid=1;ready=1;user=(x==0&&y==0);last=(x==WIDTH/4-1);
    case(frame%4)
     0:pixel=(x>=3&&x<=12&&y>=8&&y<=38)?24'hd02020:24'h808080;
     1:pixel=(x>=5&&x<=10&&y>=3&&y<=44)?24'h20d020:24'h000000;
     2:pixel=(x>=2&&x<=13&&y>=16&&y<=31)?24'h2020d0:24'h101010;
     default:pixel=$random(seed);
    endcase
    data={4{pixel}};
    if((x+y)%11==0)begin
     @(negedge clk);valid=0;user=0;last=0;repeat(2)@(negedge clk);
    end
   end
   @(negedge clk);valid=0;user=0;last=0;
   repeat(FRAME_GAP)@(negedge clk);
   if(frame==11)begin rst=0;repeat(4)@(negedge clk);rst=1;end
  end
  $display("TRACK_V41_CYCLE_EQUIVALENCE_PASS width=%0d height=%0d frames=%0d gap=%0d cycles=%0d",WIDTH,HEIGHT,FRAMES,FRAME_GAP,n);$finish;
 end
endmodule
