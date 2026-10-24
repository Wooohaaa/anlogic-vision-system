// 1280x720 red-circle result -> 320x180 -> coherent 50MHz UART1 snapshot.
// Held mailbox + request/acknowledge; no independently synchronized data bits.
// Three camera results acquire a target; any rejected result revokes it.
module ua_red_ball_uart #(
    parameter integer BIT_CYCLES=434, FRAME_CYCLES=1000000,
    parameter integer STALE_POLLS=5
)(
    input src_clk, dst_clk, rst_n, enable, frame_valid, target_valid,
    input [1:0] target_shape,
    input [10:0] target_x,target_y,xmin,xmax,ymin,ymax,
    output reg tx
);
    reg request, acknowledge;
    (* ASYNC_REG="TRUE" *) reg req_meta,req_sync,ack_meta,ack_sync;
    reg [1:0] confirmed;
    reg [15:0] camera_sequence;
    reg [22:0] latest;
    reg [38:0] mailbox;
    wire [11:0] width_px={1'b0,xmax}-{1'b0,xmin}+12'd1;
    wire [11:0] height_px={1'b0,ymax}-{1'b0,ymin}+12'd1;
    wire accepted=target_valid && target_shape==0 &&
        target_x<1280 && target_y<720 && xmax>=xmin && ymax>=ymin &&
        xmax<1280 && ymax<720 && width_px>=12 && height_px>=12 &&
        ({1'b0,width_px}<=({1'b0,height_px}<<1)) &&
        ({1'b0,height_px}<=({1'b0,width_px}<<1));
    always @(posedge src_clk or negedge rst_n) begin
        if(!rst_n) begin
            req_meta<=0;req_sync<=0;acknowledge<=0;mailbox<=0;
            confirmed<=0;camera_sequence<=0;latest<=0;
        end else begin
            req_meta<=request;req_sync<=req_meta;
            if(frame_valid) begin
                camera_sequence<=camera_sequence+16'd1;
                if(accepted) begin
                    if(confirmed<3) confirmed<=confirmed+1'b1;
                    latest<={confirmed>=2,target_y,target_x};
                end else begin confirmed<=0;latest<=0;end
            end
            if(req_sync!=acknowledge) begin
                mailbox<={camera_sequence,latest};
                acknowledge<=req_sync;
            end
        end
    end
    localparam POLL_W=(FRAME_CYCLES<=1)?1:$clog2(FRAME_CYCLES);
    localparam BIT_W=(BIT_CYCLES<=1)?1:$clog2(BIT_CYCLES);
    localparam STALE_CAP=(STALE_POLLS>255)?255:((STALE_POLLS<1)?1:STALE_POLLS);
    localparam STALE_W=(STALE_CAP<2)?1:$clog2(STALE_CAP+1);
    reg [POLL_W-1:0] poll_count;
    reg [15:0] previous_sequence;
    reg [STALE_W-1:0] stale_count;
    reg [7:0] packet_seq;
    reg seen_sequence;
    reg [2:0] state;
    reg [71:0] payload;
    reg [3:0] byte_index,bit_index;
    reg [BIT_W-1:0] bit_count;
    wire [7:0] data_byte=payload[byte_index*8 +: 8];
    wire fresh=(mailbox[38:23]!=previous_sequence)||!seen_sequence;
    wire live=mailbox[22] && (fresh || stale_count<STALE_POLLS-1);
    always @(posedge dst_clk or negedge rst_n) begin
        if(!rst_n) begin
            request<=0;ack_meta<=0;ack_sync<=0;poll_count<=0;
            previous_sequence<=0;stale_count<=0;seen_sequence<=0;
            packet_seq<=0;state<=0;payload<=0;byte_index<=0;bit_index<=0;
            bit_count<=0;tx<=1;
        end else begin
            ack_meta<=acknowledge;ack_sync<=ack_meta;
            if(!enable) begin
                // Finish outstanding CDC transaction before issuing another.
                tx<=1;state<=0;poll_count<=0;seen_sequence<=0;stale_count<=0;
            end else case(state)
                0: if(poll_count==FRAME_CYCLES-1) begin
                    if(ack_sync==request) begin request<=~request;state<=1;poll_count<=0;end
                end else poll_count<=poll_count+1'b1;
                1: if(ack_sync==request) state<=2; // extra settling cycle
                2: begin
                    previous_sequence<=mailbox[38:23];seen_sequence<=1;
                    if(fresh) stale_count<=0;
                    else if(stale_count<STALE_CAP) stale_count<=stale_count+1'b1;
                    payload<={8'h5b,packet_seq,{7'd0,live},
                        7'd0,mailbox[21:13],7'd0,mailbox[10:2],8'd9,8'h2c};
                    packet_seq<=packet_seq+1'b1;
                    byte_index<=0;bit_index<=0;bit_count<=0;state<=3;tx<=0;
                end
                3: if(bit_count==BIT_CYCLES-1) begin
                    bit_count<=0;
                    if(bit_index<8) begin tx<=data_byte[bit_index];bit_index<=bit_index+1'b1;end
                    else if(bit_index==8) begin tx<=1;bit_index<=9;end
                    else if(byte_index==8) begin state<=0;tx<=1;end
                    else begin byte_index<=byte_index+1'b1;bit_index<=0;tx<=0;end
                end else bit_count<=bit_count+1'b1;
                default: begin state<=0;tx<=1;end
            endcase
        end
    end
endmodule
