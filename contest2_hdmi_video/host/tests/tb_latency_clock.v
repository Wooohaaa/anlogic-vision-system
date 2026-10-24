`timescale 1ns/1ps
module tb_latency_clock;
  reg clk=0,rst=0;
  always #6.666667 clk=~clk;
  wire valid;wire [15:0] delay_ms;
  ua_frame_latency dut(.I_rst_n(rst),.I_camera_clk(clk),.I_raw_start(1'b0),
    .I_ddr_clk(clk),.I_write_start(1'b0),.I_write_slot(2'd0),.I_write_word(1'b0),
    .I_read_start(1'b0),.I_read_slot(2'd0),.I_pixel_clk(clk),.I_display_start(1'b0),
    .O_valid(valid),.O_delay_ms(delay_ms));
  initial begin
    #1;rst=1;#1;rst=0;
    @(negedge clk);rst=1;
    repeat(74999) @(posedge clk);#1;
    if(dut.ms_count!==0) $fatal(1,"1ms advanced early (old 52MHz divisor?)");
    @(posedge clk);#1;
    if(dut.ms_count!==1) $fatal(1,"75000 cycles must be 1ms");
    repeat(75000) @(posedge clk);#1;
    if(dut.ms_count!==2) $fatal(1,"150000 cycles must be 2ms");
    @(negedge clk);rst=0;#1;
    if(dut.ms_count!==0 || valid) $fatal(1,"reset failed");
    $display("LATENCY_75MHZ_PASS 75000_cycles_per_ms reset");$finish;
  end
endmodule
