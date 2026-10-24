`timescale 1ns/1ps
// Frame-level exposure-mode boundaries. No background frame or motion mask.
module tb_hand_dim_guard;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, clear=0, valid=0, done=0;
    reg [95:0] rgb={4{24'ha0a0a0}};
    wire [1:0] id;
    ua_hand_profile #(.IMG_WIDTH(320), .IMG_HEIGHT(180), .SAMPLE_STEP(4),
                      .DYNAMIC_ROI(1), .MOTION_GATE_ENABLE(0)) dut (
        .I_clk(clk), .I_rst_n(rst_n), .I_clear(clear),
        .I_sample_valid(valid), .I_motion_hit(1'b0),
        .I_x_grp(10'd0), .I_y(10'd0), .I_rgb(rgb), .I_frame_done(done),
        .O_id(id), .O_result_valid(), .O_tip_count(), .O_box_valid(),
        .O_box_xmin(), .O_box_xmax(), .O_box_ymin(), .O_box_ymax()
    );
    task frame;
        input integer dark_count;
        input expected;
        integer i;
        reg before_mode;
        begin
            before_mode=dut.dim_scene;
            for (i=0; i<3600; i=i+1) begin
                @(negedge clk);
                valid=1;
                rgb=(i<dark_count) ? {4{24'h6e6962}} : {4{24'ha0a0a0}};
                @(posedge clk); #1;
                if (dut.dim_scene!==before_mode)
                    $fatal(1,"mode changed inside frame at sample %0d",i);
            end
            @(negedge clk); valid=0; done=1;
            @(negedge clk); done=0;
            if (dut.dim_scene!==expected || dut.dim_samples!==18'd0)
                $fatal(1,"dark_count=%0d mode=%0d expected=%0d samples=%0d",
                    dark_count,dut.dim_scene,expected,dut.dim_samples);
            repeat(150) @(negedge clk);
            if (id!==0) $fatal(1,"no located hand but ID=%0d",id);
        end
    endtask
    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        frame(2699,0);
        frame(2700,1);
        rgb={4{24'h6e6962}}; #1;
        if (dut.profile_chroma_min!==11'd16) $fatal(1,"dim chroma threshold");
        rgb={4{24'h908070}}; #1;
        if (dut.profile_chroma_min!==11'd24) $fatal(1,"bright surface must stay strict");
        frame(0,0);
        frame(3600,1);
        @(negedge clk); clear=1;
        @(negedge clk); clear=0;
        if (dut.dim_scene!==0 || dut.dim_samples!==0) $fatal(1,"clear did not reset mode");
        $display("HAND_DIM_GUARD_PASS");
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1,"HAND_DIM_GUARD_TIMEOUT");
    end
endmodule
