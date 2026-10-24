`timescale 1ns/1ps
module tb_awb_scene_confidence;
    reg clk=0,rst=1,valid=0,user=0,last=0;
    reg [95:0] data=0;
    always #8 clk=~clk;
    wire ready,ov,ou,ol;
    wire [95:0] od;
    ua_awb_frame #(.IMG_WIDTH(256),.IMG_HEIGHT(4)) dut(
        .I_clk(clk),.I_rst_n(rst),.I_tlast(last),.I_tuser(user),.I_tdata(data),.I_tvalid(valid),.I_tready(ready),.O_tlast(ol),.O_tuser(ou),.O_tdata(od),.O_tvalid(ov),.O_tready(1'b1));
    integer f,y,x,region;
    reg [23:0] pixel;
    reg [19:0] hold_r,hold_b,prev_r=65536,prev_b=65536;
    always @(posedge clk) begin
        #1;
        if(rst && !user && (dut.gain_r!==prev_r || dut.gain_b!==prev_b))
            $fatal(1,"gain changed inside frame");
        prev_r=dut.gain_r;prev_b=dut.gain_b;
        if(ov && (^od===1'bx)) $fatal(1,"unknown output");
    end
    task frame;
        input integer kind;
        input integer moving_region;
        input integer same_beat_marker;
        begin
            if(!same_beat_marker) begin
                @(negedge clk);user=1;valid=0;last=0;
                @(negedge clk);user=0;
            end
            for(y=0;y<4;y=y+1) begin
                for(x=0;x<64;x=x+1) begin
                    region=(y>=2 ? 2 : 0)+(x>=32 ? 1 : 0);
                    case(kind)
                        0: pixel=24'h646464; // neutral
                        1: pixel=24'h50645a; // genuine uniform mild illuminant cast
                        2: pixel=(region==moving_region) ? 24'h789678 : 24'h646464;
                        3: pixel=(region==moving_region) ? 24'h967878 : 24'h646464;
                        4: pixel=(region==moving_region) ? 24'h50645a : 24'h080808;
                        5: pixel=24'h181c18; // dark colored noise, formerly eligible
                        6: pixel=(moving_region==0) ? 24'h789678 : 24'h967878;
                        default: pixel=24'hf8f8f8;
                    endcase
                    @(negedge clk);
                    valid=1;last=(x==63);data={4{pixel}};
                    user=same_beat_marker && y==0 && x==0;
                    // Include valid bubbles without advancing position.
                    if(x==11) begin
                        @(negedge clk);valid=0;user=0;last=0;
                    end
                end
                @(negedge clk);valid=0;last=0;user=0;
                repeat(60) @(negedge clk);
            end
            repeat(160) @(negedge clk);
        end
    endtask
    task check_hold;
        begin
            if(dut.gain_r!==hold_r || dut.gain_b!==hold_b)
                $fatal(1,"scene-driven gain drift R=%d B=%d expected=%d/%d",dut.gain_r,dut.gain_b,hold_r,hold_b);
        end
    endtask
    initial begin
        #1 rst=0;#32 rst=1;
        if(dut.F_awb_pixel_eligible(24'h181c18)) $fatal(1,"dark candidate accepted");
        hold_r=65536;hold_b=65536;
        for(f=0;f<24;f=f+1) begin
            frame(2,f%4,f%2);check_hold;
            frame(3,(f+1)%4,f%2);check_hold;
        end
        for(f=0;f<8;f=f+1) begin frame(4,f%4,0);check_hold;end
        for(f=0;f<20;f=f+1) begin frame(6,f%2,0);check_hold;end
        // One or two estimates alone cannot publish a new gain.
        frame(1,0,0);check_hold;
        frame(1,0,1);check_hold;
        frame(1,0,0);check_hold;
        for(f=0;f<64;f=f+1) frame(1,0,f%2);
        if(dut.gain_r<81600 || dut.gain_r>82100 || dut.gain_b<72500 || dut.gain_b>73100)
            $fatal(1,"valid cast failed to converge %d/%d",dut.gain_r,dut.gain_b);
        frame(5,0,0);hold_r=dut.gain_r;hold_b=dut.gain_b;
        for(f=0;f<12;f=f+1) begin
            frame(5,0,0);check_hold;
            frame(2,f%4,1);check_hold;
            frame(3,(f+2)%4,0);check_hold;
        end
        for(f=0;f<64;f=f+1) frame(0,0,f%2);
        if(dut.gain_r<65000 || dut.gain_r>66000 || dut.gain_b<65000 || dut.gain_b>66000)
            $fatal(1,"neutral recovery failed");
        $display("AWB_SCENE_CONFIDENCE_PASS moving_red_green_hold sparse_hold alternating_cast_hold dark_hold true_cast_convergence neutral_recovery markers_bubbles frame_only_commit");
        $finish;
    end
    initial begin #10000000;$fatal(1,"timeout");end
endmodule
