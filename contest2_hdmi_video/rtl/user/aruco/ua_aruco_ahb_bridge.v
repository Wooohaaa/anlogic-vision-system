// Serialized AHB-Lite master port -> APB register bank, one shared bus clock.
// Word-only MMIO. Reject misaligned/unsupported accesses before side effects.
// PH1P exported HADDR is [30:0]; the SDK AHBDemo uses CPU base 0x80000000.
// This bridge accepts only its first 1MiB.
module ua_aruco_ahb_bridge(
    input clk,rst_n,
    input [1:0] htrans,input hwrite,
    input [30:0] haddr,input [2:0] hsize,input [31:0] hwdata,
    output [31:0] hrdata,output [1:0] hresp,output hready,
    output reg [19:0] paddr,output psel,penable,
    output reg pwrite,output reg [31:0] pwdata,output [3:0] pstrobe,
    input [31:0] prdata,input pready,pslverr,
    output [2:0] debug_state,output debug_invalid
);
    localparam IDLE=0,DATA=1,SETUP=2,ACCESS=3,ERROR_LAST=4;
    reg [2:0] state;reg invalid;
    wire apb_error=state==ACCESS && pready && pslverr;
    wire completing=(state==ACCESS && pready && !pslverr) || state==ERROR_LAST;
    assign hready=state==IDLE || completing;
    assign hresp=(apb_error || state==ERROR_LAST || (state==DATA && invalid))?2'b01:2'b00;
    assign hrdata=state==ACCESS?prdata:32'd0;
    assign psel=state==SETUP || state==ACCESS;
    assign penable=state==ACCESS;
    assign pstrobe=4'hf;
    assign debug_state=state;
    assign debug_invalid=invalid;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin state<=IDLE;paddr<=0;pwrite<=0;pwdata<=0;invalid<=0;end
        else begin
            case(state)
                DATA:begin
                    // AHB write data belongs to the cycle AFTER address acceptance.
                    pwdata<=hwdata;
                    state<=invalid?ERROR_LAST:SETUP;
                end
                SETUP:state<=ACCESS;
                ACCESS:if(pready)state<=pslverr?ERROR_LAST:IDLE;
                ERROR_LAST:state<=IDLE;
                default:state<=IDLE;
            endcase
            // Also accept the next pipelined address on a completing transfer.
            if((state==IDLE || completing) && htrans[1])begin
                paddr<=haddr[19:0];pwrite<=hwrite;
                invalid<=hsize!=3'd2 || haddr[1:0]!=0 || haddr[30:20]!=0;
                state<=DATA;
            end
        end
    end
endmodule
