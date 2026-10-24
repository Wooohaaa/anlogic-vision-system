`timescale 1ns/1ps
module tb_awb_arithmetic_equivalence;
    reg clk=0,rst=0;always #8 clk=~clk;
    wire ir,ol,ou,ov;wire [95:0] od;
    ua_awb_frame dut(.I_clk(clk),.I_rst_n(rst),.I_tlast(1'b0),.I_tuser(1'b0),.I_tdata(96'd0),.I_tvalid(1'b0),.I_tready(ir),.O_tlast(ol),.O_tuser(ou),.O_tdata(od),.O_tvalid(ov),.O_tready(1'b1));
    reg [31:0] rng=32'h13579bdf;
    reg [47:0] quotient;
    reg [19:0] c,t,expected,xr,xb,cr,cb;
    reg signed [20:0] delta,next_gain;
    reg close_ref;
    reg signed [16:0] vote,threshold;
    reg [15:0] count;
    reg [1:0] direction_ref;
    integer i;
    initial begin
        // Check the exact former wide arithmetic, including inclusive +/-4096.
        for(i=0;i<20000;i=i+1) begin
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            quotient=(i<8) ? (48'd32766+i) : ((i<16) ? (48'd131068+i-8) : {rng,16'd0});
            expected=(quotient>131072) ? 131072 : ((quotient<32768) ? 32768 : quotient[19:0]);
            if(dut.F_limit_gain(quotient)!==expected) $fatal(1,"limit mismatch");
            c=32768+(rng%98305);t=32768+((rng>>8)%98305);
            close_ref=((c>>12)>=(t>>12) ? (c>>12)-(t>>12) : (t>>12)-(c>>12))<=1;
            if(dut.F_gain_bucket_close(c,t)!==close_ref) $fatal(1,"settled bucket mismatch");
            delta=$signed({1'b0,t})-$signed({1'b0,c});
            next_gain=$signed({1'b0,c})+(delta>>>3);
            expected=(next_gain<32768) ? 32768 : ((next_gain>131072) ? 131072 : next_gain[19:0]);
            if(dut.F_smooth_gain(c,t)!==expected) $fatal(1,"smooth mismatch");
            count=rng[15:0];vote=$signed(rng[16:0]);threshold=$signed({1'b0,count >> 2});
            direction_ref=(vote>threshold) ? 1 : ((vote < -threshold) ? 2 : 0);
            if(dut.F_vote_direction(vote,count)!==direction_ref) $fatal(1,"direction mismatch");
            xr=c;xb=t;cr=65536;cb=65536;
            if(i<4) begin xr=65536+4095+i;xb=65536;end
            if(i>=4 && i<8) begin xr=65536-4098+i-4;xb=65536;end
            force dut.target_r=xr;force dut.target_b=xb;
            force dut.confirmed_target_r=cr;force dut.confirmed_target_b=cb;
            close_ref=((xr>=cr ? xr-cr : cr-xr)<=4096) && ((xb>=cb ? xb-cb : cb-xb)<=4096);
            #1;
            if(dut.target_close!==close_ref) $fatal(1,"close mismatch");
        end
        release dut.target_r;release dut.target_b;
        release dut.confirmed_target_r;release dut.confirmed_target_b;
        // Every reachable current gain, with both limit targets and unity.
        for(i=32768;i<=131072;i=i+1) begin
            c=i;t=32768;delta=$signed({1'b0,t})-$signed({1'b0,c});
            expected=$signed({1'b0,c})+(delta>>>3);
            if(dut.F_smooth_gain(c,t)!==expected) $fatal(1,"IIR lower boundary");
            t=131072;delta=$signed({1'b0,t})-$signed({1'b0,c});
            expected=$signed({1'b0,c})+(delta>>>3);
            if(dut.F_smooth_gain(c,t)!==expected) $fatal(1,"IIR upper boundary");
            t=65536;delta=$signed({1'b0,t})-$signed({1'b0,c});
            expected=$signed({1'b0,c})+(delta>>>3);
            if(dut.F_smooth_gain(c,t)!==expected) $fatal(1,"IIR unity boundary");
        end
        $display("AWB_ARITHMETIC_EQUIVALENCE_PASS 20000_vectors directions legal_gains inclusive_delta_boundaries 294915_IIR_boundary_vectors");
        $finish;
    end
endmodule
