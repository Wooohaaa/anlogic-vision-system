`timescale 1ns/1ps
// Actual estimator, divider and line RAM, not a software-only AWB test.
module tb_photo_awb;
  reg clk=0,rst=1,valid=0,user=0,last=0;
  reg [95:0] data=0;
  always #8 clk=~clk;
  wire ready,ov,ou,ol; wire [95:0] od;
  ua_awb_frame #(.IMG_WIDTH(256),.IMG_HEIGHT(2)) dut(
    .I_clk(clk),.I_rst_n(rst),.I_tlast(last),.I_tuser(user),.I_tdata(data),.I_tvalid(valid),.I_tready(ready),.O_tlast(ol),.O_tuser(ou),.O_tdata(od),.O_tvalid(ov),.O_tready(1'b1));
  reg [19:0] old_r=20'h10000,old_b=20'h10000;
  reg [19:0] hold_r,hold_b;
  integer f,y,g;
  always @(posedge clk) begin
    #1;
    if(rst && !user && (dut.gain_r!==old_r || dut.gain_b!==old_b))
      $fatal(1,"gain changed outside frame start");
    old_r=dut.gain_r;old_b=dut.gain_b;
    if(ov && (^od===1'bx)) $fatal(1,"unknown valid RGB");
  end
  task frame;
    input [23:0] pixel;
    begin
      @(negedge clk);user=1;valid=0;last=0;
      @(negedge clk);user=0;
      for(y=0;y<2;y=y+1) begin
        for(g=0;g<64;g=g+1) begin
          @(negedge clk);valid=1;data={4{pixel}};last=(g==63);
        end
        @(negedge clk);valid=0;last=0;
        repeat(80) @(negedge clk);
      end
      repeat(160) @(negedge clk);
    end
  endtask
  initial begin
    #1 rst=0;#32 rst=1;
    if(dut.F_awb_pixel_eligible(24'h060606) ||
       dut.F_awb_pixel_eligible(24'hf5f5f5) ||
       dut.F_awb_pixel_eligible(24'h0ab40a) ||
       !dut.F_awb_pixel_eligible(24'h50645a)) $fatal(1,"sample selection");
    for(f=0;f<64;f=f+1) frame(24'h50645a);
    // G/R=1.25, G/B=1.111..., after frame IIR convergence.
    if(dut.gain_r<81600 || dut.gain_r>82100 ||
       dut.gain_b<72500 || dut.gain_b>73100) $fatal(1,"cast convergence R=%d B=%d",dut.gain_r,dut.gain_b);
    // Flush the preceding candidate before testing invalid sample scenes.
    frame(24'h0ab40a);hold_r=dut.gain_r;hold_b=dut.gain_b;
    for(f=0;f<8;f=f+1) frame(24'h0ab40a);
    for(f=0;f<8;f=f+1) frame(24'h060606);
    for(f=0;f<8;f=f+1) frame(24'hf5f5f5);
    if(dut.gain_r!==hold_r || dut.gain_b!==hold_b) $fatal(1,"invalid scene changed gains");
    for(f=0;f<64;f=f+1) frame(24'h505050);
    if(dut.gain_r<65000 || dut.gain_r>66000 ||
       dut.gain_b<65000 || dut.gain_b>66000) $fatal(1,"neutral recovery");
    $display("PHOTO_AWB_PASS cast_convergence dark_clip_saturated_hold neutral_recovery frame_only_commit");
    $finish;
  end
  initial begin #5000000;$fatal(1,"timeout");end
endmodule
