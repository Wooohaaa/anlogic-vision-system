`timescale 1ns/1ps
module tb_digit_auto_v93;
 parameter W=320,H=240,GAPS=0,SCENES=40,CASE_BASE=0;
 localparam G=W/4;
 reg clk=0,rst=0,v=0,u=0,l=0;reg [95:0] rgb=0;
 always #5 clk=~clk;
 wire dv,event_out;wire [3:0] id;wire [7:0] conf;wire [56:0] view;
 ua_digit_recognizer #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.AUTO_FIND(1)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_tlast(l),.I_tuser(u),.I_tdata(rgb),.I_tvalid(v),
 .O_digit_valid(dv),.O_digit_id(id),.O_digit_confidence(conf),
 .O_result_event(event_out),.O_result_view(view));
 reg [34:0] glyph[0:9];
 integer scene,f,x,y,lane,px,gray,col,row,dx,dy,cw,ch,font_cell,whitelevel,inklevel;
 integer expected_digit,accepted=0,events=0,seen,boxchecks=0;
 reg [56:0] last_view;
 always @(posedge clk)begin #1;
  if(event_out)begin events=events+1;last_view=view;end
  if(dv)begin
   if(expected_digit<0 || id!==expected_digit[3:0])
    $fatal(1,"AUTO_DIGIT_WRONG scene=%0d want=%0d got=%0d f=%0d bits=%h roi=%d,%d %d,%d",scene,expected_digit,id,f,dut.observed_bits,dut.card_x0,dut.card_x1,dut.card_y0,dut.card_y1);
   if(view[43:33]<dx || view[32:22]>=dx+cw || view[21:11]<dy || view[10:0]>=dy+ch+4)
    $fatal(1,"auto box not on card");
   accepted=accepted+1;seen=seen+1;boxchecks=boxchecks+1;
  end
 end
 initial begin
  glyph[0]=35'b01110_10001_10001_10001_10001_10001_01110;
  glyph[1]=35'b00100_01100_00100_00100_00100_00100_01110;
  glyph[2]=35'b01110_10001_00001_00010_00100_01000_11111;
  glyph[3]=35'b11110_00001_00001_01110_00001_00001_11110;
  glyph[4]=35'b00010_00110_01010_10010_11111_00010_00010;
  glyph[5]=35'b11111_10000_10000_11110_00001_00001_11110;
  glyph[6]=35'b01110_10000_10000_11110_10001_10001_01110;
  glyph[7]=35'b11111_00001_00010_00100_01000_01000_01000;
  glyph[8]=35'b01110_10001_10001_01110_10001_10001_01110;
  glyph[9]=35'b01110_10001_10001_01111_00001_00001_01110;
  for(scene=0;scene<SCENES;scene=scene+1)begin
   @(negedge clk);rst=0;v=0;u=0;l=0;repeat(4)@(negedge clk);rst=1;seen=0;
   expected_digit=(scene+CASE_BASE)%10;font_cell=(scene+CASE_BASE>=30)?16:12;
   cw=5*font_cell+36;ch=7*font_cell+48;
   dx=(scene+CASE_BASE<10)?16:((scene+CASE_BASE<20)?W-cw-16:(W/2-cw/2));
   dy=(scene+CASE_BASE<10)?12:((scene+CASE_BASE<20)?H-ch-16:(H/2-ch/2));
   whitelevel=(scene+CASE_BASE>=20 && scene+CASE_BASE<30)?112:220;
   inklevel=(scene+CASE_BASE>=20 && scene+CASE_BASE<30)?40:24;
   for(f=0;f<10;f=f+1)begin
    for(y=0;y<H;y=y+1)for(x=0;x<G;x=x+1)begin
     @(negedge clk);v=1;u=x==0&&y==0;l=x==G-1;
     for(lane=0;lane<4;lane=lane+1)begin
      px=x*4+lane;gray=22;
      if(px>=dx && px<dx+cw && y>=dy && y<dy+ch)begin
       gray=whitelevel;
       if(px>=dx+16 && px<dx+16+5*font_cell && y>=dy+24 && y<dy+24+7*font_cell)begin
        col=(px-dx-16)/font_cell;row=(y-dy-24)/font_cell;
        if(glyph[expected_digit][34-row*5-col])gray=inklevel;
       end
      end
      gray=gray+((px+y+f)%5)-2;
      rgb[95-lane*24-:24]={3{8'(gray)}};
     end
     if(GAPS && x%13==7)begin @(negedge clk);v=0;u=0;l=0;end
    end
    @(negedge clk);v=0;u=0;l=0;repeat(400)@(negedge clk);
    if(scene==0)$display("AUTO_FRAME f=%0d roi=%b fg=%b geom=%b state=%0d bits=%h",f,dut.card_found,dut.fg_seen,dut.geometry_ready,dut.state,dut.observed_bits);
   end
   if(seen==0)$fatal(1,"AUTO_NO_RESULT scene=%0d digit=%0d card=%b bounds=%d,%d %d,%d fg=%b geom=%b bits=%h",scene,expected_digit,dut.card_found,dut.card_x0,dut.card_x1,dut.card_y0,dut.card_y1,dut.fg_seen,dut.geometry_ready,dut.observed_bits);
   // Remove card without resetting: the next completed result must clear it.
   expected_digit=-1;
   for(f=0;f<3;f=f+1)begin
    for(y=0;y<H;y=y+1)for(x=0;x<G;x=x+1)begin
     @(negedge clk);v=1;u=x==0&&y==0;l=x==G-1;rgb={12{8'd22}};
    end
    @(negedge clk);v=0;u=0;l=0;repeat(400)@(negedge clk);
   end
   if(last_view[56])$fatal(1,"stale result after removal");
   $display("AUTO_DIGIT_SCENE_PASS scene=%0d results=%0d",scene,seen);
  end
  $display("DIGIT_AUTO_V93_PASS scenes=%0d valid_results=%0d bbox=%0d events=%0d",SCENES,accepted,boxchecks,events);$finish;
 end
 initial begin #1000000000;$fatal(1,"watchdog");end
endmodule
