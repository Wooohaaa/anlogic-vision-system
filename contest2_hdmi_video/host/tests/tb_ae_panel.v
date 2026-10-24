`timescale 1ns/1ps
module tb_ae_panel;
 reg clk=0,src=0,rst=0;
 always #5 clk=~clk;
 always #21 src=~src;
 reg [15:0] ae=1990,ag=16;
 wire [5:0] sel;wire [7:0] led;
 integer g,e,expected,seen=0,d;
 reg [7:0] want;
 reg [3:0] v;
 reg last_req=0;
 integer packet_code,packet_gain;
 ua_ae_legacy_panel_embedded #(.SCAN_CYCLES(8)) dut(
  .I_clk(clk),.I_source_clk(src),.I_rst_n(rst),.I_ae(ae),.I_ag(ag),
  .O_seg_sel(sel),.O_seg_led(led));
 function integer unbcd;
 input [19:0] x;
 begin unbcd=x[19:16]*10000+x[15:12]*1000+x[11:8]*100+x[7:4]*10+x[3:0];end
 endfunction
 always @(posedge clk) begin
  #1;
  if(rst && dut.req!=last_req) begin
   packet_code=dut.packet[15:0];
   if(packet_code<16) packet_code=16;
   if(packet_code>143) packet_code=143;
   packet_gain=(((32+((packet_code-16)%32))*(1<<((packet_code-16)/32))) +16)/32;
   if(unbcd({4'd0,dut.exposure_bcd})!=dut.packet[31:16] ||
      unbcd({8'd0,dut.gain_bcd})!=packet_gain) $fatal(1,"torn converted pair");
  end
  last_req=dut.req;
  if(rst && sel!=63) begin
   if(((~sel & 6'h3f)&((~sel & 6'h3f)-1))!=0) $fatal(1,"multi select");
   for(d=0;d<6;d=d+1) if(!sel[d]) begin
    seen=seen | (1<<d);
    case(d)
     0:v=dut.scan_exposure[15:12];1:v=dut.scan_exposure[11:8];
     2:v=dut.scan_exposure[7:4];3:v=dut.scan_exposure[3:0];
     4:v=dut.scan_gain[7:4];5:v=dut.scan_gain[3:0];
    endcase
    want=dut.decimal7seg(v);
    if(d==3) want[7]=0;
    if(led!==want) $fatal(1,"digit position=%d actual=%h expected=%h",d,led,want);
   end
  end
 end
 initial begin
  repeat(4) @(negedge clk);rst=1;
  for(g=16;g<=143;g=g+1) begin
   @(negedge src);ag=g;ae=(g-16)*15+2;
   repeat(220) @(negedge clk);
   expected=(((32+((g-16)%32))*(1<<((g-16)/32))) +16)/32;
   if(unbcd({8'd0,dut.gain_bcd})!=expected || unbcd({4'd0,dut.exposure_bcd})!=ae)
    $fatal(1,"conversion ae=%d ag=%d bcd=%h %h",ae,ag,dut.exposure_bcd,dut.gain_bcd);
  end
  for(e=0;e<=1990;e=e+1) begin
   @(negedge src);ae=e;
   repeat(100) @(negedge clk);
   if(unbcd({4'd0,dut.exposure_bcd})!=e) $fatal(1,"exposure conversion %d",e);
  end
  @(negedge src);ae=1990;ag=143;repeat(250) @(negedge clk);
  if(dut.exposure_bcd!==16'h1990 || dut.gain_bcd!==12'h016 || seen!=63)
   $fatal(1,"limits/fixed_scan");
  @(negedge src);ag=0;repeat(250) @(negedge clk);
  if(dut.gain_bcd!==12'h001) $fatal(1,"gain lower clamp");
  @(negedge src);ag=65535;repeat(250) @(negedge clk);
  if(dut.gain_bcd!==12'h016) $fatal(1,"gain upper clamp");
  // Whole source pairs change faster than serial conversion, on source edges.
  for(e=0;e<256;e=e+1) begin
   @(negedge src);ae=e*7;ag=16+(e%128);
  end
  repeat(250) @(negedge clk);
  $display("AE_PANEL_PASS all_exposures_0_1990 all_gain_codes_16_143 coherent_snapshot fixed_six_digits separator no_rotation");$finish;
 end
endmodule
