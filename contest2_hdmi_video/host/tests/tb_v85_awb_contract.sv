`timescale 1ns/1ps
// Production AWB, not a fixed-delay placeholder. Exposes its implicit
// horizontal-blanking contract which the v84 standalone row tests missed.
module tb_v85_awb_contract;
 localparam W=1280,H=8,G=W/4;
 reg clk=0,rst=0,v=0,u=0,l=0;reg[95:0]rgb=0;
 always #5 clk=~clk;
 wire rv,ru,rl;wire[95:0]rd;
 ua_top_row_repair_v85 #(.IMG_WIDTH(W),.IMG_HEIGHT(H)) repair(clk,rst,rgb,v,u,l,rd,rv,ru,rl);
 wire av,al,bv,bl;
 ua_awb_frame #(.IMG_WIDTH(W),.IMG_HEIGHT(H)) baseline(
 .I_clk(clk),.I_rst_n(rst),.I_tvalid(v),.I_tuser(u),.I_tlast(l),.I_tdata(rgb),.I_enable(1'b0),.I_tready(),
 .O_tvalid(av),.O_tlast(al),.O_tuser(),.O_tdata(),.O_tready(1'b1),.O_status());
 ua_awb_frame #(.IMG_WIDTH(W),.IMG_HEIGHT(H)) candidate(
 .I_clk(clk),.I_rst_n(rst),.I_tvalid(rv),.I_tuser(ru),.I_tlast(rl),.I_tdata(rd),.I_enable(1'b0),.I_tready(),
 .O_tvalid(bv),.O_tlast(bl),.O_tuser(),.O_tdata(),.O_tready(1'b1),.O_status());
 integer a_count=0,b_count=0,a_lines=0,b_lines=0,a_width=0,b_width=0,a_bad=0,b_bad=0;
 always @(negedge clk)if(rst)begin
  if(av)begin a_count=a_count+1;a_width=a_width+1;end
  if(bv)begin b_count=b_count+1;b_width=b_width+1;end
  if(av && al)begin a_lines=a_lines+1;if(a_width!=G)a_bad=a_bad+1;a_width=0;end
  if(bv && bl)begin b_lines=b_lines+1;if(b_width!=G)b_bad=b_bad+1;b_width=0;end
 end
 task idle(input integer n);integer k;begin for(k=0;k<n;k=k+1)begin @(posedge clk);#1;v=0;u=0;l=0;end end endtask
 integer f,x,y;
 initial begin
  repeat(4)@(posedge clk);#1;rst=1;
  for(f=0;f<2;f=f+1)begin
   for(y=0;y<H;y=y+1)begin
    for(x=0;x<G;x=x+1)begin
     @(posedge clk);#1;v=1;u=(y==0 && x==0);l=x==G-1;rgb={12{8'd100}};
    end
    idle(100);
   end
   idle(2*G+550);
  end
  idle(400);
  $display("BASELINE groups=%d lines=%d bad_width=%d",a_count,a_lines,a_bad);
  $display("V84R1 groups=%d lines=%d bad_width=%d",b_count,b_lines,b_bad);
  if(a_count!=2*G*H || a_lines!=2*H || a_bad)$fatal(1,"invalid baseline");
  if(b_count!=a_count || b_lines!=a_lines || b_bad!=0)$fatal(1,"AWB integration regression remains");
  $display("V85_PRODUCTION_AWB_LINE_CONTRACT_PASS");$finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
