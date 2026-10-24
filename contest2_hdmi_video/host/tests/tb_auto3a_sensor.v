`timescale 1ns/1ps
// Actual SC500 init/AE tables and configuration FSM; only the electrical
// I2C master is replaced with a delayed accepting model. Not an ACK test.
module tb_auto3a_sensor;
reg clk=0;always #5 clk=~clk;
reg rst=0,ft=0;reg [7:0] luma=0;
wire req,done,ae_done,scl;tri sda;
wire [15:0] ae,ag;
integer pairs=0,regs=0,i;
reg [15:0] pair_ae,pair_ag;
reg [31:0] expected;
reg [15:0] sensor_gain;
reg [6:0] gain_offset;
reg [7:0] gain_low;
ua_auto_exposure #(.AUTO_START_WRITE(1),.AUTO_FAST(1),.AG_DEFAULT(16)) ctrl
 (.I_clk(clk),.I_rst_n(rst),.I_luma_mean(luma),.I_frame_toggle(ft),
 .I_cam_cfg_done(done),.I_ae_cfg_done(ae_done),.I_auto_enable(1'b1),.I_manual_inc(1'b0),.I_manual_dec(1'b0),
 .O_ae_req(req),.O_ae(ae),.O_ag(ag),.O_luma_dbg(),.O_manual_level());
uicfgcs500_720p #(.CLK_DIV(1)) cfg(clk,rst,req,ae,ag,scl,sda,done,ae_done);
always @(posedge clk) begin
 if(req) begin pair_ae=ae;pair_ag=ag;pairs=pairs+1;end
 if(done && cfg.iic_req && !cfg.iic_busy) begin
  gain_offset=pair_ag-16;gain_low=8'h20+gain_offset[4:0];
  // Use table's band mapping including carry in offset code.
  case(gain_offset[6:5])
   0:sensor_gain={8'h03,gain_low};
   1:sensor_gain={8'h07,gain_low};
   2:sensor_gain={8'h0f,gain_low};
   3:sensor_gain={8'h1f,gain_low};
  endcase
  case(cfg.reg_index)
   0:expected={4'd0,pair_ae[15:12],8'h00,8'h3e,8'h6c};
   1:expected={pair_ae[11:4],8'h01,8'h3e,8'h6c};
   2:expected={pair_ae[3:0],4'd0,8'h02,8'h3e,8'h6c};
   3:expected={sensor_gain[15:8],8'h08,8'h3e,8'h6c};
   4:expected={sensor_gain[7:0],8'h09,8'h3e,8'h6c};
  endcase
  if(cfg.wr_data!==expected) $fatal(1,"sensor byte mismatch reg=%0d actual=%h expected=%h",cfg.reg_index,cfg.wr_data,expected);
  regs=regs+1;
 end
 if(done && !ae_done && pairs>0 && (ae!==pair_ae || ag!==pair_ag)) $fatal(1,"pair changed during actual configuration FSM");
end
initial begin
 repeat(3) @(negedge clk);rst=1;
 wait(done);repeat(250) @(negedge clk);
 if(pairs!=1 || regs!=5) $fatal(1,"startup register programming incomplete");
 for(i=0;i<90;i=i+1) begin @(negedge clk);ft=~ft;repeat(150) @(negedge clk);end
 repeat(300) @(negedge clk);
 if(pairs<3 || regs!=pairs*5) $fatal(1,"incomplete exposure register sets");
 $display("AUTO3A_SENSOR_FSM_PASS actual_init_AE_gain_tables coherent_pairs=%0d register_writes=%0d mocked_I2C",pairs,regs);$finish;
end
initial begin #10000000;$fatal(1,"sensor FSM timeout");end
endmodule

module uii2c_ce #(parameter WMEN_LEN=4,RMEN_LEN=1,CLK_DIV=1)(
 input I_clk,I_rstn,output O_iic_scl,inout IO_iic_sda,
 input [WMEN_LEN*8-1:0] I_wr_data,input [7:0] I_wr_cnt,
 output [RMEN_LEN*8-1:0] O_rd_data,input [7:0] I_rd_cnt,
 input I_iic_mode,I_iic_req,output reg O_iic_busy,output O_iic_bus_error,
 output IO_iic_sda_dg);
integer count;
assign O_iic_scl=1;assign IO_iic_sda=1'bz;assign O_rd_data=0;
assign O_iic_bus_error=0;assign IO_iic_sda_dg=1;
always @(posedge I_clk) begin
 if(!I_rstn) begin count<=0;O_iic_busy<=0;end
 else if(!O_iic_busy && I_iic_req) begin O_iic_busy<=1;count<=12;end
 else if(O_iic_busy) begin count<=count-1;if(count==1) O_iic_busy<=0;end
end
endmodule
