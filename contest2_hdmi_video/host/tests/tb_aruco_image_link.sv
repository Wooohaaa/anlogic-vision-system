`timescale 1ns/1ps
module tb_aruco_image_link #(
    parameter real SRC_HALF_NS=7.0,
    parameter integer BUS_HALF_NS=10,
    parameter integer BUBBLES=0
);
    reg src=0,bus=0,rst=0;
    always #(SRC_HALF_NS) src=~src;
    always #(BUS_HALF_NS) bus=~bus;
    reg [95:0] rgb=0;reg valid=0,sof=0,eol=0;
    reg [30:0] addr=0;reg [1:0] trans=0;reg write=0;
    reg [31:0] data=0;wire [31:0] out;wire ready;wire [1:0] err;
    wire pwm_a,pwm_b;reg [31:0] value;
    wire result_toggle,result_valid;wire [11:0] result_id_bcd;
    wire [21:0] result_corner0,result_corner1,result_corner2,result_corner3;
    wire [25:0] result_edge0,result_edge1,result_edge2,result_edge3;
    wire [10:0] bus_debug;
    reg [7:0] image[0:14399];integer x,y,i,fd;
    string input_file,output_file;
    ua_aruco_peripheral dut(src,bus,rst,rgb,valid,sof,eol,
        trans,write,addr,3'd2,data,out,err,ready,1'b1,1'b1,pwm_a,pwm_b,1'b1,
        result_toggle,result_valid,result_id_bcd,result_corner0,result_corner1,result_corner2,result_corner3,
        result_edge0,result_edge1,result_edge2,result_edge3,bus_debug,,,,);
    task transaction(input wr,input [30:0] address,input [31:0] d,output [31:0] result);
        integer guard;
        begin
            @(negedge bus);while(!ready)@(negedge bus);
            addr=address;trans=2;write=wr;
            @(negedge bus);trans=0;data=d;guard=0;
            @(posedge bus);
            while(!ready)begin @(posedge bus);guard=guard+1;if(guard>20)$fatal(1,"AHB hang");end
            #1;
            if(err)$fatal(1,"AHB error addr=%h response=%b",address,err);
            result=out;@(negedge bus);data=0;
        end
    endtask
    initial begin
        if(!$value$plusargs("INPUT=%s",input_file))input_file="tmp/aruco/link_input.hex";
        if(!$value$plusargs("OUTPUT=%s",output_file))output_file="tmp/aruco/link_output.hex";
        $readmemh(input_file,image);
        repeat(5)@(negedge bus);rst=1;repeat(8)@(negedge bus);
        if(!pwm_a || !pwm_b)$fatal(1,"legacy routing changed");
        transaction(1,'h100,1,value);#1;if(pwm_a || pwm_b)$fatal(1,"hardware OFF failed");
        transaction(0,0,0,value);if(value!==32'h41525531)$fatal(1,"signature");
        transaction(1,8,1,value);
        repeat(6)@(negedge src);
        for(y=0;y<720;y=y+1)begin
            for(x=0;x<320;x=x+1)begin
                @(negedge src);valid=1;sof=(x==0 && y==0);eol=(x==319);
                rgb={12{image[(y/8)*160+(x/2)]}};
                if(BUBBLES && x%17==5)begin
                    @(negedge src);valid=0;sof=0;eol=0;
                end
            end
            @(negedge src);valid=0;sof=0;eol=0;
        end
        repeat(8)@(negedge bus);
        transaction(0,4,0,value);if(value!==2)$fatal(1,"full frame status %h",value);
        fd=$fopen(output_file,"w");if(!fd)$fatal(1,"output file");
        for(i=0;i<14400;i=i+1)begin
            transaction(0,4096+4*i,0,value);$fdisplay(fd,"%02h",value[7:0]);
        end
        $fclose(fd);$display("ARUCO_FULL720_SNAPSHOT_PASS pixels=14400");$finish;
    end
    initial begin #10000000;$fatal(1,"timeout");end
endmodule
