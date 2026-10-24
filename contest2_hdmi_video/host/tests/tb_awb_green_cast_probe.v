`timescale 1ns/1ps
// Diagnostic repro: a gray surface under a green cast is outside v9's
// raw low-chroma gate, even though the required 100/70 gain is within 1.5.
module tb_awb_green_cast_probe;
    reg clk=0,rst=1,valid=0,user=0,last=0;
    always #8 clk=~clk;
    wire ir,ol,ou,ov;wire [95:0] od;
    ua_awb_frame #(.IMG_WIDTH(256),.IMG_HEIGHT(4)) dut(
        clk,rst,last,user,{4{24'h466446}},valid,ir,ol,ou,od,ov,1'b1);
    integer f,y,x;
    initial begin
        #1 rst=0;#32 rst=1;
        for(f=0;f<32;f=f+1) begin
            @(negedge clk);user=1;valid=0;last=0;
            @(negedge clk);user=0;
            for(y=0;y<4;y=y+1) begin
                for(x=0;x<64;x=x+1) begin
                    @(negedge clk);valid=1;last=(x==63);
                end
                @(negedge clk);valid=0;last=0;
                repeat(60) @(negedge clk);
            end
            repeat(160) @(negedge clk);
        end
        if(dut.sample_count!==0 || dut.gain_r!==65536 || dut.gain_b!==65536)
            $fatal(1,"v9 diagnostic no longer reproduces; review expected limitation");
        $display("V9_GREEN_CAST_LIMITATION_REPRO input_RGB=70,100,70 samples=0 gains=1,1 frames=32 needed_gain=1.4286");
        $finish;
    end
endmodule
