`timescale 1ns/1ps
module tb_hand_frame_classifier;
reg clk=0;always #5 clk=~clk;
reg rst=0,clear=0,start=0,cv=0,finish=0,mode=0,rv=0;reg[17:0]rd;
reg[7:0]x,w,ax;reg[6:0]y,h,ay;reg[13:0]area,bright;reg[23:0]red_sum;
wire ready,cr,read,busy,done,fault,box_valid,backlit;wire[11:0]ra;
wire[1:0]id,raw;wire[2:0]tips;wire[7:0]bx,bw;wire[6:0]by,bh;wire[10:0]radius;wire[9:0]mean;
ua_hand_frame_classifier dut(clk,rst,clear,start,cv,finish,mode,x,w,ax,y,h,ay,area,red_sum,bright,
 ready,cr,read,ra,rv,rd,busy,done,fault,id,raw,box_valid,tips,bx,bw,by,bh,radius,mean,backlit,
 1'b0,1'b0,14'd0,16'd0,,,);
reg[31:0]packed_mask[0:2429];reg[17:0]mask[0:2429];reg[2047:0]vp,mp;
reg[15:0]rng=16'h2379;
integer vector_file,mask_file,rc,bytes,n,clear_frame,b,ei,er,eb,et,ex,ey,ew,eh,err,em,i;
integer c_mode,cx,cy,cw,ch,cax,cay,ca,cs,jobs=0,pending=0,address=0,delay_cycles=0,frame_cycles=0,total_cycles=0;
reg checking=0;reg[63:0]previous_result;
wire[63:0]result_payload={id,raw,box_valid,tips,bx,bw,by,bh,radius,mean,5'd0};
always @(posedge clk)begin
 rng<={rng[14:0],rng[15]^rng[13]^rng[12]^rng[10]};rv<=0;total_cycles=total_cycles+1;
 if(busy)frame_cycles=frame_cycles+1;
 if(frame_cycles>2000000)$fatal(1,"frame %0d timeout state=%0d shape=%0d",jobs,dut.state,dut.shape.state);
 if(read)begin
  if(pending || ra>=2430)$fatal(1,"read overlap/bounds");
  pending=1;address=ra;delay_cycles=1+rng[1:0];
 end
 if(pending)begin
  if(!delay_cycles)begin pending=0;rv<=1;rd<=mask[address];end else delay_cycles=delay_cycles-1;
 end
end
initial begin
 if(!$value$plusargs("VECTORS=%s",vp)||!$value$plusargs("MASKS=%s",mp))$fatal(1,"files");
 vector_file=$fopen(vp,"r");mask_file=$fopen(mp,"rb");if(!vector_file || !mask_file)$fatal(1,"open");
 repeat(5)@(negedge clk);rst=1;
 while(!$feof(vector_file))begin
  rc=$fscanf(vector_file,"%d %d %d %d %d %d %d %d %d %d %d %d %d\n",clear_frame,n,b,ei,er,eb,et,ex,ey,ew,eh,err,em);
  if(rc!=13)$fatal(1,"header");
  while(!ready)@(negedge clk);
  bytes=$fread(packed_mask,mask_file);if(bytes!=9720)$fatal(1,"mask length %0d",bytes);
  for(i=0;i<2430;i=i+1)mask[i]=packed_mask[i][17:0];
  if(clear_frame)begin clear=1;@(negedge clk);clear=0;end
  while(!ready)@(negedge clk);frame_cycles=0;previous_result=result_payload;
  start=1;@(negedge clk);start=0;
  for(i=0;i<n;i=i+1)begin
   rc=$fscanf(vector_file,"%d %d %d %d %d %d %d %d %d\n",c_mode,cx,cy,cw,ch,cax,cay,ca,cs);if(rc!=9)$fatal(1,"candidate");
   while(!cr)begin
    if(result_payload!==previous_result)$fatal(1,"partial result changed before commit");
    @(negedge clk);
   end
   mode=c_mode;x=cx;y=cy;w=cw;h=ch;ax=cax;ay=cay;area=ca;red_sum=cs;cv=1;@(negedge clk);cv=0;
   x=0;y=0;w=0;h=0;ax=0;ay=0;area=0;red_sum=0;
  end
  while(!cr)@(negedge clk);bright=b;finish=1;@(negedge clk);finish=0;
  while(!done)@(negedge clk);
  if(fault || id!=ei || raw!=er || box_valid!==eb[0] || tips!=et || bx!=ex || by!=ey || bw!=ew || bh!=eh || radius!=err || mean!=em)
   $fatal(1,"frame %0d fault=%0d id=%0d/%0d raw=%0d/%0d box=%0d/%0d tips=%0d/%0d bbox=%0d,%0d,%0d,%0d/%0d,%0d,%0d,%0d radius=%0d/%0d mean=%0d/%0d",jobs,
    fault,id,ei,raw,er,box_valid,eb,tips,et,bx,by,bw,bh,ex,ey,ew,eh,radius,err,mean,em);
  $display("FRAME %0d %0d %0d %0d",jobs,id,raw,frame_cycles);jobs=jobs+1;
  @(negedge clk);if(done)$fatal(1,"done not pulse");
 end
 $display("HAND_FRAME_CLASSIFIER_PASS frames=%0d cycles=%0d",jobs,total_cycles);$finish;
end
endmodule
