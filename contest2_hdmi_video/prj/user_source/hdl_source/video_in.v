
// video_in：相机/ISP 侧的帧缓存写入器。
// 它把 128-bit 图像流先放入异步 FIFO，再在 DDR 时钟域写进四个循环槽位。
// 写指针只在新帧开始时切换，因此同一帧不会被拆到不同 DDR 槽。
// O_meta_* 是只读观察口，供 ua_frame_latency 给“写入的是哪个槽”打时间标签。
module video_in (
    input wire         I_rst_n,

    input wire         I_camera_clk,
    input wire         I_camera_frame_start,
    input wire         I_camera_valid,
    input wire[127:0]  I_camera_data,
    input wire         I_mipi_rx_error,

    input wire         I_ddr_clk,

    input wire         I_video_out_rd_busy,
    output wire        O_video_in_wr_busy,
    output reg[1:0]    O_video_out_rp,     ///读指针

    output reg         O_ddr_user_wr_en,
    output reg[24:0]   O_ddr_user_addr,
    output wire[127:0] O_ddr_user_wr_data,
    input wire         I_ddr_user_ready,
    output wire        O_meta_start,
    output wire [1:0]  O_meta_slot
);

    wire        S_fifo_rst;
    reg         S_camera_frame_start_extend; ///脉冲展宽，同步到ddr_clk时钟域
    reg[3:0]    S_extend_cnt;
    reg         S_camera_frame_start_d;
    reg         S_camera_frame_start_extend_1d;
    reg         S_camera_frame_start_extend_2d;
    reg         S_camera_frame_start_extend_3d;
    wire        S_frame_start;
    reg[1:0]    S_video_in_wp;       ///写指针
    wire[8:0]   S_fifo_rd_num;      
    wire        S_fifo_rd_en;   
    wire        S_fifo_rd_valid;
    wire[127:0] S_fifo_rd_data; 
    reg         S_ddr_wr_valid;
    reg[9:0]    S_ddr_wr_cnt;

    // The ISP marker is a side-band event, not a level.  Some camera/ISP
    // combinations hold it for more than one cycle while the first valid
    // word is being assembled.  Edge-detect it here so a held marker cannot
    // keep the asynchronous input FIFO in reset indefinitely.
    wire        S_camera_frame_start_pulse =
                    I_camera_frame_start & ~S_camera_frame_start_d;

    localparam IMAGE_BASE_ADDR_0 = 25'd0;
    localparam IMAGE_BASE_ADDR_1 = 25'd7000000;
    localparam IMAGE_BASE_ADDR_2 = 25'd14000000;
    localparam IMAGE_BASE_ADDR_3 = 25'd21000000;


    // 与 HX1P35A2026 官方 SC500 720P 例程保持一致：每帧都重新对齐写 FIFO。
    // 相机流、DDR 仲裁和 HDMI 读出没有反压，若不在帧边界丢弃残留字，
    // 一次短帧或仲裁抖动会把错位带到后续所有帧，表现为行尾回卷甚至双屏。
    // Include the global reset as well as the frame-boundary pulse so the
    // asynchronous FIFO starts from a known state before the first camera
    // frame is accepted.
    assign S_fifo_rst = (~I_rst_n) | S_camera_frame_start_extend_3d;

    // 官方仲裁只把正在组织的 240-word DDR burst 视为写忙。
    // 不把寄存后的 wr_en 尾拍继续并入 busy，避免挤占显示侧读 burst。
    assign O_video_in_wr_busy = S_ddr_wr_valid;

    w128_d512_fifo U_w128_d512_fifo(
        .rst        ( S_fifo_rst         ),   

        .clkw       ( I_camera_clk       ),     
        .we         ( I_camera_valid     ),
        .di         ( I_camera_data      ),
        .afull      (),
        .full_flag  (),
        .wrusedw    (),
 
        .clkr       ( I_ddr_clk          ),
        .re         ( S_fifo_rd_en       ), 
        .dout       ( O_ddr_user_wr_data ),  
        .rdusedw    ( S_fifo_rd_num      ),
        .valid      (), 
        .empty_flag (),
        .aempty     ()
    );


    // Reset the FIFO for a bounded interval at each frame boundary.  Keep the
    // marker detector and extension counter in one resettable process so no
    // power-up X state can leave the reset stretched forever.
    always @(posedge I_camera_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_camera_frame_start_d      <= 1'b0;
            S_camera_frame_start_extend <= 1'b0;
            S_extend_cnt                <= 4'd0;
        end else begin
            S_camera_frame_start_d <= I_camera_frame_start;
            if(S_camera_frame_start_pulse) begin
                S_camera_frame_start_extend <= 1'b1;
                S_extend_cnt                <= 4'd0;
            end else if(S_camera_frame_start_extend) begin
                if(S_extend_cnt == 4'd7) begin
                    S_camera_frame_start_extend <= 1'b0;
                    S_extend_cnt                <= 4'd0;
                end else begin
                    S_extend_cnt                <= S_extend_cnt + 1'b1;
                end
            end else begin
                S_camera_frame_start_extend <= 1'b0;
                S_extend_cnt                <= 4'd0;
            end
        end
    end


    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_camera_frame_start_extend_1d <= 1'b0;
            S_camera_frame_start_extend_2d <= 1'b0;
            S_camera_frame_start_extend_3d <= 1'b0;
        end else begin
            S_camera_frame_start_extend_1d <= S_camera_frame_start_extend;
            S_camera_frame_start_extend_2d <= S_camera_frame_start_extend_1d;
            S_camera_frame_start_extend_3d <= S_camera_frame_start_extend_2d;
        end
    end

    assign S_frame_start = ~S_camera_frame_start_extend_3d & S_camera_frame_start_extend_2d;
    // Observation only: exactly the slot used by the address-load case below.
    assign O_meta_start = S_frame_start;
    assign O_meta_slot = I_mipi_rx_error ? S_video_in_wp - 2'd1 : S_video_in_wp;

	/*
		如果前一帧图像有误少行了，那么地址回退为之前的，覆盖有问题的那帧图像
	*/
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_video_in_wp <= 'd0;
        else
            if(S_frame_start)
                begin
                    if(I_mipi_rx_error)
                        S_video_in_wp <= S_video_in_wp;
                    else
                        S_video_in_wp <= S_video_in_wp + 'd1;
                end
            else
                S_video_in_wp <= S_video_in_wp;
    end


    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            O_video_out_rp <= 'd0;
        else
            if(S_frame_start)
                begin
                    case(S_video_in_wp)
                        'd0: O_video_out_rp <= 'd2;
                        'd1: O_video_out_rp <= 'd3;
                        'd2: O_video_out_rp <= 'd0;
                        'd3: O_video_out_rp <= 'd1;
                    endcase
                end
            else
                O_video_out_rp <= O_video_out_rp;
    end

    /*
        fifo的深度是512，实际的深度是510，因此需要注意每次读出的长度避免为256，否则连续两次读写会引起fifo读空，丢失数据
    */
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_ddr_wr_valid <= 1'b0;
        else
            if(S_ddr_wr_valid && I_ddr_user_ready && S_ddr_wr_cnt == 'd239)
                S_ddr_wr_valid <= 1'b0;
            else if(S_fifo_rd_num >= 'd240 && (!I_video_out_rd_busy) && (!S_fifo_rst))
                S_ddr_wr_valid <= 1'b1;
            else
                S_ddr_wr_valid <= S_ddr_wr_valid;
    end

    always @(posedge I_ddr_clk) begin
        if(S_ddr_wr_valid)
            begin
                if(I_ddr_user_ready)
                    S_ddr_wr_cnt <= S_ddr_wr_cnt + 'd1;
                else
                    S_ddr_wr_cnt <= S_ddr_wr_cnt;
            end
        else
            S_ddr_wr_cnt <= 'd0;
    end

    assign S_fifo_rd_en = S_ddr_wr_valid & I_ddr_user_ready;

    always @(posedge I_ddr_clk) begin
        O_ddr_user_wr_en <= S_fifo_rd_en;
    end

	/*
		如果前一帧图像有误少行了，那么地址回退为之前的，覆盖有问题的那帧图像
	*/
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            O_ddr_user_addr <= 1'b0;
        else
            if(S_frame_start && (!I_mipi_rx_error))
                begin
                    case(S_video_in_wp)
                        'd0: O_ddr_user_addr <= IMAGE_BASE_ADDR_0;
                        'd1: O_ddr_user_addr <= IMAGE_BASE_ADDR_1;
                        'd2: O_ddr_user_addr <= IMAGE_BASE_ADDR_2;
                        'd3: O_ddr_user_addr <= IMAGE_BASE_ADDR_3;
                    endcase
                end
			else if(S_frame_start && I_mipi_rx_error)
				begin
                	case(S_video_in_wp)
                        'd0: O_ddr_user_addr <= IMAGE_BASE_ADDR_3;
                        'd1: O_ddr_user_addr <= IMAGE_BASE_ADDR_0;
                        'd2: O_ddr_user_addr <= IMAGE_BASE_ADDR_1;
                        'd3: O_ddr_user_addr <= IMAGE_BASE_ADDR_2;
                    endcase
                end
            else if(O_ddr_user_wr_en)
                O_ddr_user_addr <= O_ddr_user_addr + 'd8;
            else    
                O_ddr_user_addr <= O_ddr_user_addr;
    end

    
endmodule
