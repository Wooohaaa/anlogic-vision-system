`timescale 1ns/1ps
module tb_aruco_snapshot;
    reg src=0,bus=0,rst=0;
    always #7 src=~src;
    always #10 bus=~bus;
    reg [95:0] rgb=0;reg valid=0,sof=0,eol=0;
    reg [19:0] addr=0;reg sel=0,en=0,write=0;
    reg [31:0] data=0;reg [3:0] strobe=15;
    wire [31:0] out;wire ready,err;
    reg [31:0] value;integer i;
    ua_aruco_snapshot #(.IMG_WIDTH(64),.IMG_HEIGHT(32)) dut(
        src,rst,rgb,valid,sof,eol,bus,rst,addr,sel,en,write,data,strobe,out,ready,err);
    task rd(input [19:0] a,output [31:0] result);
        begin
            @(negedge bus);addr=a;sel=1;en=0;write=0;
            @(negedge bus);en=1;#1;result=out;
            if(!ready || err)$fatal(1,"APB read error addr=%h err=%b",a,err);
            @(negedge bus);sel=0;en=0;
        end
    endtask
    task wr(input [31:0] d);
        begin
            @(negedge bus);addr=8;sel=1;en=0;write=1;data=d;
            @(negedge bus);en=1;
            @(negedge bus);sel=0;en=0;write=0;
        end
    endtask
    task frame(input integer bias,input integer broken);
        integer x,y;reg [7:0] shade;
        begin
            for(y=0;y<32;y=y+1)begin
                for(x=0;x<16;x=x+1)begin
                    @(negedge src);valid=1;sof=(x==0 && y==0);eol=(x==(broken?14:15));
                    shade=bias+y*2+x;rgb={12{shade}};
                end
                @(negedge src);valid=0;sof=0;eol=0;
                repeat(2)@(negedge src);
            end
        end
    endtask
    initial begin
        repeat(5)@(negedge bus);rst=1;
        rd(0,value);if(value!==32'h41525531)$fatal(1,"identity");
        rd(16,value);if(value!==32'h00040008)$fatal(1,"dimensions %h",value);
        wr(1);repeat(6)@(negedge src);
        frame(10,0);repeat(8)@(negedge bus);
        rd(4,value);if(value!==2)$fatal(1,"status %h",value);
        for(i=0;i<32;i=i+1)begin
            rd(4096+4*i,value);
            if(value!==10+(i/8)*16+(i%8)*2)$fatal(1,"pixel %d %d",i,value);
        end
        // New video and duplicate request cannot overwrite an owned snapshot.
        wr(1);frame(90,0);rd(4096,value);if(value!==10)$fatal(1,"torn snapshot");
        wr(2);wr(1);repeat(6)@(negedge src);frame(30,0);
        repeat(8)@(negedge bus);rd(4096,value);if(value!==30)$fatal(1,"recapture");
        rd(12,value);if(value!==2)$fatal(1,"sequence");
        // Wrong line lengths must not be published as valid.
        wr(2);wr(1);repeat(6)@(negedge src);frame(40,1);
        repeat(8)@(negedge bus);rd(4,value);if(value!==4)$fatal(1,"malformed frame %h",value);
        @(negedge bus);rst=0;repeat(4)@(negedge bus);rst=1;
        rd(4,value);if(value!==0)$fatal(1,"reset stale data");
        $display("ARUCO_SNAPSHOT_PASS cdc_freeze_release_malformed_reset");$finish;
    end
    initial begin #10000000;$fatal(1,"timeout");end
endmodule
