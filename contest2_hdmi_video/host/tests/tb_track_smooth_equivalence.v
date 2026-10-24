`timescale 1ns/1ps
module tb_track_smooth_equivalence;
  ua_track_detect dut();
  integer old_v,new_v,expected;
  initial begin
    for(old_v=0;old_v<2048;old_v=old_v+1)
      for(new_v=0;new_v<2048;new_v=new_v+1) begin
        expected=(3*old_v+new_v+2)/4;
        if(dut.F_smooth4(old_v,new_v)!==expected[10:0])
          $fatal(1,"SMOOTH_MISMATCH old=%0d new=%0d",old_v,new_v);
      end
    $display("TRACK_SMOOTH_EXHAUSTIVE_PASS cases=4194304");
    $finish;
  end
endmodule
