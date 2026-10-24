`timescale 1ns/1ps
module tb_hand_fist_compact;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0;
    ua_hand_profile #(.IMG_WIDTH(1280),.IMG_HEIGHT(720),.DYNAMIC_ROI(1)) dut (
        .I_clk(clk),.I_rst_n(rst_n),.I_clear(1'b0),
        .I_sample_valid(1'b0),.I_motion_hit(1'b0),.I_x_grp(10'd0),.I_y(10'd0),
        .I_rgb(96'd0),.I_frame_done(1'b0),.O_id(),.O_result_valid(),
        .O_tip_count(),.O_box_valid(),.O_box_xmin(),.O_box_xmax(),
        .O_box_ymin(),.O_box_ymax());
    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        force dut.qualified_open_hint=0;
        force dut.profile_classified=1;
        force dut.xmin=0; force dut.xmax=34;
        force dut.box_height=210; #1;
        if (!dut.fist_compact || dut.classified!=1) $fatal(1,"3:2 boundary rejected");
        force dut.box_height=211; #1;
        if (dut.fist_compact || dut.classified!=0) $fatal(1,"tall strip accepted");
        force dut.profile_classified=2; #1;
        if (dut.classified!=2) $fatal(1,"POINT changed by FIST veto");
        force dut.qualified_open_hint=1; #1;
        if (dut.classified!=3) $fatal(1,"OPEN changed by FIST veto");
        force dut.xmax=1023; force dut.box_height=1023; #1;
        // The 10-bit width wraps at 1024; it must not gain a large allowance.
        if (dut.fist_width_limit!=14'd0 || dut.fist_compact)
            $fatal(1,"width wrap arithmetic mismatch");
        force dut.xmax=1022; #1;
        if (dut.fist_width_limit!=14'd12276 || !dut.fist_compact)
            $fatal(1,"wide intermediate truncated");
        $display("HAND_FIST_COMPACT_PASS"); $finish;
    end
endmodule
