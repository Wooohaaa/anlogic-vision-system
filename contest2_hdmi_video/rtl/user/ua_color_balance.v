// ============================================================================
// ua_color_balance : AWB 后的轻量颜色偏移校正
//
// 官方 awb 已经负责 R/G/B 的自动增益。本模块不再复制一套除法器，而是
// 统计当前帧相对 G 通道的平均偏差，在下一帧对 R/B 做小步进、有限幅度的
// offset 修正。这样可以补偿传感器/板级造成的蓝黄或红绿整体偏色，同时不会
// 把物体本身的色相大幅拉回灰色。
//
// 资源约束：只使用帧级累加器、比较器和移位，没有帧 RAM、DSP 或除法器。
// I_tuser 必须是与 I_tvalid 对齐的真实帧首；输出为同拍透传，避免引入
// 额外像素位移。当前 ISP 已在 isp_top_user 中完成 AWB 帧首对齐。
// ============================================================================
module ua_color_balance #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    parameter ENABLE     = 1
)(
    input             I_clk,
    input             I_rst_n,
    input             I_tlast,
    input             I_tuser,
    input      [95:0] I_tdata,
    input             I_tvalid,
    output            I_tready,
    output            O_tlast,
    output            O_tuser,
    output     [95:0] O_tdata,
    output            O_tvalid,
    input             O_tready
);

    // Four RGB888 pixels are present in each 96-bit beat.  A 30-bit signed
    // accumulator is ample for the worst case 1280x720 frame difference.
    localparam integer SUM_W = 30;
    localparam integer AVG_SHIFT = 20;

    reg signed [SUM_W-1:0] sum_gr;
    reg signed [SUM_W-1:0] sum_gb;
    reg signed [5:0]       offset_r;
    reg signed [5:0]       offset_b;
    reg                    frame_seen;

    wire [7:0] r0 = I_tdata[95:88];
    wire [7:0] g0 = I_tdata[87:80];
    wire [7:0] b0 = I_tdata[79:72];
    wire [7:0] r1 = I_tdata[71:64];
    wire [7:0] g1 = I_tdata[63:56];
    wire [7:0] b1 = I_tdata[55:48];
    wire [7:0] r2 = I_tdata[47:40];
    wire [7:0] g2 = I_tdata[39:32];
    wire [7:0] b2 = I_tdata[31:24];
    wire [7:0] r3 = I_tdata[23:16];
    wire [7:0] g3 = I_tdata[15:8];
    wire [7:0] b3 = I_tdata[7:0];

    wire [9:0] beat_r = {2'b00,r0} + {2'b00,r1} +
                        {2'b00,r2} + {2'b00,r3};
    wire [9:0] beat_g = {2'b00,g0} + {2'b00,g1} +
                        {2'b00,g2} + {2'b00,g3};
    wire [9:0] beat_b = {2'b00,b0} + {2'b00,b1} +
                        {2'b00,b2} + {2'b00,b3};
    wire signed [11:0] beat_gr = $signed({2'b00,beat_g}) -
                                  $signed({2'b00,beat_r});
    wire signed [11:0] beat_gb = $signed({2'b00,beat_g}) -
                                  $signed({2'b00,beat_b});

    function [5:0] F_target;
        input signed [SUM_W-1:0] sum_value;
        reg signed [SUM_W-1:0] q;
        begin
            // The exact pixel count is not needed for a colour *difference*;
            // a power-of-two scale keeps this path divider-free.  The final
            // clamp deliberately limits correction to a gentle +/-8 codes.
            q = sum_value >>> AVG_SHIFT;
            if (q > 8)
                F_target = 6'sd8;
            else if (q < -8)
                F_target = -6'sd8;
            else
                F_target = q[5:0];
        end
    endfunction

    function [5:0] F_step;
        input signed [5:0] current_value;
        input signed [5:0] target_value;
        reg signed [6:0] c;
        reg signed [6:0] t;
        begin
            // Move at most one code per frame.  This prevents visible colour
            // pumping when the scene contains a large coloured object.
            c = current_value;
            t = target_value;
            if (t > c + 1)
                F_step = current_value + 1'b1;
            else if (t < c - 1)
                F_step = current_value - 1'b1;
            else
                F_step = target_value;
        end
    endfunction

    // The correction is bounded to +/-8.  A 10-bit signed sum therefore
    // contains enough information to saturate from its two upper bits:
    // 10'b11xxxxxxx is negative, 10'b01xxxxxxx is above 255, and 00 is in
    // range.  This avoids three full-width comparators per pixel and leaves
    // the green channel as a literal pass-through.
    function [7:0] F_add_offset;
        input [7:0] c;
        input signed [5:0] offset;
        reg signed [9:0] value;
        begin
            value = $signed({2'b00,c}) + $signed({{4{offset[5]}},offset});
            if (value[9])
                F_add_offset = 8'd0;
            else if (value[8])
                F_add_offset = 8'hff;
            else
                F_add_offset = value[7:0];
        end
    endfunction

    function [23:0] F_apply_pixel;
        input [23:0] p;
        input signed [5:0] r_offset;
        input signed [5:0] b_offset;
        begin
            F_apply_pixel = {F_add_offset(p[23:16], r_offset),
                             p[15:8],
                             F_add_offset(p[7:0], b_offset)};
        end
    endfunction

    // This module never buffers a beat.  The surrounding video path is
    // continuously ready, and propagating ready keeps the interface legal for
    // reduced-resolution simulations as well.
    assign I_tready = O_tready;
    assign O_tlast  = I_tlast;
    assign O_tuser  = I_tuser;
    assign O_tvalid = I_tvalid;
    assign O_tdata  = (ENABLE == 0) ? I_tdata : {
        F_apply_pixel(I_tdata[95:72], offset_r, offset_b),
        F_apply_pixel(I_tdata[71:48], offset_r, offset_b),
        F_apply_pixel(I_tdata[47:24], offset_r, offset_b),
        F_apply_pixel(I_tdata[23:0],  offset_r, offset_b)
    };

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sum_gr    <= {SUM_W{1'b0}};
            sum_gb    <= {SUM_W{1'b0}};
            offset_r  <= 6'sd0;
            offset_b  <= 6'sd0;
            frame_seen <= 1'b0;
        end else if (ENABLE != 0) begin
            if (I_tvalid && I_tuser) begin
                // At a new frame, publish the previous frame's estimate and
                // start accumulating this first beat immediately.
                if (frame_seen) begin
                    offset_r <= F_step(offset_r, F_target(sum_gr));
                    offset_b <= F_step(offset_b, F_target(sum_gb));
                end
                frame_seen <= 1'b1;
                sum_gr <= {{(SUM_W-12){beat_gr[11]}}, beat_gr};
                sum_gb <= {{(SUM_W-12){beat_gb[11]}}, beat_gb};
            end else if (I_tvalid) begin
                sum_gr <= sum_gr + {{(SUM_W-12){beat_gr[11]}}, beat_gr};
                sum_gb <= sum_gb + {{(SUM_W-12){beat_gb[11]}}, beat_gb};
            end
        end
    end

endmodule
