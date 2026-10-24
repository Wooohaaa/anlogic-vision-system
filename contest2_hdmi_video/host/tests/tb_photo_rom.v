`timescale 1ns/1ps
module tb_photo_rom;
  parameter INPUT_BITS=8;
  reg clk=0;
  always #8 clk=~clk;
  wire v,u,l;wire [95:0] d;
  reg [12*INPUT_BITS-1:0] stimulus;
  reg [7:0] ref_lut[0:(1<<INPUT_BITS)-1];
  integer c;
  ua_photo_finish_96 #(.IMG_WIDTH(16),.INPUT_BITS(INPUT_BITS)) dut(clk,1'b0,1'b0,1'b0,1'b0,{12*INPUT_BITS{1'b0}},2'd0,v,u,l,d);
  initial begin
    if(INPUT_BITS==9) $readmemh("tmp/photo_tests/gamma_wide.hex",ref_lut);
    else $readmemh("tmp/photo_tests/gamma.hex",ref_lut);
    force dut.v_valid=1'b1;
    force dut.v_data=stimulus;
    for(c=0;c<(1<<INPUT_BITS);c=c+1) begin
      @(negedge clk);stimulus={12{c[INPUT_BITS-1:0]}};
      @(posedge clk);#1;
      if(dut.encoded_data!=={12{ref_lut[c]}}) $fatal(1,"ROM code %0d mismatch %h",c,dut.encoded_data);
    end
    release dut.v_valid;release dut.v_data;
    $display("PHOTO_ROM_PASS codes=%0d input_bits=%0d channels=12 registered_read exact_table",1<<INPUT_BITS,INPUT_BITS);
    $finish;
  end
endmodule
