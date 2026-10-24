// ArUco side branch: snapshot only, never backpressures production video.
// 4 RGB pixels/beat, tuser on first valid beat, tlast on last beat of each row.
// Every eighth source pixel/row -> 160x90x8 at 1280x720. No backpressure.
// Single buffer is frozen until MCU releases it; request/ack toggles cross CDC.
// APB offsets only: system address mapping must come from the MCU user manual.
module ua_aruco_snapshot #(
    parameter integer IMG_WIDTH=1280, IMG_HEIGHT=720
)(
    input src_clk,src_rst_n,
    input [95:0] rgb,
    input valid,sof,eol,
    input bus_clk,bus_rst_n,
    input [19:0] paddr,
    input psel,penable,pwrite,
    input [31:0] pwdata,
    input [3:0] pstrobe,
    output reg [31:0] prdata,
    output pready,pslverr
);
    localparam integer PIXELS=(IMG_WIDTH/8)*(IMG_HEIGHT/8);
    localparam [15:0] OUT_WIDTH=IMG_WIDTH/8, OUT_HEIGHT=IMG_HEIGHT/8;
    reg [7:0] memory[0:PIXELS-1];
    reg request,acknowledge;
    (* ASYNC_REG="TRUE" *) reg req_meta,req_sync;
    (* ASYNC_REG="TRUE" *) reg ack_meta,ack_sync,ack_settle;
    reg capture,success;
    reg [10:0] xgroup,y;
    reg [14:0] count;
    reg bad;
    wire [10:0] cx=sof?11'd0:xgroup;
    wire [10:0] cy=sof?11'd0:y;
    wire active=capture || (sof && req_sync!=acknowledge);
    wire [9:0] gray_sum={2'b0,rgb[23:16]}+{1'b0,rgb[15:8],1'b0}+{2'b0,rgb[7:0]};
    wire sample=valid && active && !cx[0] && cy[2:0]==0;
    // No RAM reset loop: stale/uninitialized contents cannot be marked ready.
    always @(posedge src_clk)
        if(src_rst_n && sample && (sof || count<PIXELS))
            memory[sof?15'd0:count] <= gray_sum[9:2];
    always @(posedge src_clk or negedge src_rst_n) begin
        if(!src_rst_n) begin
            req_meta<=0;req_sync<=0;acknowledge<=0;
            capture<=0;success<=0;xgroup<=0;y<=0;count<=0;bad<=0;
        end else begin
            req_meta<=request;req_sync<=req_meta;
            if(valid) begin
                if(sof) begin
                    xgroup<=eol?11'd0:11'd1;y<=0;
                    if(req_sync!=acknowledge) begin capture<=1;count<=1;bad<=0;end
                    // An unexpected new frame during capture discards partial data
                    // and starts again at pixel zero, never publishes a torn frame.
                end else begin
                    if(eol)begin xgroup<=0;if(y<IMG_HEIGHT)y<=y+1'b1;end
                    else if(xgroup<IMG_WIDTH/4)xgroup<=xgroup+1'b1;
                    if(sample && count<PIXELS)count<=count+1'b1;
                end
                if(active && eol && cx!=IMG_WIDTH/4-1)bad<=1;
                if(active && eol && cy==IMG_HEIGHT-1)begin
                    capture<=0;acknowledge<=req_sync;
                    success<=!bad && cx==IMG_WIDTH/4-1 && count==PIXELS;
                end
            end
        end
    end
    reg seen_ack,ready,error;
    reg [31:0] frame_sequence;
    reg [7:0] ram_data;
    wire busy=request!=ack_settle;
    // One pixel per aligned 32-bit MMIO word; only low eight data bits used.
    wire mem_select=paddr>=20'h01000 && paddr<20'h01000+PIXELS*4 && paddr[1:0]==0;
    wire known_reg=paddr==0 || paddr==4 || paddr==8 || paddr==12 || paddr==16;
    assign pready=1'b1;
    assign pslverr=psel && penable &&
        ((!known_reg && !mem_select) || (pwrite && paddr!=8) ||
         (!pwrite && mem_select && !ready));
    // APB setup phase provides one cycle for synchronous RAM read.
    always @(posedge bus_clk)
        if(psel && !pwrite && mem_select && ready)
            ram_data<=memory[(paddr-20'h01000)>>2];
    always @(posedge bus_clk or negedge bus_rst_n) begin
        if(!bus_rst_n)begin
            request<=0;ack_meta<=0;ack_sync<=0;ack_settle<=0;
            seen_ack<=0;ready<=0;error<=0;frame_sequence<=0;
        end else begin
            ack_meta<=acknowledge;ack_sync<=ack_meta;ack_settle<=ack_sync;
            if(ack_settle!=seen_ack)begin
                seen_ack<=ack_settle;ready<=success;error<=!success;
                frame_sequence<=frame_sequence+1'b1;
            end
            if(psel && penable && pwrite && paddr==8 && pstrobe[0])begin
                if(pwdata[1])ready<=0;
                if(pwdata[0] && !busy && !ready)begin request<=~request;error<=0;end
            end
        end
    end
    always @* begin
        prdata=0;
        case(paddr)
            0:prdata=32'h41525531; // ARU1
            4:prdata={29'd0,error,ready,busy};
            12:prdata=frame_sequence;
            16:prdata={OUT_HEIGHT,OUT_WIDTH};
            default:if(mem_select && ready)prdata={24'd0,ram_data};
        endcase
    end
    // Both resets must be asserted together for a subsystem reset. Independently
    // resetting either side during a transaction is not supported.
endmodule
