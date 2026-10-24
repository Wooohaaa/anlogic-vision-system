`timescale 1ns/1ps
module tb_logo_crop_equivalence;
  reg clk=0;always #5 clk=~clk;
  reg [14:0] address=0;
  wire [24:0] a,b;wire pa,pb;
  integer i;
  anlogic_logo_rom baseline(clk,address,a,pa);
  logo_candidate candidate(clk,address,b,pb);
  initial begin
    repeat(3) @(negedge clk);
    for(i=0;i<32772;i=i+1) begin
      address=i[14:0];
      @(posedge clk);#1;
      if(a!==b || pa!==pb) $fatal(1,"LOGO_MISMATCH address=%0d baseline=%h candidate=%h present=%b%b",i,a,b,pa,pb);
      @(negedge clk);
    end
    $display("LOGO_EXHAUSTIVE_PASS addresses=32768 pixel_and_presence_latency_unchanged");
    $finish;
  end
endmodule
