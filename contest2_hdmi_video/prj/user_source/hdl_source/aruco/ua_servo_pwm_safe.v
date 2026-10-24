// Hardware PWM. Defaults OFF; no automatic arm from coordinates.
// One clock domain. Commands latch only at a 20ms frame boundary. Loss of command
// refresh revokes outputs immediately at timeout, even if software is blocked.
module ua_servo_pwm_safe #(
    parameter integer CLOCK_HZ=50000000, FRAME_US=20000,
    parameter integer MIN_US=1300,MAX_US=1700,TIMEOUT_US=150000
)(
    input clk,rst_n,arm,update,
    input [15:0] pulse_a_us,pulse_b_us,
    output pwm_a,pwm_b,output reg timed_out
);
    localparam integer TICKS_US=CLOCK_HZ/1000000;
    localparam integer SUB_BITS=TICKS_US<2?1:$clog2(TICKS_US);
    localparam integer FRAME_BITS=$clog2(FRAME_US);
    localparam integer AGE_BITS=$clog2(TIMEOUT_US+1);
    reg [SUB_BITS-1:0] sub_tick;
    reg [FRAME_BITS-1:0] frame_tick;
    reg [AGE_BITS-1:0] age;
    reg [15:0] width_a,width_b;
    reg live;
    wire [15:0] clamped_a=pulse_a_us<MIN_US?MIN_US:pulse_a_us>MAX_US?MAX_US:pulse_a_us;
    wire [15:0] clamped_b=pulse_b_us<MIN_US?MIN_US:pulse_b_us>MAX_US?MAX_US:pulse_b_us;
    reg [15:0] pending_a,pending_b;
    wire us_tick=sub_tick==TICKS_US-1;
    wire boundary=us_tick && frame_tick==FRAME_US-1;
    assign pwm_a=arm && live && !timed_out && frame_tick<width_a;
    assign pwm_b=arm && live && !timed_out && frame_tick<width_b;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            sub_tick<=0;frame_tick<=0;age<=TIMEOUT_US;live<=0;timed_out<=1;
            width_a<=0;width_b<=0;pending_a<=1500;pending_b<=1500;
        end else begin
            sub_tick<=us_tick?0:sub_tick+1'b1;
            if(us_tick)frame_tick<=boundary?0:frame_tick+1'b1;
            if(!arm)begin live<=0;timed_out<=1;age<=TIMEOUT_US;end
            else if(update)begin
                pending_a<=clamped_a;pending_b<=clamped_b;age<=0;timed_out<=0;
            end else if(us_tick && age<TIMEOUT_US)begin
                age<=age+1'b1;
                if(age==TIMEOUT_US-1)begin live<=0;timed_out<=1;end
            end
            if(boundary && arm && (!timed_out || update))begin
                live<=1;
                width_a<=update?clamped_a:pending_a;
                width_b<=update?clamped_b:pending_b;
            end
        end
    end
endmodule
