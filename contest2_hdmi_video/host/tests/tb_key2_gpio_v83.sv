`timescale 1ns/1ps
// Existing vendor-wrapper contract model; no CPU instruction execution.
module tb_key2_gpio_v83;
 tb_aruco_mcu_bypass fixture();
 initial begin
  force fixture.dut.key2_n=1'b1;
  repeat(8)@(negedge fixture.clk);
  if(fixture.dut.mcu.gpio4_in!==1)$fatal(1,"released KEY2 not at GPIO4");
  force fixture.dut.key2_n=1'b0;
  repeat(8)@(negedge fixture.clk);
  if(fixture.dut.mcu.gpio4_in!==0)$fatal(1,"pressed KEY2 not at GPIO4");
  if(fixture.dut.mcu.gpio3_in!==1 || fixture.dut.mcu.gpio5_in!==1)$fatal(1,"other GPIO key changed");
  force fixture.dut.key2_n=1'b1;
  repeat(8)@(negedge fixture.clk);
  if(fixture.dut.mcu.gpio4_in!==1)$fatal(1,"release not propagated");
  $display("KEY2_V83_GPIO_PATH_PASS");
 end
endmodule
