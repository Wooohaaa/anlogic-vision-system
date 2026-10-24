`timescale 1ns/1ps
// Three 16-pixel digit runs may support local OPEN evidence, but must not
// enter the legacy 40-pixel global OPEN counters. No first-frame reference.
module tb_hand_thin_runs;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,clear=0,valid=0,done=0;
    reg [9:0] x=0,y=0;
    reg [95:0] rgb=0;
    ua_hand_profile #(.DYNAMIC_ROI(1),.SAMPLE_STEP(4),.MOTION_GATE_ENABLE(0)) dut (
        .I_clk(clk),.I_rst_n(rst_n),.I_clear(clear),.I_sample_valid(valid),
        .I_motion_hit(1'b0),.I_x_grp(x),.I_y(y),.I_rgb(rgb),.I_frame_done(done),
        .O_id(),.O_result_valid(),.O_tip_count(),.O_box_valid(),
        .O_box_xmin(),.O_box_xmax(),.O_box_ymin(),.O_box_ymax());
    task row;
        input integer yy;
        input integer palm;
        integer xx;
        begin
            for(xx=0;xx<320;xx=xx+1) begin
                @(negedge clk); valid=1;x=xx;y=yy;
                rgb=((palm && xx>=104 && xx<=126) ||
                    (!palm && ((xx>=104 && xx<=107) ||
                     (xx>=112 && xx<=115) || (xx>=120 && xx<=123)))) ?
                    {4{24'hb47850}} : 96'd0;
            end
            @(negedge clk);valid=0;rgb=0;
            repeat(8) @(negedge clk);
            if(!palm && (dut.loc_three_rows!=0 || dut.loc_open_rows!=0))
                $fatal(1,"short digits contaminated legacy OPEN counters");
        end
    endtask
    integer i;
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        force dut.loc_seen=1;force dut.loc_xmin=104;force dut.loc_xmax=126;
        force dut.loc_ymin=384;
        for(i=0;i<10;i=i+1) row(299+4*i,0);
        if(dut.finger_best_rows!=10) $fatal(1,"thin chain rows=%d",dut.finger_best_rows);
        row(399,1);
        if(!dut.palm_bridge_seen) $fatal(1,"thin digits did not join palm");
        @(negedge clk);done=1;
        @(negedge clk);done=0;
        repeat(8) @(negedge clk);
        if(!dut.coherent_open_hint || !dut.coherent_finger_long || dut.open_hint)
            $fatal(1,"hint split failed local=%b long=%b global=%b",
                dut.coherent_open_hint,dut.coherent_finger_long,dut.open_hint);
        @(negedge clk);clear=1;
        @(negedge clk);clear=0;
        if(dut.coherent_open_hint || dut.coherent_finger_long || dut.finger_row_run_count)
            $fatal(1,"clear left thin evidence");
        $display("HAND_THIN_RUNS_PASS");$finish;
    end
    initial begin #1000000; $fatal(1,"HAND_THIN_RUNS_TIMEOUT");end
endmodule
