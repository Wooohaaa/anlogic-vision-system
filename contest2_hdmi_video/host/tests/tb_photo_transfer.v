`timescale 1ns/1ps
module tb_photo_transfer;
  parameter BLACK=64;
  reg clk=0,rst=1,valid=0,user=0,last=0,ready=1;
  reg [39:0] raw=0;
  wire [39:0] fixed_raw;
  wire [31:0] converted;
  wire cv,cu,cl,ir;
  always #8 clk=~clk;
  ua_raw_black_40 #(.BLACK_LEVEL(BLACK)) black_stage(raw,fixed_raw);
  mipi_to_raw_converter converter(clk,rst,fixed_raw,10'd0,last,valid,user,ir,
                                 converted,cl,cv,cu,ready);
  wire pv,pu,pl; wire [95:0] pd;
  ua_photo_finish_96 #(.IMG_WIDTH(16)) photo(clk,rst,1'b0,1'b0,1'b0,
                                         96'd0,2'd0,pv,pu,pl,pd);
  reg [7:0] gamma_ref[0:255];
  integer i,k,c,ref10,expected,checked=0;
  initial begin
    $readmemh("tmp/photo_tests/gamma.hex",gamma_ref);
    #1 rst=0; #32 rst=1;
    for(i=0;i<256;i=i+1)
      for(k=0;k<4;k=k+1)
        if(photo.tone(i,k)!==gamma_ref[i]) $fatal(1,"gamma mismatch %0d strength %0d",i,k);
    for(i=0;i<1024;i=i+1) begin
      @(negedge clk);
      valid=(i%7!=3); user=(i%19==0); last=(i%11==10);
      ready=i%2;
      for(k=0;k<4;k=k+1) raw[k*10+:10]=(i+73*k)%1024;
      @(posedge clk); #1;
      if(cv!==valid || cu!==user || cl!==last || ir!==ready)
        $fatal(1,"converter sideband/ready mismatch at %0d",i);
      if(valid) begin
        for(k=0;k<4;k=k+1) begin
          c=(i+73*k)%1024;
          ref10=(BLACK==0)?c:((c<=BLACK)?0:c-BLACK+2);
          if(ref10>1023) ref10=1023;
          expected=ref10/4;
          if(fixed_raw[k*10+:10]!==ref10[9:0] || converted[(3-k)*8+:8]!==expected[7:0])
            $fatal(1,"raw mismatch black=%0d raw=%0d lane=%0d",BLACK,c,k);
          checked=checked+1;
        end
      end
      if(i==511) begin
        @(negedge clk);rst=0;
        #1;if(cv!==0 || converted!==0) $fatal(1,"reset flush failed");
        @(negedge clk);rst=1;
      end
    end
    $display("PHOTO_TRANSFER_PASS black=%0d gamma=256x4 raw_samples=%0d lanes rounding clamp reset bubbles",BLACK,checked);
    $finish;
  end
  initial begin #1000000; $fatal(1,"timeout"); end
endmodule
