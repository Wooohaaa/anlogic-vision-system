`timescale 1ns/1ps
module tb_hand_v36_limits #(
    parameter SAMPLE_STEP=2,
    parameter NO_BACKGROUND=0,
    parameter DIM_INPUT=0,
    parameter RECOVERY_POLICY=0
);
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, clear=0, sample_valid=0, motion_hit=0, frame_done=0;
    reg [9:0] x=0, y=0;
    reg [95:0] rgb=0;
    wire result_valid, box_valid;
    wire [1:0] id;
    wire [2:0] tips;
    wire [9:0] xmin, xmax, ymin, ymax;
    // RAM optimization equivalence only: disable the later dropout policy.
    ua_hand_profile #(.DYNAMIC_ROI(1), .SAMPLE_STEP(SAMPLE_STEP), .TEMPORAL_RECOVERY(RECOVERY_POLICY),
                      .MOTION_GATE_ENABLE(NO_BACKGROUND ? 0 : 1),
                      .MIN_AREA(400/SAMPLE_STEP),
                      .MAX_AREA(14000/SAMPLE_STEP)) dut (
        .I_clk(clk), .I_rst_n(rst_n), .I_clear(clear),
        .I_sample_valid(sample_valid), .I_motion_hit(motion_hit),
        .I_x_grp(x), .I_y(y), .I_rgb(rgb), .I_frame_done(frame_done),
        .O_result_valid(result_valid), .O_id(id), .O_tip_count(tips),
        .O_box_valid(box_valid), .O_box_xmin(xmin), .O_box_xmax(xmax),
        .O_box_ymin(ymin), .O_box_ymax(ymax)
    );
    wire ref_result_valid,ref_box_valid;
    wire [1:0] ref_id; wire [2:0] ref_tips;
    wire [9:0] ref_xmin,ref_xmax,ref_ymin,ref_ymax;
    hand_v35_reference #(.DYNAMIC_ROI(1), .SAMPLE_STEP(SAMPLE_STEP), .TEMPORAL_RECOVERY(RECOVERY_POLICY),
                      .MOTION_GATE_ENABLE(NO_BACKGROUND ? 0 : 1),
                      .MIN_AREA(400/SAMPLE_STEP),
                      .MAX_AREA(14000/SAMPLE_STEP)) reference (
        .I_clk(clk), .I_rst_n(rst_n), .I_clear(clear),
        .I_sample_valid(sample_valid), .I_motion_hit(motion_hit),
        .I_x_grp(x), .I_y(y), .I_rgb(rgb), .I_frame_done(frame_done),
        .O_result_valid(ref_result_valid), .O_id(ref_id), .O_tip_count(ref_tips),
        .O_box_valid(ref_box_valid), .O_box_xmin(ref_xmin), .O_box_xmax(ref_xmax),
        .O_box_ymin(ref_ymin), .O_box_ymax(ref_ymax)
    );
    always @(posedge clk) begin
        #1;
        if(rst_n && {result_valid,box_valid,id,tips,xmin,xmax,ymin,ymax} !==
                    {ref_result_valid,ref_box_valid,ref_id,ref_tips,ref_xmin,ref_xmax,ref_ymin,ref_ymax})
          $fatal(1,"hand RAM cycle mismatch x=%d y=%d state=%d",x,y,dut.state);
    end

    integer results=0;
    reg [1:0] last_id=0;
    reg last_box=0;
    integer last_xmin=0, last_xmax=0, last_ymin=0, last_ymax=0;
    always @(posedge clk) if (result_valid) begin
        results=results+1;
        last_id=id;
        last_box=box_valid;
        last_xmin=xmin; last_xmax=xmax;
        last_ymin=ymin; last_ymax=ymax;
    end
    function shape;
        input integer kind, cx, cy;
        integer xx, yy;
        begin
            xx=cx; yy=cy;
            shape=0;
            case(kind)
                4: shape=1;
                1: shape=((xx>=154 && xx<=207 && yy>=300 && yy<=383) ||
                          (xx>=174 && xx<=188 && yy>=384 && yy<=507));
                2: shape=((xx>=154 && xx<=207 && yy>=300 && yy<=383) ||
                          (xx>=174 && xx<=188 && yy>=384 && yy<=507) ||
                          (xx>=178 && xx<=183 && yy>=219 && yy<300));
                3: shape=((xx>=146 && xx<=214 && yy>=300 && yy<=383) ||
                          (xx>=174 && xx<=188 && yy>=384 && yy<=507) ||
                          (((xx>=149 && xx<=153) || (xx>=160 && xx<=164) ||
                            (xx>=174 && xx<=178) || (xx>=190 && xx<=194) ||
                            (xx>=206 && xx<=210)) && yy>=219 && yy<300));
            endcase
        end
    endfunction
    task send_frame;
        input integer kind, dx, dy;
        input integer expected;
        integer xx, yy, before_count;
        begin
            before_count=results;
            for (yy=SAMPLE_STEP-1; yy<720; yy=yy+SAMPLE_STEP) begin
                for (xx=0; xx<320; xx=xx+1) begin
                    @(negedge clk);
                    x=xx; y=yy;
                    sample_valid=1;
                    motion_hit=shape(kind,xx-dx,yy-dy);
                    if (NO_BACKGROUND)
                        rgb=motion_hit ? {4{DIM_INPUT ? 24'h6e6962 : 24'h907050}} :
                                         {4{24'h606060}};
                    else rgb={4{24'h907050}};
                end
            end
            @(negedge clk); sample_valid=0; motion_hit=0; frame_done=1;
            @(negedge clk); frame_done=0;
            repeat (400) @(negedge clk);
            if (results!=before_count+1 || (expected>=0 && last_id!==expected[1:0])) begin
                $display("FAIL kind=%0d dx=%0d dy=%0d id=%0d expected=%0d roi=%0d,%0d area=%0d upper=%0d rows=%0d peaks=%0d shoulder=%0d bbox=%0d,%0d,%0d,%0d",
                         kind,dx,dy,last_id,expected,dut.roi_x0_r,dut.roi_y0_r,dut.loc_area,
                         dut.upper_evidence,dut.upper_rows,dut.final_peaks,dut.shoulder_count,
                         last_xmin,last_xmax,last_ymin,last_ymax);
                $fatal(1);
            end
            if (expected>0 && (!last_box || last_xmin<0 || last_xmax>319 ||
                                last_ymin<0 || last_ymax>719 ||
                                last_xmin>last_xmax || last_ymin>last_ymax)) begin
                $display("FAIL invalid box %0d %0d %0d %0d",last_xmin,last_xmax,last_ymin,last_ymax);
                $fatal(1);
            end
            $display("PASS kind=%0d pos=%0d,%0d id=%0d roi=%0d,%0d box=%0d,%0d,%0d,%0d peaks=%0d upper=%0d baseline=%0d ymin=%0d",
                     kind,dx,dy,last_id,dut.roi_x0_r,dut.roi_y0_r,
                     last_xmin,last_xmax,last_ymin,last_ymax,
                     dut.final_peaks,dut.upper_evidence,dut.baseline,dut.ymin);
        end
    endtask
    task release_after;
        input [1:0] held;
        integer miss;
        begin
            // Current classifier deliberately keeps the last stable result
            // for four missing frames and clears it on the fifth.
            for (miss=0; miss<4; miss=miss+1)
                send_frame(0,0,0,held);
            send_frame(0,0,0,0);
        end
    endtask
    integer observed_max=0,b;
    always @(negedge clk)if(rst_n && x==319)begin
      for(b=0;b<dut.LOC_BIN_COUNT;b=b+1)begin
        if(dut.loc_bin_area[b]!==reference.loc_bin_area[b])$fatal(1,"band overflow/equivalence mismatch");
        if(dut.loc_bin_area[b]>observed_max)observed_max=dut.loc_bin_area[b];
      end
    end
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        repeat(3)send_frame(4,0,0,-1);
        if(observed_max!=320*(128/SAMPLE_STEP))$fatal(1,"max band coverage missing got=%0d",observed_max);
        $display("HAND_V36_MAX_RANGE_PASS step=%0d observed_max=%0d hist_bits=%0d band_bits=%0d",SAMPLE_STEP,observed_max,dut.HIST_COUNT_W,dut.LOC_BIN_AREA_W);
        $finish;
    end
endmodule
