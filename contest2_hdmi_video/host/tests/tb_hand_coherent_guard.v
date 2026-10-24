`timescale 1ns/1ps
// Guard boundaries for the spatial OPEN rescue; scene accuracy is checked
// separately by recorded RGB replay, not by these hierarchical probes.
module tb_hand_coherent_guard;
    reg clk=0, rst_n=0, clear=0;
    always #5 clk=~clk;
    ua_hand_profile #(.DYNAMIC_ROI(1), .SAMPLE_STEP(4),
                      .MOTION_GATE_ENABLE(0), .MIN_AREA(100)) dut (
        .I_clk(clk), .I_rst_n(rst_n), .I_clear(clear),
        .I_sample_valid(1'b0), .I_motion_hit(1'b0),
        .I_x_grp(10'd0), .I_y(10'd0), .I_rgb(96'd0), .I_frame_done(1'b0),
        .O_result_valid(), .O_id(), .O_tip_count(), .O_box_valid(),
        .O_box_xmin(), .O_box_xmax(), .O_box_ymin(), .O_box_ymax()
    );
    initial begin
        #12; rst_n=1; #10;
        if (dut.coherent_open_hint!==0) $fatal(1,"reset left OPEN evidence");
        force dut.coherent_open_hint=1;
        force dut.capture_roi_valid=1;
        force dut.bbox_seen=1;
        force dut.area=100;
        force dut.upper_evidence=1;
        force dut.coherent_finger_long=0;
        force dut.columns=89;
        #1; if(dut.qualified_coherent_open!==0) $fatal(1,"narrow profile accepted");
        force dut.columns=90;
        #1; if(dut.qualified_coherent_open!==0) $fatal(1,"brief triplet accepted");
        force dut.upper_evidence=0;
        force dut.coherent_finger_long=1;
        force dut.columns=59;
        #1; if(dut.qualified_coherent_open!==0) $fatal(1,"thin rescue too narrow");
        force dut.columns=60;
        #1; if(dut.qualified_coherent_open!==1) $fatal(1,"thin rescue boundary rejected");
        force dut.coherent_finger_long=0;
        force dut.columns=90;
        force dut.upper_evidence=0;
        #1; if(dut.qualified_coherent_open!==0) $fatal(1,"compact fist texture accepted");
        force dut.upper_evidence=1;
        force dut.coherent_finger_long=1;
        force dut.area=99;
        #1; if(dut.qualified_coherent_open!==0) $fatal(1,"undersized profile accepted");
        force dut.area=100;
        force dut.capture_roi_valid=0;
        #1; if(dut.qualified_coherent_open!==0) $fatal(1,"invalid ROI accepted");
        release dut.coherent_open_hint;
        release dut.capture_roi_valid;
        release dut.bbox_seen;
        release dut.area;
        release dut.columns;
        release dut.upper_evidence;
        release dut.coherent_finger_long;
        @(negedge clk); clear=1;
        @(negedge clk); clear=0;
        #1; if(dut.coherent_open_hint!==0 || dut.finger_best_rows!==0 ||
               dut.palm_bridge_seen!==0) $fatal(1,"clear left spatial evidence");
        $display("HAND_COHERENT_GUARD_PASS");
        $finish;
    end
endmodule
