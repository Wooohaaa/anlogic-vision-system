`timescale 1ns/1ps
module tb_red_ball_uart;
 reg src_clk=0,dst_clk=0,rst_n=0,enable=0,frame_valid=0,target_valid=0;
 reg [1:0] target_shape=0;
 reg [10:0] x=640,y=360,xmin=600,xmax=680,ymin=320,ymax=400;
 wire tx;
 always #7 src_clk=~src_clk;
 always #10 dst_clk=~dst_clk;
 ua_red_ball_uart #(.BIT_CYCLES(4),.FRAME_CYCLES(500),.STALE_POLLS(3)) dut(
 .src_clk(src_clk),.dst_clk(dst_clk),.rst_n(rst_n),.enable(enable),
 .frame_valid(frame_valid),.target_valid(target_valid),.target_shape(target_shape),
 .target_x(x),.target_y(y),.xmin(xmin),.xmax(xmax),.ymin(ymin),.ymax(ymax),.tx(tx));
 reg [7:0] received[0:8];
 integer packets=0,rx_x,rx_y,rx_valid,i,j;
 initial forever begin
   @(negedge tx); #120;
   for(i=0;i<9;i=i+1) begin
     for(j=0;j<8;j=j+1) begin received[i][j]=tx;#80;end
     if(tx!==1) $fatal(1,"UART stop bit");
     if(i<8) begin @(negedge tx);#120;end
   end
   if(received[0]!=8'h2c || received[1]!=9 || received[8]!=8'h5b)
     $fatal(1,"UART framing");
   rx_x={received[3],received[2]};rx_y={received[5],received[4]};rx_valid=received[6];
   packets=packets+1;
 end
 task frame(input bit v,input [1:0] shape);
 begin
   @(negedge src_clk);target_valid=v;target_shape=shape;frame_valid=1;
   @(negedge src_clk);frame_valid=0;
 end endtask
 task get_packet;
 integer count;
 begin count=packets;wait(packets>count);#1;end endtask
 initial begin
   #100;rst_n=1;enable=1;
   frame(1,0);frame(1,0);get_packet();
   if(rx_valid) $fatal(1,"Acquired before three frames");
   frame(1,0);get_packet();
   if(rx_valid!=1||rx_x!=160||rx_y!=90)$fatal(1,"Center mapping %d %d %d",rx_x,rx_y,rx_valid);
   // Corner and asynchronous changing source must preserve a coherent packet.
   x=1279;y=719;xmin=1230;xmax=1279;ymin=670;ymax=719;
   frame(1,0);get_packet();
   if(rx_x!=319||rx_y!=179||!rx_valid)$fatal(1,"Corner mapping");
   frame(1,1);get_packet();if(rx_valid)$fatal(1,"Non-circle accepted");
   frame(1,0);frame(1,0);frame(1,0);get_packet();
   get_packet();get_packet();get_packet();if(rx_valid)$fatal(1,"Frozen-camera stale target");
   frame(0,0);get_packet();if(rx_valid)$fatal(1,"Lost target still live");
   enable=0;#2000;if(tx!==1)$fatal(1,"Disabled UART not idle");
   enable=1;x=640;y=360;xmin=600;xmax=680;ymin=320;ymax=400;
   frame(1,0);frame(1,0);frame(1,0);get_packet();
   if(!rx_valid||rx_x!=160||rx_y!=90)$fatal(1,"Re-enable failed");
   $display("RED_BALL_UART_PASS packets=%0d",packets);$finish;
 end
 initial begin #2000000;$fatal(1,"Timeout");end
endmodule
