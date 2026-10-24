`timescale 1ns/1ps
// Full 720p geometry verifies confidence thresholds, quadrant addressing and counts.
module tb_awb_full_statistics;
    reg clk=0,rst=1,valid=0,user=0,last=0;
    reg [95:0] data=0;
    always #8 clk=~clk;
    wire ready,ov,ou,ol;wire [95:0] od;
    ua_awb_frame dut(.I_clk(clk),.I_rst_n(rst),.I_tlast(last),.I_tuser(user),.I_tdata(data),.I_tvalid(valid),.I_tready(ready),.O_tlast(ol),.O_tuser(ou),.O_tdata(od),.O_tvalid(ov),.O_tready(1'b1));
    integer f,y,x,region,k;
    reg [23:0] pixel;
    task frame;
        input integer local_color;
        begin
            @(negedge clk);user=1;valid=0;last=0;
            @(negedge clk);user=0;
            for(y=0;y<720;y=y+1) begin
                for(x=0;x<320;x=x+1) begin
                    region=(y>=360 ? 2 : 0)+(x>=160 ? 1 : 0);
                    pixel=(local_color==2) ? 24'he0e0e0 :
                          (local_color==1) ? ((region==0) ? 24'h789678 : 24'h646464) : 24'h50645a;
                    @(negedge clk);valid=1;last=(x==319);data={4{pixel}};
                end
                @(negedge clk);valid=0;last=0;
                repeat(4) @(negedge clk);
            end
            repeat(160) @(negedge clk);
            for(k=0;k<4;k=k+1)
                if(dut.region_count[k]!==57600) $fatal(1,"quadrant %d count=%d",k,dut.region_count[k]);
            if(dut.sample_count!==230400) $fatal(1,"frame sample count");
            if(dut.spatial_confident!==(local_color!=1)) $fatal(1,"full geometry confidence");
            if(local_color==2 && (dut.sum_r!==51609600 || dut.sum_g!==51609600 || dut.sum_b!==51609600))
                $fatal(1,"maximum eligible sum overflow");
        end
    endtask
    initial begin
        #1 rst=0;#32 rst=1;
        frame(1);
        frame(1);
        if(dut.gain_r!==65536 || dut.gain_b!==65536) $fatal(1,"local object changed white balance");
        for(f=0;f<4;f=f+1) frame(0);
        if(dut.gain_r<=65536 || dut.gain_b<=65536) $fatal(1,"credible cast not applied");
        frame(2);
        $display("AWB_FULL720_STATISTICS_PASS 230400_samples quadrants_57600 max_sum_51609600 local_color_hold genuine_cast_commit");
        $finish;
    end
    initial begin #50000000;$fatal(1,"timeout");end
endmodule
