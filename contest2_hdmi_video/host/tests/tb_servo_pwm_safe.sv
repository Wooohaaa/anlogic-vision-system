`timescale 1ns/1ps
module tb_servo_pwm_safe #(parameter CLOCK_HZ=1000000);
    localparam TICKS=CLOCK_HZ/1000000;
    reg clk=0,rst=0,arm=0,update=0;
    reg [15:0] a=1500,b=1500;
    wire pa,pb,timeout;
    always #5 clk=~clk;
    ua_servo_pwm_safe #(.CLOCK_HZ(CLOCK_HZ),.TIMEOUT_US(65000)) dut(clk,rst,arm,update,a,b,pa,pb,timeout);
    task command(input [15:0] aa,input [15:0] bb);
        begin @(negedge clk);a=aa;b=bb;update=1;@(negedge clk);update=0;end
    endtask
    task count_frame(input integer expected_a,input integer expected_b);
        integer n,ca,cb;
        begin
            while(dut.frame_tick!=0 || dut.sub_tick!=0)@(negedge clk);
            ca=0;cb=0;
            for(n=0;n<20000*TICKS;n=n+1)begin
                ca=ca+pa;cb=cb+pb;@(negedge clk);
            end
            if(ca!=expected_a*TICKS || cb!=expected_b*TICKS)$fatal(1,"width %d %d expected %d %d",ca,cb,expected_a*TICKS,expected_b*TICKS);
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);rst=1;
        repeat(20)begin @(negedge clk);if(pa || pb)$fatal(1,"default on");end
        arm=1;command(100,3000);
        count_frame(1300,1700);
        // Software goes silent; hardware revokes outputs without an interrupt.
        repeat(70000*TICKS)@(negedge clk);
        if(pa || pb || !timeout)$fatal(1,"watchdog failed");
        command(1500,1600);count_frame(1500,1600);
        arm=0;#1;if(pa || pb)$fatal(1,"disarm not immediate");
        @(negedge clk);rst=0;#1;if(pa || pb)$fatal(1,"reset");
        $display("SERVO_PWM_SAFE_PASS default_off_clamp_watchdog_rearm_disarm");$finish;
    end
    initial begin #150000000;$fatal(1,"timeout");end
endmodule
