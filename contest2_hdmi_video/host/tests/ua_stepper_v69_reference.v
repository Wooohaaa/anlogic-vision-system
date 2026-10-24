// Two independent STEP/DIR axes, shared 1us enable, no generated fabric clock.
// 50MHz bus; signed positions/goals in steps, rates in pulses/second.
// APB local offsets: 00 STP2,04 status,08 staged goals,0c staged rates,
// 10 command,14 command positions,18 committed goals,1c committed rates.
// ARM never implies homing. ZERO is an explicit operator-established origin.
// Position is emitted STEP count, NOT encoder feedback. Hard stop loses origin.
module ua_stepper_v69_reference #(
    parameter integer CLOCK_MHZ=50,
    parameter integer WAKE_US=50000,
    parameter integer WATCHDOG_US=250000
)(
    input clk,rst_n,input [4:0] addr,input select,enable,write,
    input [31:0] wdata,input [3:0] strobe,
    output reg [31:0] rdata,output error,
    output reg [1:0] step,dir,output [1:0] awake
);
    localparam [31:0] ZERO=32'h5a45524f,ARM=32'h41524d32,
                      COMMIT=32'h434d5432,KEEP=32'h4b454550;
    reg [5:0] divider;
    wire tick=divider==CLOCK_MHZ-1;
    reg armed,origin_valid,fault;
    reg [17:0] age;
    reg [15:0] wake_count;
    reg [3:0] release_count;
    reg [31:0] staged_goal,staged_rate;
    reg signed [15:0] position[0:1],goal[0:1],rate[0:1];
    reg [19:0] phase[0:1];
    reg [3:0] guard[0:1];
    reg [2:0] high_count[0:1];
    wire command_write=select && enable && write && !error && addr==5'h10;
    wire is_stop=command_write && wdata==0;
    wire is_zero=command_write && wdata==ZERO;
    wire is_arm=command_write && wdata==ARM;
    wire is_commit=command_write && wdata==COMMIT;
    wire is_keep=command_write && wdata==KEEP;
    wire signed [15:0] g0=staged_goal[15:0],g1=staged_goal[31:16];
    wire signed [15:0] v0=staged_rate[15:0],v1=staged_rate[31:16];
    wire range_ok=g0>=-16'sd640 && g0<=16'sd640 && g1>=-16'sd640 && g1<=16'sd640 &&
                  v0>=-16'sd1000 && v0<=16'sd1000 && v1>=-16'sd1000 && v1<=16'sd1000;
    wire command_ok=wdata==0 || wdata==ZERO || wdata==ARM || wdata==COMMIT || wdata==KEEP;
    wire writable=addr==5'h08 || addr==5'h0c || addr==5'h10;
    assign error=addr[1:0]!=0 || (write && (strobe!=4'hf || !writable ||
                 (addr==5'h10 && !command_ok)));
    // Release only after complete STEP pulse and >=10us trailing hold.
    assign awake={2{armed || release_count!=0 || step!=0}};
    always @* begin
        rdata=0;
        case(addr)
            5'h00:rdata=32'h53545032;
            5'h04:rdata={24'd0,step,dir,awake[0],fault,origin_valid,armed};
            5'h08:rdata=staged_goal;
            5'h0c:rdata=staged_rate;
            5'h14:rdata={position[1],position[0]};
            5'h18:rdata={goal[1],goal[0]};
            5'h1c:rdata={rate[1],rate[0]};
        endcase
    end
    integer i;
    reg [15:0] magnitude;
    reg [20:0] sum;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            divider<=0;armed<=0;origin_valid<=0;fault<=0;age<=0;
            wake_count<=0;release_count<=0;step<=0;dir<=0;
            staged_goal<=0;staged_rate<=0;
            for(i=0;i<2;i=i+1) begin
                position[i]<=0;goal[i]<=0;rate[i]<=0;phase[i]<=0;
                guard[i]<=0;high_count[i]<=0;
            end
        end else begin
            if(tick)divider<=0;else divider<=divider+1'b1;
            if(select && enable && write && !error) begin
                if(addr==5'h08)staged_goal<=wdata;
                if(addr==5'h0c)staged_rate<=wdata;
            end
            if(tick) begin
                if(armed) begin
                    if(age<WATCHDOG_US-1)age<=age+1'b1;
                    else begin armed<=0;fault<=1;origin_valid<=0;end
                    if(wake_count!=0)wake_count<=wake_count-1'b1;
                    release_count<=10;
                end else if(step!=0)release_count<=10;
                else if(release_count!=0)release_count<=release_count-1'b1;
                for(i=0;i<2;i=i+1) begin
                    if(step[i]) begin
                        if(high_count[i]==1)begin step[i]<=0;high_count[i]<=0;guard[i]<=5;end
                        else high_count[i]<=high_count[i]-1'b1;
                    end else if(guard[i]!=0)guard[i]<=guard[i]-1'b1;
                    else if(armed && wake_count==0) begin
                        if(dir[i]!=!rate[i][15])begin dir[i]<=!rate[i][15];guard[i]<=5;phase[i]<=0;end
                        else if((rate[i]>0 && position[i]<goal[i]) || (rate[i]<0 && position[i]>goal[i]))begin
                            magnitude=rate[i][15]?-rate[i]:rate[i];
                            sum={1'b0,phase[i]}+{5'd0,magnitude};
                            if(sum>=21'd1000000)begin
                                phase[i]<=sum-21'd1000000;step[i]<=1;high_count[i]<=5;
                                if(rate[i][15])position[i]<=position[i]-16'sd1;
                                else position[i]<=position[i]+16'sd1;
                            end else phase[i]<=sum[19:0];
                        end else phase[i]<=0;
                    end else phase[i]<=0;
                end
            end
            // Commands win over timeout tick. COMMIT is atomic across both axes.
            // Timeout faults cannot be cleared or armed without an explicit ZERO.
            if(is_stop)begin armed<=0;origin_valid<=0;age<=0;end
            if(is_zero && awake==0)begin
                origin_valid<=1;fault<=0;age<=0;
                for(i=0;i<2;i=i+1)begin position[i]<=0;goal[i]<=0;rate[i]<=0;phase[i]<=0;end
            end
            if(is_arm && origin_valid && !fault && !armed)begin
                armed<=1;age<=0;wake_count<=WAKE_US;release_count<=10;
            end
            if(is_keep && armed && age<WATCHDOG_US-1)age<=0;
            if(is_commit)begin
                if(armed && !fault && age<WATCHDOG_US-1 && range_ok)begin
                    goal[0]<=g0;goal[1]<=g1;rate[0]<=v0;rate[1]<=v1;age<=0;
                end else begin armed<=0;fault<=1;origin_valid<=0;end
            end
        end
    end
endmodule
