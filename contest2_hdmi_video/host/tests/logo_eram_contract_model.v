// Simulation-only SP/NOREG read contract used by the maintained Logo.
// This is NOT the encrypted vendor model or post-route hardware signoff.
module PH1P_LOGIC_ERAM #(
 parameter DATA_WIDTH_A=9,DATA_WIDTH_B=9,ADDR_WIDTH_A=14,ADDR_WIDTH_B=14,
 parameter DATA_DEPTH_A=16384,DATA_DEPTH_B=16384,
 parameter MODE="SP",REGMODE_A="NOREG",REGMODE_B="NOREG",CLKMODE="ASYNC",
 parameter IMPLEMENT="20K(FAST)",INIT_FILE="NONE",FILL_ALL="NONE"
)(input clka,cea,ocea,wea,rsta,bea,input [DATA_WIDTH_A-1:0] dia,
 input [ADDR_WIDTH_A-1:0] addra,output reg [DATA_WIDTH_A-1:0] doa,
 input clkb,ceb,oceb,web,rstb,beb,input [DATA_WIDTH_B-1:0] dib,
 input [ADDR_WIDTH_B-1:0] addrb,output [DATA_WIDTH_B-1:0] dob,
 output ecc_sbiterr,ecc_dbiterr,input ecc_sbiterrinj,ecc_dbiterrinj);
 reg [DATA_WIDTH_A-1:0] mem[0:DATA_DEPTH_A-1];
 integer file_id,status,address,value,count;reg [4095:0] line;
 initial begin
  if(MODE!="SP" || REGMODE_A!="NOREG")$fatal(1,"Unsupported Logo RAM contract");
  file_id=$fopen(INIT_FILE,"r");count=0;
  if(!file_id)$fatal(1,"Missing Logo MIF: %s",INIT_FILE);
  while(!$feof(file_id))begin
   status=$fgets(line,file_id);
   if($sscanf(line,"%d : %h;",address,value)==2)begin
    if(address<0 || address>=DATA_DEPTH_A)$fatal(1,"Logo MIF address out of bounds");
    mem[address]=value;count=count+1;
   end
  end
  $fclose(file_id);
  if(INIT_FILE=="rtl/user/font_compact.dath")begin
   $readmemh(INIT_FILE,mem);count=DATA_DEPTH_A;
  end
  if(count!=DATA_DEPTH_A)$fatal(1,"Incomplete Logo MIF words=%0d",count);
 end
 always @(posedge clka)if(cea)begin
  if(wea)$fatal(1,"Unexpected Logo ROM write");
  doa<=mem[addra];
 end
 assign dob=0;assign ecc_sbiterr=0;assign ecc_dbiterr=0;
endmodule
