`timescale 1ns/1ps
// Live VPI host-C -> serialized AHB -> unchanged production peripheral RTL.
// Input starts at the post-ISP RGB tap, not at the sensor/MIPI interface.
module tb_aruco_live #(
    parameter integer SCENES=10,
    parameter integer BUS_HALF_NS=10
);
    reg src=0,bus=0,rst=0;
    always #8.333 src=~src;
    always #(BUS_HALF_NS) bus=~bus;
    reg [95:0] rgb=0;reg valid=0,sof=0,eol=0;
    reg [30:0] addr=0;reg [1:0] trans=0;reg write=0;
    reg [31:0] data=0;wire [31:0] out;wire ready;wire [1:0] err;
    wire pwm_a,pwm_b;
    wire result_toggle,result_valid;wire [11:0] result_id_bcd;
    wire [21:0] result_corner0,result_corner1,result_corner2,result_corner3;
    wire [25:0] result_edge0,result_edge1,result_edge2,result_edge3;
    wire [10:0] bus_debug;
    integer scene=0,frames_sent=0;
    reg source_enabled=1;
    // RGB beats in low lane first, 4 * R8G8B8 per beat.
    reg [95:0] pixels[0:SCENES*230400-1];
    string input_file;
    integer x,y,current,pass;
    ua_aruco_peripheral dut(src,bus,rst,rgb,valid,sof,eol,
        trans,write,addr,3'd2,data,out,err,ready,1'b0,1'b0,pwm_a,pwm_b,1'b1,
        result_toggle,result_valid,result_id_bcd,result_corner0,result_corner1,result_corner2,result_corner3,
        result_edge0,result_edge1,result_edge2,result_edge3,bus_debug,,,,);
    initial begin
        if(!$value$plusargs("RGB=%s",input_file))$fatal(1,"RGB input path required");
        $readmemh(input_file,pixels);
        repeat(8)@(negedge bus);rst=1;
        forever begin
            wait(source_enabled && dut.snapshot.req_sync!=dut.snapshot.acknowledge);
            current=scene;
            // A second, deliberately different frame arrives while the first
            // snapshot must stay frozen for the MCU's many reads.
            for(pass=0;pass<2;pass=pass+1)begin
                for(y=0;y<720;y=y+1)begin
                    for(x=0;x<320;x=x+1)begin
                        @(negedge src);valid=1;sof=(x==0&&y==0);eol=(x==319);
                        rgb=pixels[current*230400+y*320+x];
                        if(pass==1)rgb=~rgb;
                        // Independent valid bubbles exercise sideband/column alignment.
                        if(x%29==7)begin @(negedge src);valid=0;sof=0;eol=0;end
                    end
                    @(negedge src);valid=0;sof=0;eol=0;
                    repeat(3)@(negedge src);
                end
                frames_sent=frames_sent+1;
            end
        end
    end
    // No authorization is ever issued in this test.
    always @(posedge bus)if(rst && (pwm_a || pwm_b))$fatal(1,"PWM unexpectedly armed");
    initial begin #3000000000;$fatal(1,"live co-simulation watchdog");end
endmodule
