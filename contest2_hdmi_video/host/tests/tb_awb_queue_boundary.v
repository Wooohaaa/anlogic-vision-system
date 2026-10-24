`timescale 1ns/1ps
// No blanking: exercise both sides of the static short-frame queue cutoff.
module tb_awb_queue_boundary;
    parameter integer BEATS=101;
    reg clk=0,rst=1,valid=0,user=0,last=0;
    always #8 clk=~clk;
    wire ir,ol,ou,ov;wire [95:0] od;
    ua_awb_frame #(.IMG_WIDTH(BEATS*4),.IMG_HEIGHT(1)) dut(
        .I_clk(clk),.I_rst_n(rst),.I_tlast(last),.I_tuser(user),.I_tdata({4{24'h50645a}}),.I_tvalid(valid),.I_tready(ir),.O_tlast(ol),.O_tuser(ou),.O_tdata(od),.O_tvalid(ov),.O_tready(1'b1));
    integer f,x;
    initial begin
        #1 rst=0;#32 rst=1;
        for(f=0;f<100;f=f+1) begin
            for(x=0;x<BEATS;x=x+1) begin
                @(negedge clk); valid=1;user=(x==0);last=(x==BEATS-1);
                if(x==BEATS-1 && BEATS>100 && dut.div_state!==0)
                    $fatal(1,"large frame overlaps calculation");
                @(posedge clk);#1;
                if(dut.sum_g!==(x+1)*100 || dut.sample_count!==(x+1))
                    $fatal(1,"sum/count mismatch f=%0d x=%0d",f,x);
            end
        end
        @(negedge clk);valid=0;user=0;last=0;
        if(dut.gain_r<81600 || dut.gain_r>82100 || dut.gain_b<72500 || dut.gain_b>73100)
            $fatal(1,"continuous-frame convergence %0d/%0d",dut.gain_r,dut.gain_b);
        $display("AWB_QUEUE_BOUNDARY_PASS beats=%0d queue=%0d continuous_frames exact_sums",BEATS,dut.ALLOW_SHORT_FRAME_QUEUE);
        $finish;
    end
endmodule
