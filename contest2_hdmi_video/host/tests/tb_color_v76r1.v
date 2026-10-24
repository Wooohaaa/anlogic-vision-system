`timescale 1ns/1ps
module tb_color_v76r1;
  parameter WIDTH=16;
  parameter TONE_ENABLE=1;
  parameter BUBBLES=1;
  parameter INPUT_BITS=8;
  parameter WINDOW5=1;
  parameter HEIGHT=8;
  localparam GROUPS=WIDTH/4, WORDS=3*HEIGHT*GROUPS;
  reg clk=0,rst=1,valid=0,user=0,last=0;
  reg [12*INPUT_BITS-1:0] data=0;
  reg [1:0] strength=0;
  reg checking=0;
  reg [4:0] valid_pipe=0,user_pipe=0,last_pipe=0;
  reg ref_pending=0,ref_user=0,ref_last=0;
  wire ref_emit=ref_pending && (ref_last || valid);
  always @(posedge clk or negedge rst)
    if(!rst) begin valid_pipe<=0;user_pipe<=0;last_pipe<=0;ref_pending<=0;ref_user<=0;ref_last<=0;end
    else begin
      if(valid) begin ref_pending<=1;ref_user<=user;ref_last<=last;end
      else if(ref_emit) ref_pending<=0;
      valid_pipe<={valid_pipe[3:0],ref_emit};
      user_pipe<={user_pipe[3:0],ref_emit && ref_user};
      last_pipe<={last_pipe[3:0],ref_emit && ref_last};
    end
  always #8 clk=~clk;
  wire ov,ou,ol;wire [95:0] od;
  ua_photo_finish_96 #(.IMG_WIDTH(WIDTH),.TONE_ENABLE(TONE_ENABLE),.INPUT_BITS(INPUT_BITS),.WINDOW5(WINDOW5),.SHADOW_COLOR_DENOISE(1),.COLOR_RESTORE(0),.GENTLE_SHADOW_LIFT(1),.SELECTIVE_SHADOW_BOOST(1),.RUNTIME_STRENGTH(1),.HIGHLIGHT_SAFE_LIFT(1)) dut(clk,rst,valid,user,last,data,strength,ov,ou,ol,od);
  reg [12*INPUT_BITS-1:0] inputs[0:WORDS-1];
  reg [95:0] expected[0:WORDS-1];
  integer f,y,g,index=0,got=0;
  reg [95:0] previous_output=0;
  always @(posedge clk) begin
    if(rst) begin
      if(dut.h_valid && dut.access_x>=GROUPS) $fatal(1,"RAM read address out of range");
      if(GROUPS>=4 && dut.v_valid && dut.v_x>=GROUPS) $fatal(1,"RAM write address out of range");
      if(dut.h_valid && (dut.read_addr>=2*GROUPS || dut.write_addr>=2*GROUPS || dut.read_addr==dut.write_addr))
        $fatal(1,"line bank collision or out-of-range address");
      if(GROUPS>=4 && dut.h_valid && dut.p_valid && dut.access_x==dut.p_x)
        $fatal(1,"second-line simultaneous read/write collision");
    end
    #1;
    if(checking && rst && !ov && od!==previous_output)$fatal(1,"idle output did not hold");
    previous_output=od;
    if(checking && (ov!==valid_pipe[4] || ou!==user_pipe[4] || ol!==last_pipe[4]))
      $fatal(1,"lookahead/pipeline marker mismatch");
    if(ov && checking) begin
      if(got>=WORDS) $fatal(1,"extra output");
      if(od!==expected[got]) $fatal(1,"word %0d got=%h expected=%h",got,od,expected[got]);
      if(ou !== ((got%(HEIGHT*GROUPS))==0) || ol !== ((got%GROUPS)==GROUPS-1)) $fatal(1,"sideband misalignment at %0d",got);
      got=got+1;
    end
  end
  initial begin
    $readmemh("tmp/v76r1_color/input.hex",inputs);
    $readmemh("tmp/v76r1_color/expected.hex",expected);
    #1 rst=0;#32 rst=1;
    // Dirty history and reset with data still in flight. RAM is not reset;
    // the new frame must ignore it and preserve its own first-row samples.
    for(g=0;g<GROUPS*2;g=g+1) begin
      @(negedge clk);valid=1;user=(g==0);last=(g%GROUPS==GROUPS-1);
      for(integer dirty_channel=0;dirty_channel<12;dirty_channel=dirty_channel+1)
        data[dirty_channel*INPUT_BITS+:INPUT_BITS]=211;
    end
    @(negedge clk);rst=0;valid=0;user=0;last=0;
    repeat(3) @(negedge clk);
    if(ov || ou || ol) $fatal(1,"output markers not cleared by reset");
    rst=1;checking=1;
    for(f=0;f<3;f=f+1) begin
      for(y=0;y<HEIGHT;y=y+1) begin
        for(g=0;g<GROUPS;g=g+1) begin
          @(negedge clk);valid=1;data=inputs[index];
          user=(y==0 && g==0);last=(g==GROUPS-1);
          strength=user?(2-f):2; // deliberate mid-frame change must be ignored
          index=index+1;
          if(BUBBLES && g==1) begin
            @(negedge clk);valid=0;user=0;last=0;
            @(negedge clk);
          end
          if(BUBBLES==2 && (index%7==0 || index%19==0)) begin
            @(negedge clk);valid=0;user=0;last=0;
            repeat(index%11+1) @(negedge clk);
          end
        end
        if(BUBBLES) begin
          @(negedge clk);valid=0;user=0;last=0;
          repeat(2) @(negedge clk);
        end
      end
      if(BUBBLES) repeat(6) @(negedge clk);
    end
    @(negedge clk);valid=0;user=0;last=0;
    repeat(10) @(negedge clk);
    if(got!=WORDS) $fatal(1,"missing outputs %0d",got);
    $display("PHOTO_RTL_PASS width=%0d tone_enable=%0d bubbles=%0d words=%0d pixels=%0d frames=3 frame_strength_hold first_last_pixels",WIDTH,TONE_ENABLE,BUBBLES,WORDS,WORDS*4);
    $finish;
  end
  initial begin #(WORDS*100+1000000);$fatal(1,"timeout");end
endmodule
