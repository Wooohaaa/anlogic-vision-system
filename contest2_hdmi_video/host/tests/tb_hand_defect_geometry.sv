`timescale 1ns/1ps
module tb_hand_defect_geometry;
reg clk=0;always #5 clk=~clk;
reg rst=0,clear=0,start=0,mode=0,rv=0;reg[17:0]rd;
reg[7:0]xmin,width,anchor_x;reg[6:0]ymin,height,anchor_y;
wire ready,read,busy,done,fault,has;wire[11:0]ra;
wire unused_hv,unused_hl,unused_client_ready;wire[7:0]unused_hx;wire[6:0]unused_hy;wire[15:0]unused_client_data;
wire[7:0]cx,ax,bx,fx;wire[6:0]cy,ay,by,fy;wire[10:0]radius;wire[13:0]area;
wire signed[9:0]wx,wy;wire ev,qual,has_far;wire[19:0]cross_value;wire[9:0]length;wire[31:0]cycles;
reg probe=0;reg[7:0]px;reg[6:0]py;wire pr,pv,pp;
reg[15:0]rng=16'hb34d;wire er=rng[3:0]!=0;
ua_hand_defect_geometry dut(
 clk,rst,clear,start,mode,xmin,width,anchor_x,ymin,height,anchor_y,ready,read,ra,rv,rd,
 busy,done,fault,has,cx,cy,radius,area,wx,wy,ev,er,ax,bx,ay,by,qual,has_far,fx,fy,cross_value,length,cycles,
 probe,px,py,pr,pv,pp,unused_hv,1'b1,unused_hx,unused_hy,unused_hl,
 1'b0,1'b0,14'd0,16'd0,unused_client_ready,unused_client_data);
reg[17:0]source[0:2429];reg mask[0:14399];reg[76:0]expected[0:319];
reg[2047:0]mask_path,expected_path,bitmap_path;
integer f,rc,e,i,j,ea,eb,ec,ed,eq,eh,ex,ey,em,el;
integer x,y,w,h,tx,ty,mode_arg,expected_cx,expected_cy,expected_r,expected_area,expected_wx,expected_wy;
integer pending=0,pending_address=0,delay_cycles=0,ticks=0,observed=0,checking=0,abort_stage=0;
reg held=0;reg[76:0]payload;
wire[76:0]result_payload={ax,bx,ay,by,qual,has_far,fx,fy,cross_value,length};
always @(posedge clk)begin
 rng<={rng[14:0],rng[15]^rng[13]^rng[12]^rng[10]};ticks=ticks+1;rv<=0;
 if(ticks>5000000)$fatal(1,"timeout");
 if(read)begin
  if(pending || ra>=2430)$fatal(1,"read overlap/bounds");
  pending=1;pending_address=ra;delay_cycles=1+rng[1:0];
 end
 if(pending)begin
  if(!delay_cycles)begin pending=0;rv<=1;rd<=source[pending_address];end
  else delay_cycles=delay_cycles-1;
 end
 if(dut.geometry.scratch_read && dut.geometry.scratch_write)$fatal(1,"scratch collision");
 if((dut.memory_read || dut.memory_write) && dut.memory_ready && dut.memory_address>=14400)$fatal(1,"scratch bounds");
 if(checking)begin
  if(held && (!ev || result_payload!==payload))$fatal(1,"unstable output");
  held=ev && !er;payload=result_payload;
  if(ev && er)begin
   if(observed>=e || result_payload!==expected[observed])
    $fatal(1,"edge %0d/%0d got %h expected %h",observed,e,result_payload,expected[observed]);
   observed=observed+1;
  end
 end else held=0;
end
task launch;
begin while(!ready)@(negedge clk);start=1;@(negedge clk);start=0;end endtask
initial begin
 if(!$value$plusargs("MASK=%s",mask_path)||!$value$plusargs("EXPECTED=%s",expected_path)||!$value$plusargs("BITMAP=%s",bitmap_path))$fatal(1,"files");
 $readmemh(mask_path,source,0,2429);
 f=$fopen(expected_path,"r");if(!f)$fatal(1,"open");
 rc=$fscanf(f,"%d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",x,y,w,h,tx,ty,mode_arg,expected_cx,expected_cy,expected_r,expected_area,expected_wx,expected_wy,e);
 if(rc!=14)$fatal(1,"header");
 xmin=x;ymin=y;width=w;height=h;anchor_x=tx;anchor_y=ty;mode=mode_arg;
 $readmemh(bitmap_path,mask,0,w*h-1);
 for(i=0;i<e;i=i+1)begin
  rc=$fscanf(f,"%d %d %d %d %d %d %d %d %d %d\n",ea,eb,ec,ed,eq,eh,ex,ey,em,el);
  if(rc!=10)$fatal(1,"edge header");
  expected[i]={8'(ea),8'(ec),7'(eb),7'(ed),1'(eq),1'(eh),8'(ex),7'(ey),20'(em),10'(el)};
 end
 if($value$plusargs("ABORT=%d",abort_stage))begin end
 repeat(5)@(negedge clk);rst=1;
 if(abort_stage)begin
  launch();
  if(abort_stage==1)while(!pending)@(negedge clk);
  else if(abort_stage==2)while(dut.state!=4 || !pending)@(negedge clk);
  else while(!ev)@(negedge clk);
  clear=1;@(negedge clk);clear=0;
  if(busy || done || ev)$fatal(1,"abort incomplete");
  while(!ready)@(negedge clk);
 end
 checking=1;launch();while(!done)@(negedge clk);
 if(fault || observed!=e || cx!=expected_cx || cy!=expected_cy || radius!=expected_r ||
    area!=expected_area || wx!=expected_wx || wy!=expected_wy || has!==(expected_r>=80))
  $fatal(1,"geometry f=%0d e=%0d/%0d palm=%0d,%0d,%0d/%0d,%0d,%0d wrist=%0d,%0d/%0d,%0d",fault,observed,e,cx,cy,radius,expected_cx,expected_cy,expected_r,wx,wy,expected_wx,expected_wy);
 checking=0;@(negedge clk);
 // Probe every retained selected-component pixel after scratch reuse.
 for(j=0;j<h;j=j+1)for(i=0;i<w;i=i+1)begin
  while(!pr)@(negedge clk);px=i;py=j;probe=1;@(negedge clk);probe=0;
  if(!pv || pp!==mask[j*w+i])$fatal(1,"retained pixel %0d,%0d",i,j);
 end
 $display("HAND_DEFECT_GEOMETRY_PASS cycles=%0d edges=%0d pixels=%0d",cycles,observed,w*h);$finish;
end
endmodule
