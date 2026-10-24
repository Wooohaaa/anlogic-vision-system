`timescale 1ns/1ps
module tb_digit_auto_negative_v93;
 localparam W=320,H=240,G=W/4;
 reg clk=0,rst=0,v=0,u=0,l=0;reg [95:0] rgb=0;
 always #5 clk=~clk;
 wire dv,ev;wire [3:0] id;wire [7:0] conf;wire [56:0] view;
 ua_digit_recognizer #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.AUTO_FIND(1)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_tlast(l),.I_tuser(u),.I_tdata(rgb),.I_tvalid(v),
 .O_digit_valid(dv),.O_digit_id(id),.O_digit_confidence(conf),.O_result_event(ev),.O_result_view(view));
 integer mode,f,x,y,k,px,grey,checks=0,events=0;
 always @(posedge clk)begin #1;if(rst)begin
  if(dv)$fatal(1,"false digit on negative scene mode=%0d id=%0d",mode,id);
  if(ev)events=events+1;
 end end
 initial begin
  for(mode=0;mode<8;mode=mode+1)begin
   @(negedge clk);rst=0;v=0;u=0;l=0;repeat(4)@(negedge clk);rst=1;
   for(f=0;f<7;f=f+1)begin
    for(y=0;y<H;y=y+1)for(x=0;x<G;x=x+1)begin
     @(negedge clk);v=1;u=x==0&&y==0;l=x==G-1;
     for(k=0;k<4;k=k+1)begin
      px=x*4+k;grey=22;
      case(mode)
       1:if(px>=40&&px<136&&y>=40&&y<172)grey=220; // blank card
       2:if(px<96&&y>=40&&y<172)grey=220; // clipped left
       3:grey=220; // featureless white wall, no card boundary
       4:if(px>=40&&px<136&&y>=40&&y<172)grey=150; // colored rectangle below
       5:if(px>=40&&px<72&&y>=40&&y<72)grey=220; // tiny patch
       6:if(px>=40&&px<136&&y>=40&&y<172)grey=((px/4+y/4)%2)?220:24;
       7:if(((px>=40&&px<88)||(px>=120&&px<168))&&y>=40&&y<72)grey=220;
      endcase
      if(mode==4&&grey==150)rgb[95-k*24-:24]=24'h20d020;
      else rgb[95-k*24-:24]={3{8'(grey)}};
     end
    end
    @(negedge clk);v=0;u=0;l=0;repeat(400)@(negedge clk);
   end
   checks=checks+1;
  end
  if(events!=56)$fatal(1,"negative events missing %0d",events);
  $display("DIGIT_AUTO_NEGATIVE_V93_PASS scenes=%0d events=%0d",checks,events);$finish;
 end
endmodule
