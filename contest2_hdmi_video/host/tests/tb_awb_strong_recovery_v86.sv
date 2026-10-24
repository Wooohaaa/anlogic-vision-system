`timescale 1ns/1ps
// No forced gains: exercise estimator, frame commits, runtime control and RGB.
module tb_awb_strong_recovery_v86;
 parameter RECOVERY=0;
 reg clk=0,rst=0,v=0,u=0,l=0,en=1;
 reg[23:0]pixel=24'h3c6428;
 always #5 clk=~clk;
 wire ov;wire[107:0]od;wire[10:0]status;
 ua_awb_frame #(.IMG_WIDTH(256),.IMG_HEIGHT(4),.OUTPUT_CHANNEL_BITS(9),.RUNTIME_CONTROL(1),.GREEN_CAST_RECOVERY(RECOVERY))dut(
 .I_clk(clk),.I_rst_n(rst),.I_tdata({4{pixel}}),.I_tvalid(v),.I_tuser(u),.I_tlast(l),
 .I_enable(en),.O_tready(1'b1),.O_tvalid(ov),.O_tdata(od),.O_status(status));
 integer f,y,x,k,checked=0,phase=0,channel,gain,product,expected;reg[19:0]held_r,held_b;
 task frame;
 begin
 @(negedge clk);u=1;v=0;l=0;
 @(negedge clk);u=0;
 for(y=0;y<4;y=y+1)begin
 for(x=0;x<64;x=x+1)begin @(negedge clk);v=1;l=x==63;end
 @(negedge clk);v=0;l=0;repeat(100)@(negedge clk);
 end
 repeat(200)@(negedge clk);
 end endtask
 always @(negedge clk)if(rst && ov && phase!=0)begin
 for(k=0;k<4;k=k+1)begin
 if(phase==1 && (od[k*27+18+:9]<98 || od[k*27+18+:9]>102 ||
 od[k*27+9+:9]!=100 || od[k*27+:9]<98 || od[k*27+:9]>102))
 $fatal(1,"corrected gray mismatch phase=%0d data=%h",phase,od);
 if(phase==2 && od[k*27+:27]!=={9'd60,9'd100,9'd40})$fatal(1,"OFF is not unity");
 end
 checked=checked+1;
 end
 initial begin
 repeat(4)@(negedge clk);rst=1;
 for(f=0;f<96;f=f+1)frame;
 $display("STRONG_CAST_ESTIMATOR samples=%0d gains=%0d,%0d enabled=%0d",dut.sample_count,dut.gain_r,dut.gain_b,status[10]);
 if(dut.gain_r<108700 || dut.gain_r>109700 || dut.gain_b<163300 || dut.gain_b>164300)
 $fatal(1,"strong cast stuck/unbalanced; target=1.6667,2.5");
 phase=1;frame;phase=0;
 en=0;frame;phase=2;frame;phase=0;
 if(status!=={1'b0,5'd10,5'd10})$fatal(1,"OFF status");
 en=1;frame;phase=1;frame;phase=0;
 if(!status[10] || checked!=3*256)$fatal(1,"ON status/output coverage %0d",checked);
 held_r=dut.gain_r;held_b=dut.gain_b;
 pixel=24'h056405;
 for(f=0;f<24;f=f+1)frame;
 if(dut.gain_r!==held_r || dut.gain_b!==held_b)$fatal(1,"saturated green must not adapt");
 pixel=24'h181c18;
 for(f=0;f<24;f=f+1)frame;
 if(dut.gain_r!==held_r || dut.gain_b!==held_b)$fatal(1,"dark noise must not adapt");
 // Independently check all input codes across 0.5x..3x including the
 // newly reachable >511 output domain, plus exact clamp endpoints.
 for(gain=32768;gain<=196608;gain=gain+1024)begin
 for(channel=0;channel<256;channel=channel+1)begin
 product=(channel*gain)>>16;expected=product>511?511:product;
 if(dut.F_output_channel(8'(channel),20'(gain))!==9'(expected))$fatal(1,"wide saturation wrap");
 end end
 if(dut.F_limit_gain(48'd196609)!==20'd196608 || dut.F_limit_gain(48'd0)!==20'd32768)
 $fatal(1,"recovery clamp bounds");
 $display("AWB_STRONG_RECOVERY_V86_PASS actual_estimator ON_OFF_ON all4lanes reject_green_dark");$finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
