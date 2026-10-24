`ifndef UA_FRAME_LATENCY_V
`define UA_FRAME_LATENCY_V

// RAW frame-start to HDMI frame-start latency, 1 ms resolution.
// Four slot records follow actual video_in/video_out address-load events.
// No pixel data, DDR addressing, or traffic arbitration is modified.
// Timer wraps at 65536 ms; ages >=32768 ms are invalid, not negative delays.
// 阅读入口：计时器在 HDMI 域；RAW 帧首在相机域捕获时间；DDR 域将时间对应
// 到四个帧槽；最后 HDMI 域在显示帧首相减。跨域用 toggle/mailbox，不直接读
// 多位异步计数器。
module ua_frame_latency #(
    parameter integer PIXEL_HZ = 75000000,
    // The ISP packs four RGB888 pixels (96 bits) into three 128-bit words.
    // For the active 1280x720 mode: 1280*720*24/128 = 172800 writes/frame.
    parameter integer FRAME_WORDS = 172800
)(
    input I_rst_n,
    input I_camera_clk, input I_raw_start,
    input I_ddr_clk, input I_write_start, input [1:0] I_write_slot,
    input I_write_word, input I_read_start, input [1:0] I_read_slot,
    input I_pixel_clk, input I_display_start,
    output reg O_valid, output reg [15:0] O_delay_ms
);
    reg [15:0] ms_count, ms_gray;
    reg [31:0] divider;
    wire [15:0] next_ms = ms_count + 16'd1;
    always @(posedge I_pixel_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            divider <= 0; ms_count <= 0; ms_gray <= 0;
        end else if (divider == PIXEL_HZ/1000-1) begin
            divider <= 0; ms_count <= next_ms;
            ms_gray <= (next_ms >> 1) ^ next_ms;
        end else divider <= divider + 1'b1;
    end
    function [15:0] ungray;
        input [15:0] g;
        integer k;
        begin
            ungray[15] = g[15];
            for (k=14;k>=0;k=k-1) ungray[k] = ungray[k+1] ^ g[k];
        end
    endfunction
    // Registered Gray timer: only one bit changes per millisecond. Source
    // update interval is much longer than the complete synchronizer latency.
    (* ASYNC_REG = "TRUE" *) reg [15:0] gray_c0, gray_c1;
    reg [15:0] capture_ms;
    reg capture_toggle;
    always @(posedge I_camera_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            gray_c0 <= 0; gray_c1 <= 0; capture_ms <= 0; capture_toggle <= 0;
        end else begin
            gray_c0 <= ms_gray; gray_c1 <= gray_c0;
            if (I_raw_start) begin
                capture_ms <= ungray(gray_c1);
                capture_toggle <= ~capture_toggle;
            end
        end
    end
    // Bundled capture mailbox: capture_ms is held until the next RAW frame.
    // Three control stages give the two data stages an extra settling cycle.
    (* ASYNC_REG = "TRUE" *) reg [15:0] cap_d0, cap_d1;
    (* ASYNC_REG = "TRUE" *) reg [2:0] cap_sync;
    reg cap_seen, capture_fresh;
    reg [15:0] latest_capture;
    wire capture_event = cap_sync[2] != cap_seen;
    reg [15:0] slot_ms [0:3];
    reg [3:0] slot_valid;
    reg [1:0] writing_slot;
    reg writing_valid;
    reg [31:0] word_count;
    // Read-result mailbox with acknowledgement: payload held until accepted.
    reg [16:0] read_payload;
    reg read_req;
    reg read_ack;
    (* ASYNC_REG = "TRUE" *) reg [1:0] ack_sync;
    integer s;
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            cap_d0 <= 0; cap_d1 <= 0; cap_sync <= 0; cap_seen <= 0;
            latest_capture <= 0; capture_fresh <= 0;
            slot_valid <= 0; writing_slot <= 0; writing_valid <= 0;
            word_count <= 0; read_payload <= 0; read_req <= 0; ack_sync <= 0;
            for (s=0;s<4;s=s+1) slot_ms[s] <= 0;
        end else begin
            cap_d0 <= capture_ms; cap_d1 <= cap_d0;
            cap_sync <= {cap_sync[1:0],capture_toggle};
            ack_sync <= {ack_sync[0],read_ack};
            if (capture_event) begin
                cap_seen <= cap_sync[2]; latest_capture <= cap_d1;
                capture_fresh <= 1;
            end
            if (I_write_start) begin
                slot_ms[I_write_slot] <= capture_event ? cap_d1 : latest_capture;
                slot_valid[I_write_slot] <= 0;
                writing_slot <= I_write_slot;
                writing_valid <= capture_fresh || capture_event;
                capture_fresh <= 0;
                word_count <= 0;
            end else if (I_write_word && word_count < FRAME_WORDS) begin
                word_count <= word_count + 1'b1;
                if (word_count == FRAME_WORDS-1)
                    slot_valid[writing_slot] <= writing_valid;
            end
            if (I_read_start && read_req == ack_sync[1]) begin
                read_payload <= {slot_valid[I_read_slot] &&
                    !(I_write_start && I_write_slot == I_read_slot), slot_ms[I_read_slot]};
                read_req <= ~read_req;
            end
        end
    end
    (* ASYNC_REG = "TRUE" *) reg [2:0] req_sync;
    (* ASYNC_REG = "TRUE" *) reg [16:0] payload_p0, payload_p1;
    reg [16:0] selected;
    reg selected_fresh;
    wire result_event = req_sync[2] != read_ack;
    wire [16:0] chosen = result_event ? payload_p1 : selected;
    wire [15:0] age_ms = ms_count - chosen[15:0];
    always @(posedge I_pixel_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            req_sync <= 0; payload_p0 <= 0; payload_p1 <= 0;
            read_ack <= 0; selected <= 0; selected_fresh <= 0;
            O_valid <= 0; O_delay_ms <= 0;
        end else begin
            req_sync <= {req_sync[1:0],read_req};
            payload_p0 <= read_payload; payload_p1 <= payload_p0;
            if (result_event) begin
                read_ack <= req_sync[2]; selected <= payload_p1;
                selected_fresh <= 1;
            end
            if (I_display_start) begin
                O_valid <= (selected_fresh || result_event) && chosen[16] && !age_ms[15];
                O_delay_ms <= age_ms;
                selected_fresh <= 0;
            end
        end
    end
endmodule

`endif
