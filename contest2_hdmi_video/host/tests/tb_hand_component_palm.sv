`timescale 1ns/1ps
module tb_hand_component_palm;
reg clk=0;always #5 clk=~clk;
reg rst=0,clear=0,start=0,mode=1;
reg[7:0]bx,bw,ax;reg[6:0]by,bh,ay;
wire read;wire[11:0]ra;reg rv=0;reg[17:0]rd=0;
wire pv,pixel,pl,ready,cbusy,cdone,cfault,overflow;wire[13:0]area;wire[31:0]ccycles;
wire pbusy,pdone,pfault,has,dv;wire[7:0]cx,dx;wire[6:0]cy,dy;wire[10:0]radius,dq;wire[31:0]pcycles;
reg[15:0]lfsr=16'h4731;wire gate=lfsr[2:0]!=0;
ua_hand_component_mask component_core(clk,rst,clear,start,mode,bx,bw,ax,by,bh,ay,
 read,ra,rv,rd,pv,pixel,pl,ready&&gate,cbusy,cdone,cfault,overflow,area,ccycles,
 ,,,,16'd0,1'b0,8'd0,7'd0,,,);
ua_hand_palm_distance palm_core(clk,rst,clear,start,bw,bh,pv&&gate,pixel,pl,ready,
 pbusy,pdone,pfault,has,cx,cy,radius,dv,dx,dy,dq,pcycles,,,,,16'd0);
reg[17:0]mem[0:2429];reg[15:0]expected[0:14399];reg seen[0:14399];
reg[2047:0]input_path,expected_path;
integer x0,y0,w,h,anchor_x,anchor_y,expected_x,expected_y,expected_radius,expected_area;
integer case_error=0,abort_stage=0,n,i,outputs=0,distances=0,ticks=0,index;
integer pending=0,delay_count=0,pending_address=0,component_finished=0;
reg checking=0,held=0,held_pixel,held_last;
always @(posedge clk)begin
 lfsr<={lfsr[14:0],lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};rv<=0;
 if(read)begin
  if(pending)$fatal(1,"two outstanding mask reads");
  if(ra>=2430)$fatal(1,"mask address out of bounds %0d",ra);
  pending=1;pending_address=ra;delay_count=1+lfsr[1:0];
 end
 if(pending)begin
  if(delay_count==0)begin rv<=1;rd<=mem[pending_address];pending=0;end
  else delay_count=delay_count-1;
 end
 if(checking)begin
  if(held && (!pv || pixel!==held_pixel || pl!==held_last))$fatal(1,"stream changed while stalled");
  held=pv && !(ready&&gate);held_pixel=pixel;held_last=pl;
  if(pv && ready && gate)begin
   if(outputs>=n)$fatal(1,"too many component pixels");
   if(pixel!==expected[outputs][11] || pl!==(outputs==n-1))
    $fatal(1,"component pixel mismatch index=%0d pixel=%0d expected=%0d last=%0d",outputs,pixel,expected[outputs][11],pl);
   outputs=outputs+1;
  end
 end else held=0;
 #1;
 if(checking && cdone)begin
  component_finished=1;
  if(!case_error && (cfault||overflow||area!=expected_area))
   $fatal(1,"component completion fault=%0d overflow=%0d area=%0d expected=%0d",cfault,overflow,area,expected_area);
 end
 if(checking && dv)begin
  if(dx>=w || dy>=h)$fatal(1,"bad distance coordinates");index=dy*w+dx;
  if(seen[index] || dq!==expected[index][10:0])$fatal(1,"distance mismatch index=%0d actual=%0d expected=%0d",index,dq,expected[index][10:0]);
  seen[index]=1;distances=distances+1;
 end
end
task launch;
 begin @(negedge clk);start=1;@(negedge clk);start=0;end
endtask
task restart;
 begin
  checking=0;@(negedge clk);clear=1;@(negedge clk);clear=0;
  if(cbusy||pbusy||pv)$fatal(1,"clear did not abort chain");
  outputs=0;distances=0;component_finished=0;for(i=0;i<n;i=i+1)seen[i]=0;
  checking=1;launch();
 end
endtask
initial begin
 if(!$value$plusargs("INPUT=%s",input_path)||!$value$plusargs("EXPECTED=%s",expected_path)||
    !$value$plusargs("X=%d",x0)||!$value$plusargs("Y=%d",y0)||
    !$value$plusargs("W=%d",w)||!$value$plusargs("H=%d",h)||
    !$value$plusargs("AX=%d",anchor_x)||!$value$plusargs("AY=%d",anchor_y)||
    !$value$plusargs("CX=%d",expected_x)||!$value$plusargs("CY=%d",expected_y)||
    !$value$plusargs("R=%d",expected_radius)||!$value$plusargs("AREA=%d",expected_area))$fatal(1,"missing arguments");
 if($value$plusargs("MODE=%d",mode))begin end
 if($value$plusargs("ERROR=%d",case_error))begin end
 if($value$plusargs("ABORT=%d",abort_stage))begin end
 bx=x0;by=y0;bw=w;bh=h;ax=anchor_x;ay=anchor_y;n=w*h;
 $readmemh(input_path,mem);$readmemh(expected_path,expected,0,n-1);
 for(i=0;i<n;i=i+1)seen[i]=0;
 repeat(4)@(negedge clk);rst=1;checking=1;launch();
 if(abort_stage==1)begin repeat(100)@(negedge clk);restart();end
 if(abort_stage==2)begin wait(pv);repeat(12)@(negedge clk);restart();end
 if(case_error)begin
  while(!component_finished && ticks<1000000)begin @(negedge clk);ticks=ticks+1;end
  if(!component_finished||!cfault||cbusy||pv||outputs!=0)$fatal(1,"component fault contract");
  if((case_error==2)!==overflow)$fatal(1,"overflow flag mismatch");
 end else begin
  while(!pdone && ticks<1000000)begin @(negedge clk);ticks=ticks+1;end
  if(!pdone||pfault||!component_finished||outputs!=n||distances!=n||
     cx!=expected_x||cy!=expected_y||radius!=expected_radius||has!=(expected_radius>=80))
   $fatal(1,"component/palm result outputs=%0d distances=%0d center=(%0d,%0d) radius=%0d",outputs,distances,cx,cy,radius);
 end
 $display("HAND_COMPONENT_PALM_PASS area=%0d pixels=%0d component_cycles=%0d total_cycles=%0d error=%0d abort=%0d",area,n,ccycles,pcycles,case_error,abort_stage);
 $finish;
end
endmodule
