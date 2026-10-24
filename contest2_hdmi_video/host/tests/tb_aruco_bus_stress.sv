`timescale 1ns/1ps
// Contract master, NOT a vendor hard-MCU instruction-level model.
module tb_aruco_bus_stress #(parameter integer BUS_HALF_NS=10);
    reg clk=0,src=0,rst=0;
    always #(BUS_HALF_NS) clk=~clk;
    always #8.333 src=~src;
    reg [1:0] trans=0;reg wr=0;reg [30:0] addr=0;reg [2:0] size=2;reg [31:0] data=0;
    wire [31:0] result;wire [1:0] resp;wire ready,pa,pb;
    wire result_toggle,result_valid;wire [11:0] result_id_bcd;
    wire [10:0] bus_debug;
    reg [31:0] value,random_state=32'h53a17e49;
    integer i,guard,errors_seen=0,errors_expected=0;
    reg [31:0] pulse=1500;
    ua_aruco_peripheral #(.IMG_WIDTH(64),.IMG_HEIGHT(32)) dut(
        .src_clk(src),.bus_clk(clk),.rst_n(rst),.rgb(96'd0),.valid(1'b0),
        .sof(1'b0),.eol(1'b0),.htrans(trans),.hwrite(wr),.haddr(addr),
        .hsize(size),.hwdata(data),.hrdata(result),.hresp(resp),.hready(ready),
        .legacy_pwm_a(1'b0),.legacy_pwm_b(1'b0),.pwm_a(pa),.pwm_b(pb),
        .detect_enable(1'b1),.result_toggle(result_toggle),.result_valid(result_valid),
        .result_id_bcd(result_id_bcd),.bus_debug(bus_debug));
    always @(posedge clk)begin
        if(rst && resp==1 && !ready)errors_seen=errors_seen+1;
        if(pa || pb)$fatal(1,"unexpected PWM");
    end
    task transfer(input write,input [30:0] address,input [2:0] bytes,
                  input [31:0] payload,input error,output [31:0] readback);
        begin
            @(negedge clk);#1;while(!ready)begin @(negedge clk);#1;end
            trans=2;wr=write;addr=address;size=bytes;data=32'hbad0dada;
            @(negedge clk);#1;trans=0;data=payload;
            @(posedge clk);guard=0;
            while(!ready)begin @(posedge clk);guard=guard+1;if(guard>24)$fatal(1,"hung");end
            #1;if(resp!=={1'b0,error})$fatal(1,"response %h addr%h size%0d",resp,address,bytes);
            readback=result;
            if(error)errors_expected=errors_expected+1;
            @(negedge clk);#1;data=0;
        end
    endtask
    task reset_during_address;
        begin
            @(negedge clk);#1;trans=2;wr=1;addr='h100;size=2;data=7;
            @(negedge clk);#1;rst=0;trans=0;data=0;
            repeat(4)@(negedge clk);rst=1;
            repeat(8)@(negedge clk);pulse=1500;
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);rst=1;repeat(8)@(negedge clk);
        transfer(1,'h100,2,1,0,value);
        for(i=0;i<512;i=i+1)begin
            random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            repeat(random_state[10:8])@(negedge clk);
            case(random_state[2:0])
                0:begin transfer(0,0,2,0,0,value);if(value!==32'h41525531)$fatal(1,"signature");end
                1:begin transfer(1,'h104,2,random_state,0,value);pulse=random_state & 32'hffff;end
                2:begin transfer(0,'h104,2,0,0,value);if(value!==pulse)$fatal(1,"write data phase");end
                3:transfer(1,'h101,2,7,1,value);
                4:transfer(0,0,random_state[5]?0:1,0,1,value);
                5:transfer(1,'h100000,2,7,1,value);
                6:transfer(1,'h200,2,7,1,value);
                7:transfer(0,'h1000,2,0,1,value);
            endcase
            if(i%64==63)begin
                reset_during_address;
                transfer(0,0,2,0,0,value);if(value!==32'h41525531)$fatal(1,"reset recovery");
                transfer(0,'h104,2,0,0,value);if(value!==1500)$fatal(1,"aborted write/reset");
            end
        end
        if(errors_seen!=errors_expected)$fatal(1,"two-cycle error count %0d expected%0d",errors_seen,errors_expected);
        $display("ARUCO_BUS_STRESS_PASS transactions=512 resets=8 half_ns=%0d errors=%0d PWM_OFF",BUS_HALF_NS,errors_seen);
        $finish;
    end
    initial begin #2000000;$fatal(1,"timeout");end
endmodule
