`timescale 1ns/1ps
module tb_stepper_pins_v77;
  wire [1:0] rst_n;
  design_top_user dut(.I_sys_clk(1'b0), .I_mcu_uart_rx(1'b1),
      .I_button(4'hf), .I_detect_sw(4'hf), .O_motor_reset_n(rst_n));
  initial begin
    force dut.O_motor_awake = 2'b00; #1;
    if (rst_n !== 2'b00) $fatal(1,"Disabled RST pads not low");
    force dut.O_motor_awake = 2'b01; #1;
    if (rst_n !== 2'b01) $fatal(1,"Axis 0 RST mapping incorrect");
    force dut.O_motor_awake = 2'b10; #1;
    if (rst_n !== 2'b10) $fatal(1,"Axis 1 RST mapping incorrect");
    force dut.O_motor_awake = 2'b11; #1;
    if (rst_n !== 2'b11) $fatal(1,"Enabled RST pads not high");
    force dut.O_motor_awake = 2'b00; #1;
    if (rst_n !== 2'b00) $fatal(1,"RST pads failed to close");
    $display("STEPPER_DEDICATED_PADS_V77_PASS"); $finish;
  end
endmodule
