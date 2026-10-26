
// ============================================================================
// design_top_user : 本工程的“总装配图”，不在这里实现具体图像算法。
// 阅读方法：先看 u_xxx 实例和 S_* 连线，再回到被实例化的子模块。
// 主路径：MIPI/CSI -> RAW10 -> isp_top_user -> video_in -> DDR
//         -> video_out -> hdmi_mixer_user -> hdmi_tx。
// 时钟域：S_csi_rx_clk（相机/ISP）、S_ddr_clk（帧缓冲）、
//         S_hdmi_pixel_clk（显示）；跨域必须经过 FIFO、2FF 或握手。
// 按键属于低速配置输入：在稳定的 S_100m_clk 域完成同步/消抖；KEY1/KEY2
// 控制模式，KEY3 开关白平衡，KEY4 开关自动曝光与模拟增益。
// ============================================================================
// TD 6.2.1/GUI may omit a newly added Verilog entry when regenerating its
// synthesis source list. The latency monitor is an established guarded include;
// the switch controller and seven-segment scanner are embedded below because
// the GUI run directory does not resolve new includes relative to this source.
`include "ua_frame_latency.v"

// Local copy used by the top-level assembly. Keeping this small controller in
// the guaranteed top source removes any dependency on TD's generated file list
// and include search path. Inputs are synchronized and must remain unchanged
// for DEBOUNCE_CYCLES before the complete four-switch bank is committed.
module ua_detect_switch_ctrl_embedded #(
    parameter integer WIDTH = 4,
    parameter integer DEBOUNCE_CYCLES = 100000,
    parameter integer SW_ACTIVE_LOW = 1
)(
    input  wire             I_clk,
    input  wire             I_rst_n,
    input  wire [WIDTH-1:0] I_switch,
    output reg  [WIDTH-1:0] O_enable
);
    localparam [WIDTH-1:0] RELEASED_VALUE =
        (SW_ACTIVE_LOW != 0) ? {WIDTH{1'b1}} : {WIDTH{1'b0}};

    reg [WIDTH-1:0] switch_sync0;
    reg [WIDTH-1:0] switch_sync1;
    reg [WIDTH-1:0] candidate;
    reg [31:0]      stable_count;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            switch_sync0 <= RELEASED_VALUE;
            switch_sync1 <= RELEASED_VALUE;
        end else begin
            switch_sync0 <= I_switch;
            switch_sync1 <= switch_sync0;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            candidate    <= RELEASED_VALUE;
            stable_count <= 32'd0;
            O_enable     <= {WIDTH{1'b0}};
        end else if (switch_sync1 != candidate) begin
            candidate    <= switch_sync1;
            stable_count <= 32'd0;
        end else if (stable_count < DEBOUNCE_CYCLES - 1) begin
            stable_count <= stable_count + 32'd1;
        end else if (SW_ACTIVE_LOW != 0) begin
            O_enable <= ~candidate;
        end else begin
            O_enable <= candidate;
        end
    end
endmodule

// The standalone ua_exposure_seg6.v is kept in the maintained source list for
// simulation and fresh TD projects.  TD's existing run directory can however
// omit that file before elaboration, so this small, uniquely named copy is
// intentionally defined in the guaranteed top source.  It has the same
// active-low scan convention and 00..15 decoder as the standalone module.
module ua_exposure_seg6_embedded #(
    parameter integer SCAN_HALF_CYCLES = 50000
)(
    input  wire       I_clk,
    input  wire       I_rst_n,
    input  wire [3:0] I_level,
    output reg  [5:0] O_seg_sel,
    output reg  [7:0] O_seg_led
);
    localparam [31:0] SCAN_LIMIT =
        (SCAN_HALF_CYCLES < 1) ? 32'd0 : SCAN_HALF_CYCLES - 1;
    reg [31:0] scan_count;
    reg        scan_digit;
    wire [3:0] tens_digit  = (I_level >= 4'd10) ? 4'd1 : 4'd0;
    wire [3:0] units_digit = (I_level >= 4'd10) ?
                              (I_level - 4'd10) : I_level;

    function [7:0] hex7seg;
        input [3:0] value;
        begin
            case (value)
                4'd0: hex7seg = 8'hc0;
                4'd1: hex7seg = 8'hf9;
                4'd2: hex7seg = 8'ha4;
                4'd3: hex7seg = 8'hb0;
                4'd4: hex7seg = 8'h99;
                4'd5: hex7seg = 8'h92;
                4'd6: hex7seg = 8'h82;
                4'd7: hex7seg = 8'hf8;
                4'd8: hex7seg = 8'h80;
                4'd9: hex7seg = 8'h90;
                default: hex7seg = 8'hff;
            endcase
        end
    endfunction

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            scan_count <= 32'd0;
            scan_digit <= 1'b0;
            O_seg_sel  <= 6'b111111;
            O_seg_led  <= 8'hff;
        end else if (scan_count >= SCAN_LIMIT) begin
            scan_count <= 32'd0;
            scan_digit <= ~scan_digit;
            if (scan_digit == 1'b0) begin
                O_seg_sel <= 6'b111110;
                O_seg_led <= hex7seg(tens_digit);
            end else begin
                O_seg_sel <= 6'b111101;
                O_seg_led <= hex7seg(units_digit);
            end
        end else begin
            scan_count <= scan_count + 32'd1;
            if (scan_digit == 1'b0) begin
                O_seg_sel <= 6'b111101;
                O_seg_led <= hex7seg(units_digit);
            end else begin
                O_seg_sel <= 6'b111110;
                O_seg_led <= hex7seg(tens_digit);
            end
        end
    end
endmodule

// Shared post-ISP diagnostic. Enable is already synchronized by the existing
// switch bank; commit only at VS so a displayed frame cannot change halfway.
// No new latency: both consumers see the same combinational pattern, using
// the existing aligned DE/VS. Camera/ISP/DDR continue behind the pattern.
module ua_shared_colour_diagnostic_embedded (
    input wire I_clk, I_rst_n, I_enable, I_vs, I_de,
    input wire [23:0] I_hdmi_rgb, I_clean_rgb,
    output wire [23:0] O_hdmi_rgb, O_clean_rgb
);
    reg vs_d,de_d,enabled;
    reg [10:0] x;
    reg [9:0] y;
    reg [23:0] pattern;
    reg [7:0] gray;
    always @(posedge I_clk or negedge I_rst_n) begin
      if(!I_rst_n) begin vs_d<=0;de_d<=0;enabled<=0;x<=0;y<=0;end
      else begin
        vs_d<=I_vs;de_d<=I_de;
        if(I_vs && !vs_d) begin enabled<=I_enable;x<=0;y<=0;end
        else if(I_de) x<=x+11'd1;
        else begin
          x<=0;
          if(de_d) y<=y+10'd1;
        end
      end
    end
    always @* begin
      pattern=24'd0;gray=0;
      if(y<10'd240) begin
        if(x<11'd160) pattern=24'hff0000;
        else if(x<11'd320) pattern=24'h00ff00;
        else if(x<11'd480) pattern=24'h0000ff;
        else if(x<11'd640) pattern=24'hffff00;
        else if(x<11'd800) pattern=24'h00ffff;
        else if(x<11'd960) pattern=24'hff00ff;
        else if(x<11'd1120) pattern=24'hffffff;
        else pattern=24'h000000;
      end else begin
        // Middle: 256 exact gray codes, 4 columns/code, then white reference.
        // Bottom: 16 near-black codes, 64 columns/code, then white reference.
        if(x>=11'd1024) gray=8'hff;
        else if(y<10'd480) gray=x[9:2];
        else gray={4'd0,x[9:6]};
        pattern={gray,gray,gray};
      end
    end
    assign O_hdmi_rgb=enabled ? (I_de ? pattern : 24'd0) : I_hdmi_rgb;
    assign O_clean_rgb=enabled ? (I_de ? pattern : 24'd0) : I_clean_rgb;
endmodule

// Debounced button-level toggle, once per press. Reset policy is selectable.
module ua_button_toggle_embedded #(parameter INITIAL_ENABLE=1'b1)(input I_clk,I_rst_n,I_button,output reg O_enable);
 reg button_d;
 always @(posedge I_clk or negedge I_rst_n) begin
  if(!I_rst_n) begin button_d<=0;O_enable<=INITIAL_ENABLE;end
  else begin
   button_d<=I_button;
   if(I_button && !button_d) O_enable<=~O_enable;
  end
 end
endmodule

// Read-only exposure telemetry. Shared serial decimal conversion avoids dividers.
// Fixed six digits: exposure half-lines (4), rounded analogue gain (2).
module ua_ae_legacy_panel_embedded #(
 parameter integer SCAN_CYCLES=50000
)(
 input I_clk,I_source_clk,I_rst_n,
 input [15:0] I_ae,I_ag,
 output reg [5:0] O_seg_sel,output reg [7:0] O_seg_led
);
 localparam integer SW=(SCAN_CYCLES<2)?1:$clog2(SCAN_CYCLES);
 localparam [SW-1:0] SL=(SCAN_CYCLES<2)?1:SCAN_CYCLES-1;
 reg req,req_meta,req_sync,ack,ack_meta,ack_sync;
 reg [31:0] packet;
 reg [15:0] binary;
 reg [19:0] bcd,adjusted;
 reg [15:0] exposure_bcd,exposure_work,scan_exposure;
 reg [11:0] gain_bcd,scan_gain;
 reg [15:0] gain_tenths;
 reg [4:0] bit_count;
 reg [1:0] conversion;
 reg [SW-1:0] scan_count;
 reg [2:0] digit;
 reg [3:0] value;
 reg [7:0] decoded;
 integer n;
 wire [19:0] shifted={adjusted[18:0],binary[15]};
 wire [6:0] offset=(packet[15:0]<16'd16)?7'd0:
                         (packet[15:0]>16'd143)?7'd127:packet[6:0]-7'd16;
 wire [11:0] gain_units=({7'd0,offset[4:0]}+12'd32)<<offset[6:5];
 wire [11:0] gain_rounded=(gain_units+12'd16)>>5;
 function [7:0] decimal7seg;
 input [3:0] v;
 begin case(v)
  0:decimal7seg=8'hc0;1:decimal7seg=8'hf9;2:decimal7seg=8'ha4;
  3:decimal7seg=8'hb0;4:decimal7seg=8'h99;5:decimal7seg=8'h92;
  6:decimal7seg=8'h82;7:decimal7seg=8'hf8;8:decimal7seg=8'h80;
  9:decimal7seg=8'h90;default:decimal7seg=8'hff;
 endcase end endfunction
 always @(posedge I_source_clk or negedge I_rst_n) begin
  if(!I_rst_n) begin req_meta<=0;req_sync<=0;ack<=0;packet<={16'd1990,16'd16};end
  else begin
   req_meta<=req;req_sync<=req_meta;
   if(req_sync!=ack) begin packet<={I_ae,I_ag};ack<=req_sync;end
  end
 end
 always @* begin
  adjusted=bcd;
  for(n=0;n<5;n=n+1)
   if(bcd[n*4+:4]>=5) adjusted[n*4+:4]=bcd[n*4+:4]+4'd3;
 end
 always @(posedge I_clk or negedge I_rst_n) begin
  if(!I_rst_n) begin
   req<=0;ack_meta<=0;ack_sync<=0;conversion<=0;binary<=0;bcd<=0;
   bit_count<=0;gain_tenths<=1;exposure_work<=16'h1990;
   exposure_bcd<=16'h1990;gain_bcd<=12'h001;
  end else begin
   ack_meta<=ack;ack_sync<=ack_meta;
   case(conversion)
    0:if(ack_sync==req) begin
     binary<=packet[31:16];gain_tenths<={4'd0,gain_rounded};
     bcd<=0;bit_count<=0;conversion<=1;
    end
    1,2:begin
     bcd<=shifted;binary<={binary[14:0],1'b0};bit_count<=bit_count+1'b1;
     if(bit_count==15) begin
      if(conversion==1) begin
       exposure_work<=shifted[15:0];binary<=gain_tenths;
       bcd<=0;bit_count<=0;conversion<=2;
      end else begin
       exposure_bcd<=exposure_work;gain_bcd<=shifted[11:0];
       req<=~req;conversion<=0;
      end
     end
    end
    default:conversion<=0;
   endcase
  end
 end
 always @* begin
  value=4'hf;
  case(digit)
   0:value=scan_exposure[15:12];1:value=scan_exposure[11:8];
   2:value=scan_exposure[7:4];3:value=scan_exposure[3:0];
   4:value=scan_gain[7:4];5:value=scan_gain[3:0];
  endcase
  decoded=decimal7seg(value);
  if(digit==3) decoded[7]=0; // separator, not exposure decimal units
 end
 always @(posedge I_clk or negedge I_rst_n) begin
  if(!I_rst_n) begin
   scan_count<=0;digit<=0;
   scan_exposure<=16'h1990;scan_gain<=12'h001;
   O_seg_sel<=6'b111111;O_seg_led<=8'hff;
  end else begin
   if(scan_count>=SL) begin
    scan_count<=0;digit<=(digit==5)?0:digit+1'b1;
    O_seg_sel<=6'b111111;O_seg_led<=8'hff;
    if(digit==5) begin
     scan_exposure<=exposure_bcd;scan_gain<=gain_bcd;
    end
   end else begin
    scan_count<=scan_count+1'b1;
    O_seg_sel<=~(6'b000001<<digit);O_seg_led<=decoded;
   end
  end
 end
endmodule

// Fixed panel: left two digits = composite control index (00..31),
// rightmost digit = KEY4 enable (0/1); the middle three digits are blank.
module ua_ae_panel_embedded #(parameter integer SCAN_CYCLES=50000)(
 input I_clk,I_source_clk,I_rst_n,input [4:0] I_index,input I_enable,
 output reg [5:0] O_seg_sel,output reg [7:0] O_seg_led
);
 localparam integer CW=(SCAN_CYCLES<2)?1:$clog2(SCAN_CYCLES);
 reg req,rm,rs,ack,am,as;
 reg [5:0] packet,snapshot,scan;
 reg [CW-1:0] count;
 reg [2:0] digit;
 reg [3:0] val,tens,units;
 function [7:0] seg;
 input [3:0] v;
 begin case(v)
 0:seg=8'hc0;1:seg=8'hf9;2:seg=8'ha4;3:seg=8'hb0;4:seg=8'h99;
 5:seg=8'h92;6:seg=8'h82;7:seg=8'hf8;8:seg=8'h80;9:seg=8'h90;
 default:seg=8'hff;endcase end endfunction
 always @(posedge I_source_clk or negedge I_rst_n)
  if(!I_rst_n)begin rm<=0;rs<=0;ack<=0;packet<=6'b101111;end
  else begin rm<=req;rs<=rm;
   if(rs!=ack)begin packet<={I_enable,I_index};ack<=rs;end
  end
 always @(posedge I_clk or negedge I_rst_n)
  if(!I_rst_n)begin req<=0;am<=0;as<=0;snapshot<=6'b101111;end
  else begin am<=ack;as<=am;
   if(as==req)begin snapshot<=packet;req<=~req;end
  end
 always @*begin
  tens=(scan[4:0]>=30)?3:(scan[4:0]>=20)?2:(scan[4:0]>=10)?1:0;
  units=scan[4:0]-tens*4'd10;
  val=4'hf;
  case(digit)0:val=tens;1:val=units;5:val={3'd0,scan[5]};endcase
 end
 always @(posedge I_clk or negedge I_rst_n)
  if(!I_rst_n)begin count<=0;digit<=0;scan<=6'b101111;O_seg_sel<=63;O_seg_led<=255;end
  else if(count==SCAN_CYCLES-1)begin
   count<=0;digit<=(digit==5)?0:digit+1'b1;O_seg_sel<=63;O_seg_led<=255;
   if(digit==5)scan<=snapshot;
  end else begin count<=count+1'b1;O_seg_sel<=~(6'b1<<digit);O_seg_led<=seg(val);end
endmodule

module design_top_user (
    input wire        I_sys_clk,
    input wire        I_mcu_uart_rx,
    output wire       O_mcu_uart_tx,
    output wire [1:0] O_motor_step,
    output wire [1:0] O_motor_dir,
    output wire [1:0] O_motor_awake,
    output wire [1:0] O_motor_reset_n,
      
    output wire       O_cam_scl,
    inout  wire       IO_cam_sda,
    output wire       O_cam_24m,
    output wire       O_cam_rst,
      
    input wire [3:0]  I_button,
    // 官方原理图中的 4 bit Switch（key[4]..key[7]），低电平表示 ON：
    // SW1 同时开关 motion 与颜色/形状，SW2 开关 ArUco，SW3 预留，SW4 数字识别。
    // I_button 是 8_key_sw 示例中的四个瞬时按键 KEY1..KEY4。
    input wire [3:0]  I_detect_sw,

    // 6-digit active-low seven-segment display from the board example.
    // Fixed composite gain index 00..31 plus a separate KEY4 enable 0/1.
    output wire [5:0]  O_seg_sel,
    output wire [7:0]  O_seg_led,

    // HDMI-only build: no external video transport.

    output wire       O_tmds_ch0_p,
    output wire       O_tmds_ch1_p,
    output wire       O_tmds_ch2_p,
    output wire       O_tmds_clk_p,

    inout wire        IO_rx_clk_pad_n, 
    inout wire        IO_rx_clk_pad_p, 
    inout wire[3:0]   IO_rx_data_pad_n,
    inout wire[3:0]   IO_rx_data_pad_p,

    output wire[12:0] ddr_addr,
    output wire[ 1:0] ddr_ba,
    output wire[ 0:0] ddr_cke,
    output wire[ 0:0] ddr_odt,
    output wire[ 0:0] ddr_cs_n,
    output wire       ddr_ras_n,
    output wire       ddr_cas_n,
    output wire       ddr_we_n,
    output wire[ 0:0] ddr_ck_p,
    output wire[ 0:0] ddr_ck_n,
    inout wire[1:0]   ddr_dm,
    inout wire[15:0]  ddr_dq,
    inout wire[1:0]   ddr_dqs_p,
    inout wire[1:0]   ddr_dqs_n   
);

    // 2026 SC500 factory mode and HDMI path are 1280x720@60.  Keep the
    // geometry in one place so the camera unpacker, ISP observers, DDR video
    // path, VTC and OSD cannot silently drift back to the legacy 1024x600
    // profile.
    localparam integer IMG_WIDTH  = 1280;
    localparam integer IMG_HEIGHT = 720;
    // Product feature switches.  The TD flow now loads the board pin/DDR/FIFO
    // ADC and SDC files, so the complete feature path is checked rather than
    // hiding blocks behind a diagnostic-only configuration.
    localparam integer ENABLE_AE_DIAG = 1;
    localparam integer ENABLE_AE_CUSTOM = 1;
    // KEY4 enables/disables frame-based automatic exposure and analogue gain.
    localparam integer FORCE_AE_MAX = 0;
    localparam integer ENABLE_OSD_DIAG = 1;
    localparam integer ENABLE_LAT_DIAG = 1;
    // KEY1/KEY2 select ISP modes; KEY3 toggles automatic white balance.
    localparam integer ENABLE_MODE_DIAG = 1;
    // The updated 720p sensor already emits a correctly framed RAW10 stream.
    // Keep the legacy crop/counter block switchable while isolating synthesis;
    // the product path enables it only when the requested ROI is used.
    localparam integer ENABLE_CORR_DIAG = 0;
    // Use the maintained ISP wrapper so tracking, motion and image
    // statistics remain available to the OSD/status path.
    localparam integer ENABLE_USER_TOP_DIAG = 1;
    // Fixed-ROI 5x7 digit recognizer.  Keep it as a top-level switch so an
    // A/B synthesis can measure its cost without touching the video path.
    localparam integer ENABLE_DIGIT_DIAG = 1;
    // Metadata/CDC diagnostics drive the on-screen status counters.
    localparam integer ENABLE_META_DIAG = 1;
    // Drive the sensor clock through the HDIO DDR output cell.  Besides
    // matching the board's edge-shaped XCLK requirement, this keeps the
    // package pin off the internal PLL clock net and removes the mixed
    // clock/data fanout warning on O_cam_24m.
    localparam integer ENABLE_XCLK_ODDR_DIAG = 1;


    wire        	S_100m_clk;
    wire        	S_24m_clk;
    wire        	S_aux_50m_clk;
	wire        	S_10m_clk;
		
	wire        	S_pll_lock;
	// R10 is wired to the PHY TX_CTL signal on this board. This project uses
	// PLL lock for internal reset sequencing instead of an external reset pin.
	wire I_rst_n = 1'b1;
    wire        	S_rst_n;
	
	wire [15:0] 	S_ae;
    wire [15:0] 	S_ag;
    wire 			S_cam_cfg_done;
    wire 			S_ae_cfg_done;
    wire 			S_ae_req;
    wire [7:0]     S_ae_luma;
    wire [1:0]     S_ae_highlight;
    wire           S_ae_luma_toggle;
    wire [7:0]     S_ae_luma_dbg;
    wire [3:0]     S_exposure_level;
    wire [4:0]     S_gain_index;
    reg gain_req,gain_rm,gain_rs,gain_ack,gain_am,gain_as;
    reg [5:0] gain_packet,gain_csi;
    always @(posedge S_24m_clk or negedge S_rst_n)
      if(!S_rst_n)begin gain_req<=0;gain_am<=0;gain_as<=0;gain_packet<=6'b101111;end
      else begin gain_am<=gain_ack;gain_as<=gain_am;
        if(gain_as==gain_req)begin
          gain_packet<={S_ae_auto_enable_s1,S_gain_index};gain_req<=~gain_req;
        end
      end
    always @(posedge S_csi_rx_clk or negedge S_rst_n)
      if(!S_rst_n)begin gain_rm<=0;gain_rs<=0;gain_ack<=0;gain_csi<=6'b101111;end
      else begin gain_rm<=gain_req;gain_rs<=gain_rm;
        if(gain_rs!=gain_ack)begin gain_csi<=gain_packet;gain_ack<=gain_rs;end
      end
    // Debounced KEY3 controls AWB; KEY4 controls automatic AE/AG.
    wire           S_awb_enable_request;
    wire           S_ae_auto_enable;
    reg            S_ae_auto_enable_s0,S_ae_auto_enable_s1;
    wire [10:0]    S_awb_status;

    // 四键控制器在 100MHz 域输出的消抖状态。KEY3 的曝光兼容输入跨到
    // 24MHz；KEY4 的自动控制电平经过两级同步后送入同一控制域。
    wire [3:0]     S_button_state;
    reg           S_ae_inc_s0, S_ae_inc_s1, S_ae_inc_d;
    wire          S_ae_manual_inc = S_ae_inc_s1 & ~S_ae_inc_d;
	
	wire        	S_csi_rx_clk;  
    wire        	S_hs_rx_valid;  
    wire[15:0]  	S_hs_rx_data;   
	wire[1:0]   	S_lane_error;
    wire        S_csi_hs_unused;
    wire        S_hdmi_ddc_sda;
	
	wire        	S_csi_frame_start;       
	wire        	S_csi_frame_end;         
	wire        	S_csi_valid;             
	wire[31:0]  	S_csi_data;  
		
	wire        	S_raw10_frame_start; 
	wire        	S_raw10_frame_end;   
	wire        	S_raw10_valid;       
	wire [39:0] 	S_raw10_data;
		
	wire 			S_axis_tlast;  
	wire 			S_axis_tuser;  
	wire [39:0]		S_axis_tdata;  
	wire 			S_axis_tvalid; 
	
	wire [39:0]		S_raw_tdata ;
	wire			S_raw_tlast ;
	wire 			S_raw_tvalid;
	wire 			S_raw_tuser ;
	
	wire			S_ISP_O_tready;
	wire [127:0]	S_ISP_O_tdata ;
	wire 			S_ISP_O_tlast ;
	wire 			S_ISP_O_tuser ;
	wire 			S_ISP_O_tvalid; 
	

    wire        S_ddr_clk;
    wire        S_lat_write_start, S_lat_read_start;
    wire [1:0]  S_lat_write_slot, S_lat_read_slot;
    wire        S_latency_valid;
    wire [7:0] S_in_fps_bcd,S_out_fps_bcd;
    wire S_second_tick,S_pixel_underflow,S_display_frame_end;
    wire [15:0] S_latency_ms;
    wire        S_hdmi_pixel_clk;
    wire        S_hdmi_serial_clk;
    wire        S_hdmi_rst_n;
    wire        S_video_out_rst_n;


    wire        S_vi_128b_frame_start;
    wire        S_vi_128b_valid;      
    wire[127:0] S_vi_128b_data;    
    
    wire        S_video_out_rd_busy;
    wire        S_video_in_wr_busy; 
    wire[1:0]   S_video_out_rp;     

    wire        S_ddr_user_wr_en;       
    wire        S_ddr_user_rd_en;       
    wire[24:0]  S_ddr_user_addr;        
    wire[127:0] S_ddr_user_wr_data;     
    wire        S_ddr_user_ready;       
    wire        S_ddr_user_rd_valid;    
    wire[127:0] S_ddr_user_rd_data;     

    wire        S_vi_ddr_wr_en;   
    wire[24:0]  S_vi_ddr_wr_addr; 
    wire[127:0] S_vi_ddr_wr_data;
    wire        S_vi_ddr_wr_ready;

    wire        S_vo_ddr_rd_en;   
    wire[24:0]  S_vo_ddr_rd_addr; 
    wire        S_vo_ddr_rd_ready;
    wire        S_vo_dbg_fifo_rst;
    wire        S_vo_dbg_ddr_rd_valid;
    wire        S_vo_dbg_fifo_rd_en;
    wire        S_vo_dbg_fifo_empty;

    wire        S_init_calib_complete; 
    wire[24:0]  S_mc_app_addr;          
    wire[2:0]   S_mc_app_cmd;           
    wire        S_mc_app_en;            
    wire[127:0] S_mc_app_wdf_data;      
    wire        S_mc_app_wdf_end;       
    wire[15:0]  S_mc_app_wdf_mask;
    wire[31:0]  S_mc_app_wdf_mask_wide;
    wire        S_mc_app_wdf_wren;      
    wire[127:0] S_mc_app_rd_data;       
    wire        S_mc_app_rd_data_end;   
    wire        S_mc_app_rd_data_valid; 
    wire        S_mc_app_rdy;           
    wire        S_mc_app_wdf_rdy;       
    wire        S_mc_dbg_fifo_afull;
    wire        S_mc_dbg_app_rdy;
    wire        S_mc_dbg_wdf_rdy;
    wire        S_mc_dbg_cmd_pop;

    wire        S_hdmi_vsync;
    wire        S_hdmi_hsync;
    wire        S_hdmi_de;
    wire        S_hdmi_user;
    wire        S_hdmi_last;
    wire        S_video_out_vsync;
    wire        S_hdmi_window_rd_en;
    wire        S_hdmi_out_vsync;
    wire        S_hdmi_out_hsync;
    wire        S_hdmi_out_de;
    wire[23:0]  S_hdmi_out_data;

    wire[23:0]  S_video_rd_data;
    wire[23:0]  S_hdmi_clean_data;
    reg         S_dbg_raw_seen;
    reg         S_dbg_isp_seen;
    reg         S_dbg_ddr_wr_seen;
    reg         S_dbg_ddr_rd_seen;
    reg         S_dbg_cam_cfg_seen;
    reg         S_dbg_hs_seen;
    reg         S_dbg_csi_seen;
    reg         S_dbg_raw10_seen;
    reg         S_dbg_isp_fs_seen;
    reg         S_dbg_isp_valid_seen;
    reg         S_dbg_ddr_req_seen;
    reg         S_dbg_ddr_ready_seen;
    reg [1:0]   S_dbg_raw_seen_sync;
    reg [1:0]   S_dbg_isp_seen_sync;
    reg [1:0]   S_dbg_ddr_wr_seen_sync;
    reg [1:0]   S_dbg_ddr_rd_seen_sync;
    reg [1:0]   S_dbg_cam_cfg_seen_sync;
    reg [1:0]   S_dbg_hs_seen_sync;
    reg [1:0]   S_dbg_csi_seen_sync;
    reg [1:0]   S_dbg_raw10_seen_sync;
    reg [1:0]   S_dbg_isp_fs_seen_sync;
    reg [1:0]   S_dbg_isp_valid_seen_sync;
    reg [1:0]   S_dbg_ddr_req_seen_sync;
    reg [1:0]   S_dbg_ddr_ready_seen_sync;
    reg         S_dbg_video_nonzero_seen;
    reg         S_dbg_rd_req_seen;
    reg         S_dbg_rd_valid_seen;
    reg         S_dbg_rd_nonzero_seen;
    reg [1:0]   S_dbg_rd_req_seen_sync;
    reg [1:0]   S_dbg_rd_valid_seen_sync;
    reg [1:0]   S_dbg_rd_nonzero_seen_sync;
    reg         S_dbg_mc_init_seen;
    reg         S_dbg_mc_app_rdy_seen;
    reg         S_dbg_mc_wdf_rdy_seen;
    reg         S_dbg_mc_cmd_pop_seen;
    reg [1:0]   S_dbg_mc_init_seen_sync;
    reg [1:0]   S_dbg_mc_app_rdy_seen_sync;
    reg [1:0]   S_dbg_mc_wdf_rdy_seen_sync;
    reg [1:0]   S_dbg_mc_cmd_pop_seen_sync;
    wire[3:0]   S_hdmi_debug_status;
    wire        S_lane_error_any;


    assign S_video_out_vsync = ~S_hdmi_vsync;
	
	
    // 外部复位必须直接异步拉低用户逻辑；不能只等待 PLL lock 因复位而掉低。
    // 释放仍由 PLL lock 门控，保持与官方工程的启动顺序一致。
    assign S_rst_n 		= I_rst_n & S_pll_lock;
    assign S_hdmi_rst_n = I_rst_n & S_pll_lock;

    // KEY3 的曝光加档历史输入保留兼容；KEY4 的自动控制使能通过两级
    // 同步器跨入相机配置域。其低速电平不进入像素数据通路。
    always @(posedge S_24m_clk or negedge S_rst_n) begin
        if (!S_rst_n) begin
            S_ae_inc_s0 <= 1'b0;
            S_ae_inc_s1 <= 1'b0;
            S_ae_inc_d  <= 1'b0;
            S_ae_auto_enable_s0 <= 1'b1;
            S_ae_auto_enable_s1 <= 1'b1;
        end else begin
            S_ae_inc_s0 <= S_button_state[2];
            S_ae_inc_s1 <= S_ae_inc_s0;
            S_ae_inc_d  <= S_ae_inc_s1;
            S_ae_auto_enable_s0 <= S_ae_auto_enable;
            S_ae_auto_enable_s1 <= S_ae_auto_enable_s0;
        end
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_raw_seen <= 1'b0;
        else if(S_raw10_frame_start | S_axis_tvalid)
            S_dbg_raw_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_seen <= 1'b0;
        else if(S_ISP_O_tuser | S_ISP_O_tvalid)
            S_dbg_isp_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_wr_seen <= 1'b0;
        else if(S_vi_ddr_wr_en)
            S_dbg_ddr_wr_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_rd_seen <= 1'b0;
        else if(S_ddr_user_rd_valid)
            S_dbg_ddr_rd_seen <= 1'b1;
    end

    always @(posedge S_24m_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_cam_cfg_seen <= 1'b0;
        else if(S_cam_cfg_done)
            S_dbg_cam_cfg_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_hs_seen <= 1'b0;
        else if(S_hs_rx_valid)
            S_dbg_hs_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_csi_seen <= 1'b0;
        else if(S_csi_frame_start | S_csi_valid)
            S_dbg_csi_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_raw10_seen <= 1'b0;
        else if(S_raw10_frame_start | S_raw10_valid)
            S_dbg_raw10_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_fs_seen <= 1'b0;
        else if(S_ISP_O_tuser)
            S_dbg_isp_fs_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_valid_seen <= 1'b0;
        else if(S_ISP_O_tvalid)
            S_dbg_isp_valid_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_req_seen <= 1'b0;
        else if(S_vi_ddr_wr_en)
            S_dbg_ddr_req_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_ready_seen <= 1'b0;
        else if(S_ddr_user_ready)
            S_dbg_ddr_ready_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_req_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_req_seen <= 1'b0;
        else if(S_vo_ddr_rd_en)
            S_dbg_rd_req_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_valid_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_valid_seen <= 1'b0;
        else if(S_ddr_user_rd_valid)
            S_dbg_rd_valid_seen <= 1'b1;
    end

    always @(posedge S_hdmi_pixel_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_nonzero_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_nonzero_seen <= 1'b0;
        else if(S_hdmi_window_rd_en && (S_video_rd_data != 24'd0))
            S_dbg_rd_nonzero_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_init_seen <= 1'b0;
        else if(S_init_calib_complete)
            S_dbg_mc_init_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_app_rdy_seen <= 1'b0;
        else if(S_mc_dbg_app_rdy)
            S_dbg_mc_app_rdy_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_wdf_rdy_seen <= 1'b0;
        else if(S_mc_dbg_wdf_rdy)
            S_dbg_mc_wdf_rdy_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_cmd_pop_seen <= 1'b0;
        else if(S_mc_dbg_cmd_pop)
            S_dbg_mc_cmd_pop_seen <= 1'b1;
    end

    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if(!S_hdmi_rst_n) begin
            S_dbg_cam_cfg_seen_sync <= 2'b00;
            S_dbg_hs_seen_sync      <= 2'b00;
            S_dbg_csi_seen_sync     <= 2'b00;
            S_dbg_raw10_seen_sync   <= 2'b00;
            S_dbg_raw_seen_sync    <= 2'b00;
            S_dbg_isp_seen_sync    <= 2'b00;
            S_dbg_ddr_wr_seen_sync <= 2'b00;
            S_dbg_ddr_rd_seen_sync <= 2'b00;
            S_dbg_isp_fs_seen_sync  <= 2'b00;
            S_dbg_isp_valid_seen_sync <= 2'b00;
            S_dbg_ddr_req_seen_sync <= 2'b00;
            S_dbg_ddr_ready_seen_sync <= 2'b00;
            S_dbg_video_nonzero_seen <= 1'b0;
            S_dbg_rd_req_seen_sync <= 2'b00;
            S_dbg_rd_valid_seen_sync <= 2'b00;
            S_dbg_rd_nonzero_seen_sync <= 2'b00;
            S_dbg_mc_init_seen_sync <= 2'b00;
            S_dbg_mc_app_rdy_seen_sync <= 2'b00;
            S_dbg_mc_wdf_rdy_seen_sync <= 2'b00;
            S_dbg_mc_cmd_pop_seen_sync <= 2'b00;
        end
        else begin
            S_dbg_cam_cfg_seen_sync <= {S_dbg_cam_cfg_seen_sync[0], S_dbg_cam_cfg_seen};
            S_dbg_hs_seen_sync      <= {S_dbg_hs_seen_sync[0],      S_dbg_hs_seen};
            S_dbg_csi_seen_sync     <= {S_dbg_csi_seen_sync[0],     S_dbg_csi_seen};
            S_dbg_raw10_seen_sync   <= {S_dbg_raw10_seen_sync[0],   S_dbg_raw10_seen};
            S_dbg_raw_seen_sync    <= {S_dbg_raw_seen_sync[0],    S_dbg_raw_seen};
            S_dbg_isp_seen_sync    <= {S_dbg_isp_seen_sync[0],    S_dbg_isp_seen};
            S_dbg_ddr_wr_seen_sync <= {S_dbg_ddr_wr_seen_sync[0], S_dbg_ddr_wr_seen};
            S_dbg_ddr_rd_seen_sync <= {S_dbg_ddr_rd_seen_sync[0], S_dbg_ddr_rd_seen};
            S_dbg_isp_fs_seen_sync  <= {S_dbg_isp_fs_seen_sync[0],  S_dbg_isp_fs_seen};
            S_dbg_isp_valid_seen_sync <= {S_dbg_isp_valid_seen_sync[0], S_dbg_isp_valid_seen};
            S_dbg_ddr_req_seen_sync <= {S_dbg_ddr_req_seen_sync[0], S_dbg_ddr_req_seen};
            S_dbg_ddr_ready_seen_sync <= {S_dbg_ddr_ready_seen_sync[0], S_dbg_ddr_ready_seen};
            S_dbg_rd_req_seen_sync <= {S_dbg_rd_req_seen_sync[0], S_dbg_rd_req_seen};
            S_dbg_rd_valid_seen_sync <= {S_dbg_rd_valid_seen_sync[0], S_dbg_rd_valid_seen};
            S_dbg_rd_nonzero_seen_sync <= {S_dbg_rd_nonzero_seen_sync[0], S_dbg_rd_nonzero_seen};
            S_dbg_mc_init_seen_sync <= {S_dbg_mc_init_seen_sync[0], S_dbg_mc_init_seen};
            S_dbg_mc_app_rdy_seen_sync <= {S_dbg_mc_app_rdy_seen_sync[0], S_dbg_mc_app_rdy_seen};
            S_dbg_mc_wdf_rdy_seen_sync <= {S_dbg_mc_wdf_rdy_seen_sync[0], S_dbg_mc_wdf_rdy_seen};
            S_dbg_mc_cmd_pop_seen_sync <= {S_dbg_mc_cmd_pop_seen_sync[0], S_dbg_mc_cmd_pop_seen};
            if(S_hdmi_window_rd_en && (S_video_rd_data != 24'd0))
                S_dbg_video_nonzero_seen <= 1'b1;
        end
    end

    assign S_lane_error_any = |S_lane_error;

    assign S_vo_dbg_fifo_rst = 1'b0;
    assign S_vo_dbg_ddr_rd_valid = 1'b0;
    assign S_vo_dbg_fifo_rd_en = 1'b0;
    assign S_vo_dbg_fifo_empty = 1'b0;
    assign S_mc_dbg_fifo_afull = 1'b0;
    assign S_mc_dbg_app_rdy = 1'b0;
    assign S_mc_dbg_wdf_rdy = 1'b0;
    assign S_mc_dbg_cmd_pop = 1'b0;

    assign S_hdmi_debug_status = {
        (|S_ddr_user_rd_data),
        S_ddr_user_rd_valid,
        S_vo_ddr_rd_en,
        S_vi_ddr_wr_en
    };
	
	assign O_cam_rst 	= 1'b1;

// 用输出 DDR 寄存器转发摄像头时钟。S_24m_clk 因而只驱动真正的
    // clock pin，不再同时作为普通数据网直连输出管脚。
    // (修复#34) PH1P_LOGIC_ODDR 属 HRIO(HR bank) 原语, 而 O_cam_24m 约束
    //   在 HDIO 引脚(L3) → TD MapIO 错误。改用 HD 专用 PH1P_LOGIC_HD_ODDR
    //   (端口签名完全一致: q/clk/d1/d0/rst, rst 高有效)。
    generate
    if (ENABLE_XCLK_ODDR_DIAG != 0) begin : gen_xclk_oddr
    PH1P_LOGIC_HD_ODDR u_cam_xclk_oddr (
        .clk (S_24m_clk),
        .rst (~S_rst_n),
        .d1  (1'b1),
        .d0  (1'b0),
        .q   (O_cam_24m)
    );
    end else begin : gen_xclk_direct
        assign O_cam_24m = S_24m_clk;
    end
    endgenerate
	assign S_ISP_O_tready = 1'b1; // 视频链不支持反压，明确保持 ready
	
	
	
	
    PLL u_PLL(
        .refclk      ( I_sys_clk         ),
        .reset    	 ( ~I_rst_n          ),
        
        .clk0_out    ( S_100m_clk        ),
        .clk1_out    ( S_24m_clk         ),

        .clk4_out    ( S_hdmi_pixel_clk  ),
        .clk5_out    ( S_hdmi_serial_clk ),

        .lock        ( S_pll_lock        )

    );


	

  
  generate
  if (ENABLE_AE_DIAG != 0) begin : gen_ae
  if (ENABLE_AE_CUSTOM != 0) begin : gen_custom_ae
  ua_auto_exposure #(
      .FORCE_MAX      (FORCE_AE_MAX),
      .MANUAL_LEVELS  (0),
      .AUTO_START_WRITE (1),
      .AUTO_FAST (1),
      .RESTORE_ON_DISABLE(1),
      .HIGHLIGHT_PROTECT(1),
      .SUBJECT_FLOOR(8'd40),
      .LUMA_LOW(8'd48),.LUMA_HIGH(8'd72), // linear-light, not display gamma codes
      .AG_DEFAULT (16'd16)
  ) u_ua_auto_exposure (
      .I_clk          (S_24m_clk),
      .I_rst_n        (S_rst_n),
      .I_luma_mean    (S_ae_luma),
      .I_frame_toggle (S_ae_luma_toggle),
      .I_highlight    (S_ae_highlight),
      .I_cam_cfg_done (S_cam_cfg_done),
      .I_ae_cfg_done  (S_ae_cfg_done),
      .I_auto_enable  (S_ae_auto_enable_s1),
      .I_manual_inc   (S_ae_manual_inc),
      .I_manual_dec   (1'b0),
      .O_ae_req       (S_ae_req),
      .O_ae           (S_ae),
      .O_ag           (S_ag),
      .O_luma_dbg     (S_ae_luma_dbg),
      .O_manual_level (S_exposure_level),
      .O_gain_index   (S_gain_index)
  );
  end else begin : gen_official_ae
    ae_set u_ae_set (
      .I_clk        (S_24m_clk),
      .I_rst        (~S_rst_n),
      .I_btn        (I_button),
      .I_cam_cfg_done(S_cam_cfg_done),
      .I_ae_cfg_done (S_ae_cfg_done),
      .O_ae_req     (S_ae_req),
      .O_ae         (S_ae),
      .O_ag         (S_ag)
    );
    assign S_ae_luma_dbg = 8'd128;
    assign S_exposure_level = 4'd15;
    assign S_gain_index = 5'd15;
  end

  ua_button_toggle_embedded u_awb_key (
      .I_clk(S_100m_clk),.I_rst_n(S_rst_n),.I_button(S_button_state[2]),
      .O_enable(S_awb_enable_request)
  );
  ua_button_toggle_embedded u_auto_exposure_key (
      .I_clk(S_100m_clk),.I_rst_n(S_rst_n),.I_button(S_button_state[3]),
      .O_enable(S_ae_auto_enable)
  );
  ua_ae_panel_embedded u_ae_panel (
      .I_clk(S_100m_clk),.I_source_clk(S_24m_clk),.I_rst_n(S_rst_n),
      .I_index(S_gain_index),.I_enable(S_ae_auto_enable_s1),
      .O_seg_sel(O_seg_sel),.O_seg_led(O_seg_led)
  );
  
    uicfgcs500_720p #(
      .CLK_DIV(24000000 / 100000 - 1)
  ) u_uicfgcs500 (
      .I_clk(S_24m_clk),  //系统时钟输入
      .I_rst_n(S_rst_n),  //系统复位输入
      .I_ae_req(S_ae_req),
      .I_ae(S_ae),
      .I_ag(S_ag),
      .O_cam_scl(O_cam_scl),  //I2C总线，SCL时钟
      .IO_cam_sda(IO_cam_sda),  //I2C总线，SDA数据
      .O_cfg_done(S_cam_cfg_done),  //摄像头寄存器初始化完成
      .O_ae_cfg_done(S_ae_cfg_done)  //AE配置完成
  );
	
    mipi_dphy_rx_ph1p_mipiio_wrapper#(
        .DPHY_RX_LOCATION      ( "DPHY0" ),
        .HS_EQUALIZER          ( "0dB"   ),//"0dB","1.5dB","3dB","4.5dB","6dB","7.5dB","9dB","10.5dB"
        .HS_VGA_GAIN           ( "8dB" ),//"-3dB","-1.5dB","0dB","1.5dB","3dB","4.5dB","6dB","7.5dB"
        .LANE_NUM              ( 2       ),
        .BYTE_NUM              ( 1       )
    )u_mipi_dphy_rx_ph1p_mipiio_wrapper(
        .I_lp_clk              ( S_100m_clk       ),
        .I_rst                 ( ~S_rst_n         ),

        .I_clk_lane_in_delay   ( 6'd0             ),
        .I_data_lane0_in_delay ( 6'd0             ),
        .I_data_lane1_in_delay ( 6'd0             ),
        .I_data_lane2_in_delay ( 6'd0             ),
        .I_data_lane3_in_delay ( 6'd0             ),

        .I_lane_invert         ( 2'b00            ),
     
        .O_hs_rx_clk           ( S_csi_rx_clk     ),
        .O_hs_rx_valid         ( S_hs_rx_valid    ),
        .O_hs_rx_data          ( S_hs_rx_data     ),
      
        .O_lp_rx_lane0_p       (  ),
        .O_lp_rx_lane0_n       (  ),
      
        .I_lp_tx_en            ( 1'b0             ),
        .I_lp_tx_lane0_p       ( 1'b1             ),
        .I_lp_tx_lane0_n       ( 1'b1             ),
      
        .O_lane_match_error    (                  ),
        .O_lane_error          ( S_lane_error     ),
      
        .IO_rx_clk_pad_n       ( IO_rx_clk_pad_n  ),
        .IO_rx_clk_pad_p       ( IO_rx_clk_pad_p  ),
        .IO_rx_data_pad_n      ( IO_rx_data_pad_n ),
        .IO_rx_data_pad_p      ( IO_rx_data_pad_p )
    );
	
	
 //  cwc cwc_inst
 //(
 //    .probe0(S_hs_rx_valid),
 //    .probe1(S_hs_rx_data),
 //    .probe2(S_lane_error),
 //    .clk(S_csi_rx_clk)
 //);

// [输入链路] MIPI 字节流解包为 CSI 像素流；此时仍是相机原始数据。
csi_unpacket_2lane u_csi_unpacket(
.I_clk                 ( S_csi_rx_clk       ),
.I_rst_n               ( S_rst_n        	),
.I_hs_valid            ( S_hs_rx_valid     ),
.I_hs_data             ( S_hs_rx_data      ),

.O_csi_frame_start     ( S_csi_frame_start ),
.O_csi_frame_end       ( S_csi_frame_end   ),
.O_csi_valid           ( S_csi_valid       ),
.O_csi_data            ( S_csi_data        ),
.O_csi_hs              ( S_csi_hs_unused   )
);


// [输入链路] RAW10 解包并附加流边界：tuser=帧首，tlast=行尾。
raw10_unpacket_2lane u_raw10_unpacket (
.I_clk  (S_csi_rx_clk),
.I_rst_n(S_rst_n),

.I_csi_frame_start(S_csi_frame_start),
.I_csi_frame_end  (S_csi_frame_end),
.I_csi_valid      (S_csi_valid),
.I_csi_data       (S_csi_data),
.I_camera_black_level(10'd0),

.O_raw10_frame_start(S_raw10_frame_start),
.O_raw10_frame_end  (S_raw10_frame_end),
.O_raw10_valid      (S_raw10_valid),
.O_raw10_data       (S_raw10_data)
  );


//将数据转为stream流
uial2axis #(
.IMG_WIDTH(IMG_WIDTH),
.IMG_HEIGHT(IMG_HEIGHT),
.INPUT_DATA_WIDTH(40)
) 
u_uial2axis (
.I_native_clk(S_csi_rx_clk),
.I_rst_n     (S_rst_n),
.I_data      (S_raw10_data       ),
.I_data_valid(S_raw10_valid      ),
.I_data_start(S_raw10_frame_start),
.I_data_end  (S_raw10_frame_end  ),
.axis_tvalid (S_axis_tvalid),
.axis_tdata  (S_axis_tdata ),
.axis_tuser  (S_axis_tuser ),
.axis_tlast  (S_axis_tlast )
);
	

if (ENABLE_CORR_DIAG != 0) begin : gen_image_correction
image_correction #(
    .DATA_WIDTH(40)
) u_image_correction(
    .I_clk   		(S_csi_rx_clk),
    .I_rst_n 		(S_rst_n),
					
    .I_raw_data 	(S_axis_tdata),
    .I_raw_frame_end 	(S_axis_tlast),
    .I_raw_valid	(S_axis_tvalid),
    .I_raw_frame_start 	(S_axis_tuser),
					
    .O_raw_tdata 	(S_raw_tdata ),
    .O_raw_tlast 	(S_raw_tlast ),
    .O_raw_tvalid	(S_raw_tvalid),
    .O_raw_tuser 	(S_raw_tuser ),
    .O_raw_tready    (1'b1)
);
end else begin : gen_no_image_correction
    assign S_raw_tdata  = S_axis_tdata;
    assign S_raw_tlast  = S_axis_tlast;
    assign S_raw_tvalid = S_axis_tvalid;
    assign S_raw_tuser  = S_axis_tuser;
end


//cwc1 cwc1_Inst
//  (
//      .probe0(S_axis_tuser),
//      .probe1(S_axis_tvalid),
//      .probe2(S_axis_tlast),
//      .probe3(S_axis_tdata),
//      .probe4(S_ISP_O_tuser),
//      .probe5(S_ISP_O_tvalid),
//      .probe6(S_ISP_O_tlast),
//      .probe7(S_ISP_O_tdata),
//      .probe8 (S_raw_tdata ),
//      .probe9 (S_raw_tlast ),
//      .probe10(S_raw_tvalid),
//      .probe11(S_raw_tuser ),
//      .clk(S_csi_rx_clk)
//  );


// [ISP + 用户算法] RAW10 -> 去马赛克/AWB -> RGB；旁路还会统计运动、目标和亮度。
wire [2:0]  S_algo_mode;       // 已同步到 CSI/ISP 域的模式
wire [2:0]  S_algo_mode_btn;   // 100MHz 按键控制域的稳定模式
reg  [2:0]  S_algo_mode_csi_s0;
reg  [2:0]  S_algo_mode_csi_s1;
wire [3:0]  S_detect_en_btn;   // 100MHz 域的稳定检测使能
reg  [3:0]  S_detect_en_csi_s0;
reg  [3:0]  S_detect_en_csi_s1;
reg  [3:0]  S_detect_en_hdmi_s0;
reg  [3:0]  S_detect_en_hdmi_s1;
reg         S_aruco_enable_hdmi_s0;
reg         S_aruco_enable_hdmi_s1;

// 模式是低速、只在按键动作时改变的配置总线。按键控制器在 100MHz
// 域完成消抖后，这里用两级寄存器跨到 ISP 域；模式在下一帧边界前
// 已稳定，避免把异步按键或未同步的多位总线直接送入图像算法。
always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
    if (!S_rst_n) begin
        S_algo_mode_csi_s0 <= 3'd0;
        S_algo_mode_csi_s1 <= 3'd0;
    end else begin
        S_algo_mode_csi_s0 <= S_algo_mode_btn;
        S_algo_mode_csi_s1 <= S_algo_mode_csi_s0;
    end
end
assign S_algo_mode = S_algo_mode_csi_s1;

// 拨动开关同样是低速配置总线：先在 100 MHz 域同步/消抖，再分别同步
// 到 CSI 和 HDMI 域。这样用户可以在运行中独立打开/关闭检测，不会把
// 异步开关抖动直接带入像素 ready 链或 OSD 状态寄存器。
always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
    if (!S_rst_n) begin
        S_detect_en_csi_s0 <= 4'd0;
        S_detect_en_csi_s1 <= 4'd0;
    end else begin
        // SW1 drives both motion and color/shape. Independent SW2 is reserved
        // for the ArUco firmware through S_detect_en_btn[1].
        S_detect_en_csi_s0 <= {S_detect_en_btn[3:2],S_detect_en_btn[0],S_detect_en_btn[0]};
        S_detect_en_csi_s1 <= S_detect_en_csi_s0;
    end
end
always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
    if (!S_hdmi_rst_n) begin
        S_detect_en_hdmi_s0 <= 4'd0;
        S_detect_en_hdmi_s1 <= 4'd0;
        S_aruco_enable_hdmi_s0 <= 1'b0;
        S_aruco_enable_hdmi_s1 <= 1'b0;
    end else begin
        S_detect_en_hdmi_s0 <= S_detect_en_csi_s1;
        S_detect_en_hdmi_s1 <= S_detect_en_hdmi_s0;
        S_aruco_enable_hdmi_s0 <= S_detect_en_btn[1];
        S_aruco_enable_hdmi_s1 <= S_aruco_enable_hdmi_s0;
    end
end

// 运行时检测选择。检测器实体仍保持常驻，以免切换时重新建立大块
// 参考帧/流水；这里在结果发布端屏蔽，开关关闭时不会污染 OSD 或计数。
wire        S_motion_valid_sel = S_detect_en_csi_s1[0] ? S_isp_motion_valid : 1'b0;
wire [15:0] S_motion_count_sel = S_detect_en_csi_s1[0] ? S_isp_motion_count : 16'd0;
wire        S_track_valid_sel  = S_detect_en_csi_s1[1] ? S_isp_track_valid : 1'b0;
wire [3:0]  S_track_cnt_sel    = S_detect_en_csi_s1[1] ? S_isp_track_cnt : 4'd0;
wire        S_t0_v_sel         = S_detect_en_csi_s1[1] ? S_isp_t0_v : 1'b0;
wire [10:0] S_t0_x_sel         = S_detect_en_csi_s1[1] ? S_isp_t0_x : 11'd0;
wire [10:0] S_t0_y_sel         = S_detect_en_csi_s1[1] ? S_isp_t0_y : 11'd0;
wire [1:0]  S_t0_sh_sel        = S_detect_en_csi_s1[1] ? S_isp_t0_sh : 2'd3;
wire [10:0] S_t0_xmin_sel      = S_detect_en_csi_s1[1] ? S_isp_t0_xmin : 11'd0;
wire [10:0] S_t0_xmax_sel      = S_detect_en_csi_s1[1] ? S_isp_t0_xmax : 11'd0;
wire [10:0] S_t0_ymin_sel      = S_detect_en_csi_s1[1] ? S_isp_t0_ymin : 11'd0;
wire [10:0] S_t0_ymax_sel      = S_detect_en_csi_s1[1] ? S_isp_t0_ymax : 11'd0;
wire        S_t1_v_sel         = S_detect_en_csi_s1[1] ? S_isp_t1_v : 1'b0;
wire [10:0] S_t1_x_sel         = S_detect_en_csi_s1[1] ? S_isp_t1_x : 11'd0;
wire [10:0] S_t1_y_sel         = S_detect_en_csi_s1[1] ? S_isp_t1_y : 11'd0;
wire [1:0]  S_t1_sh_sel        = S_detect_en_csi_s1[1] ? S_isp_t1_sh : 2'd3;
wire [10:0] S_t1_xmin_sel      = S_detect_en_csi_s1[1] ? S_isp_t1_xmin : 11'd0;
wire [10:0] S_t1_xmax_sel      = S_detect_en_csi_s1[1] ? S_isp_t1_xmax : 11'd0;
wire [10:0] S_t1_ymin_sel      = S_detect_en_csi_s1[1] ? S_isp_t1_ymin : 11'd0;
wire [10:0] S_t1_ymax_sel      = S_detect_en_csi_s1[1] ? S_isp_t1_ymax : 11'd0;
wire        S_t2_v_sel         = S_detect_en_csi_s1[1] ? S_isp_t2_v : 1'b0;
wire [10:0] S_t2_x_sel         = S_detect_en_csi_s1[1] ? S_isp_t2_x : 11'd0;
wire [10:0] S_t2_y_sel         = S_detect_en_csi_s1[1] ? S_isp_t2_y : 11'd0;
wire [1:0]  S_t2_sh_sel        = S_detect_en_csi_s1[1] ? S_isp_t2_sh : 2'd3;
wire [10:0] S_t2_xmin_sel      = S_detect_en_csi_s1[1] ? S_isp_t2_xmin : 11'd0;
wire [10:0] S_t2_xmax_sel      = S_detect_en_csi_s1[1] ? S_isp_t2_xmax : 11'd0;
wire [10:0] S_t2_ymin_sel      = S_detect_en_csi_s1[1] ? S_isp_t2_ymin : 11'd0;
wire [10:0] S_t2_ymax_sel      = S_detect_en_csi_s1[1] ? S_isp_t2_ymax : 11'd0;
wire        S_digit_valid_sel   = S_detect_en_csi_s1[3] ? S_isp_digit_valid : 1'b0;
wire [3:0]  S_digit_id_sel      = S_detect_en_csi_s1[3] ? S_isp_digit_id : 4'hf;
wire [7:0]  S_digit_conf_sel    = S_detect_en_csi_s1[3] ? S_isp_digit_confidence : 8'd0;
wire        S_hand_valid_sel   = S_detect_en_csi_s1[2] ? S_isp_hand_valid : 1'b0;
wire [1:0]  S_hand_id_sel      = S_detect_en_csi_s1[2] ? S_isp_hand_id : 2'd0;
wire [2:0]  S_hand_tips_sel    = S_detect_en_csi_s1[2] ? S_isp_hand_tips : 3'd0;
wire [40:0] S_hand_box_sel = S_detect_en_csi_s1[2] ?
    {S_isp_hand_box_valid,S_isp_hand_xmin,S_isp_hand_xmax,
     S_isp_hand_ymin,S_isp_hand_ymax} : 41'd0;
// 相机域帧计数 + CDC 到显示域 (OSD 延迟显示用, mod256)
reg [7:0] S_cam_frame_cnt = 8'd0;
wire        S_isp_motion_valid;      // csi 域 (帧末脉冲)
wire        S_isp_track_valid;       // csi 域 (帧末脉冲)
wire [3:0]  S_isp_track_cnt;
wire S_isp_t0_v;
wire [10:0] S_isp_t0_x, S_isp_t0_y;
wire [1:0] S_isp_t0_sh;
wire [10:0] S_isp_t0_xmin, S_isp_t0_xmax, S_isp_t0_ymin, S_isp_t0_ymax;
wire S_target_enable, S_target_uart;
wire [95:0] S_aruco_rgb;
wire S_aruco_valid,S_aruco_sof,S_aruco_eol;
wire S_aruco_display_valid;
wire S_aruco_display_update;
wire [166:0] S_aruco_display_axes;
wire [11:0] S_aruco_display_id_bcd;
wire [21:0] S_aruco_display_corner0,S_aruco_display_corner1;
wire [21:0] S_aruco_display_corner2,S_aruco_display_corner3;
wire [25:0] S_aruco_display_edge0,S_aruco_display_edge1;
wire [25:0] S_aruco_display_edge2,S_aruco_display_edge3;
// Dedicated RST pads: one FPGA pin per driver terminal. Keep the same
// fail-closed reset/watchdog/stop timing as SLP; no independent software arm.
assign O_motor_reset_n = O_motor_awake;
ua_tracking_mcu #(.ENABLE_ARUCO(1),.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT),.ENABLE_STEPPER(1),.ENABLE_BUS_TRACE(0)) u_tracking_mcu (
    .clk_50m(I_sys_clk), .uart_rx(I_mcu_uart_rx), .uart_tx(O_mcu_uart_tx),.key2_n(I_button[1]),
    .target_uart(S_target_uart), .target_enable(S_target_enable),
    .servo_pwm(), .servo_pwm_b(),
    .motor_step(O_motor_step),.motor_dir(O_motor_dir),.motor_awake(O_motor_awake),
    .video_clk(S_csi_rx_clk),.video_rst_n(S_rst_n),.video_rgb(S_aruco_rgb),
    .video_valid(S_aruco_valid),.video_sof(S_aruco_sof),.video_eol(S_aruco_eol),
    .aruco_enable(S_detect_en_btn[1]),
    .display_clk(S_hdmi_pixel_clk),.display_rst_n(S_hdmi_rst_n),
    .O_aruco_update(S_aruco_display_update),.O_aruco_valid(S_aruco_display_valid),.O_aruco_id_bcd(S_aruco_display_id_bcd),
    .O_aruco_axes(S_aruco_display_axes),
    .O_aruco_corner0(S_aruco_display_corner0),.O_aruco_corner1(S_aruco_display_corner1),
    .O_aruco_corner2(S_aruco_display_corner2),.O_aruco_corner3(S_aruco_display_corner3),
    .O_aruco_edge0(S_aruco_display_edge0),.O_aruco_edge1(S_aruco_display_edge1),
    .O_aruco_edge2(S_aruco_display_edge2),.O_aruco_edge3(S_aruco_display_edge3)
);
ua_red_ball_uart u_red_ball_uart (
    .src_clk(S_csi_rx_clk), .rst_n(S_rst_n), .dst_clk(I_sys_clk),
    .enable(S_target_enable), .frame_valid(S_isp_track_valid),
    .target_valid(S_isp_t0_v), .target_shape(S_isp_t0_sh),
    .target_x(S_isp_t0_x), .target_y(S_isp_t0_y),
    .xmin(S_isp_t0_xmin), .xmax(S_isp_t0_xmax),
    .ymin(S_isp_t0_ymin), .ymax(S_isp_t0_ymax), .tx(S_target_uart)
);
  wire        S_isp_t1_v;  wire [10:0] S_isp_t1_x; wire [10:0] S_isp_t1_y; wire [1:0] S_isp_t1_sh;
  wire [10:0] S_isp_t1_xmin, S_isp_t1_xmax, S_isp_t1_ymin, S_isp_t1_ymax;
  wire        S_isp_t2_v;  wire [10:0] S_isp_t2_x; wire [10:0] S_isp_t2_y; wire [1:0] S_isp_t2_sh;
  wire [10:0] S_isp_t2_xmin, S_isp_t2_xmax, S_isp_t2_ymin, S_isp_t2_ymax;
wire        S_isp_digit_valid;
wire [3:0]  S_isp_digit_id;
wire [7:0]  S_isp_digit_confidence;
wire        S_isp_hand_valid;
wire [1:0]  S_isp_hand_id;
wire [2:0]  S_isp_hand_tips;
wire        S_isp_hand_box_valid;
wire [9:0]  S_isp_hand_xmin, S_isp_hand_xmax, S_isp_hand_ymin, S_isp_hand_ymax;
wire [15:0] S_isp_motion_count;      // csi 域
wire [52:0] S_motion_view_src,S_motion_view_hdmi;
wire [56:0] S_digit_view_src,S_digit_view_hdmi;
wire S_digit_view_valid_src,S_digit_view_valid_hdmi;
ua_motion_mailbox #(.WIDTH(57)) u_digit_mailbox(
 .src_clk(S_csi_rx_clk),.src_rst_n(S_rst_n),
 .src_valid(S_digit_view_valid_src),.src_data(S_digit_view_src),
 .dst_clk(S_hdmi_pixel_clk),.dst_rst_n(S_hdmi_rst_n),
 .dst_valid(S_digit_view_valid_hdmi),.dst_data(S_digit_view_hdmi));
wire S_motion_view_valid_src,S_motion_view_valid_hdmi;
(* async_reg="true" *) reg [1:0] S_motor_step_sync0,S_motor_step_sync1;
reg [1:0] S_motor_step_previous;
always @(posedge S_csi_rx_clk or negedge S_rst_n)begin
 if(!S_rst_n)begin S_motor_step_sync0<=0;S_motor_step_sync1<=0;S_motor_step_previous<=0;end
 else begin
  S_motor_step_sync0<=O_motor_step;S_motor_step_sync1<=S_motor_step_sync0;
  S_motor_step_previous<=S_motor_step_sync1;
 end
end
wire S_camera_step=|(S_motor_step_sync1^S_motor_step_previous);
ua_motion_mailbox u_motion_mailbox(
 .src_clk(S_csi_rx_clk),.src_rst_n(S_rst_n),
 .src_valid(S_motion_view_valid_src),.src_data(S_motion_view_src),
 .dst_clk(S_hdmi_pixel_clk),.dst_rst_n(S_hdmi_rst_n),
 .dst_valid(S_motion_view_valid_hdmi),.dst_data(S_motion_view_hdmi));
// Keep the CDC/status registers at module scope.  A named generate scope
// would hide them from the later OSD instance and make Verilog create
// accidental one-bit implicit nets at elaboration.
reg         S_motion_lvl;            // csi 域: 脉冲→电平 (帧末置1)
reg         S_track_lvl;
reg         S_digit_lvl;
// 脉冲→电平: 帧末(motion_valid)置1, 帧首(raw_tuser)清0 — 电平跨域安全
always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
    if (!S_rst_n) begin
        S_motion_lvl <= 1'b0;
        S_track_lvl  <= 1'b0;
        S_digit_lvl <= 1'b0;
    end else begin
        if (S_motion_valid_sel) S_motion_lvl <= 1'b1;
        if (S_raw_tuser)        S_motion_lvl <= 1'b0;   // 帧首清 (优先于置位: 同帧不同拍, 无冲突)
        if (S_track_valid_sel)   S_track_lvl  <= 1'b1;
        if (S_raw_tuser)        S_track_lvl  <= 1'b0;
        if (S_digit_valid_sel) S_digit_lvl <= 1'b1;
        if (S_raw_tuser)       S_digit_lvl <= 1'b0;
    end
end
reg         S_motion_valid_s0, S_motion_valid_s1;
reg [15:0]  S_motion_count_s0, S_motion_count_s1;
reg         S_track_valid_s0, S_track_valid_s1;
reg [3:0]   S_track_cnt_s0, S_track_cnt_s1;
reg         S_digit_valid_s0, S_digit_valid_s1;
reg [3:0]   S_digit_id_s0, S_digit_id_s1;
reg [7:0]   S_digit_confidence_s0, S_digit_confidence_s1;
// Held-data mailbox: capture all hand fields together in the CSI clock domain.
// Results are spaced by video frames, so the bus remains unchanged for many
// HDMI cycles after the event toggle has crossed its synchronizer.
reg [45:0] S_hand_mailbox_csi;
reg        S_hand_toggle_csi;
always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
    if (!S_rst_n) begin
        S_hand_mailbox_csi <= 46'd0;
        S_hand_toggle_csi <= 1'b0;
    end else if (S_hand_valid_sel) begin
        S_hand_mailbox_csi <= {S_hand_box_sel,S_hand_id_sel,S_hand_tips_sel};
        S_hand_toggle_csi <= ~S_hand_toggle_csi;
    end
end
(* ASYNC_REG = "TRUE" *) reg S_hand_toggle_s0, S_hand_toggle_s1;
reg S_hand_toggle_s2;
reg S_hand_valid_pe;
reg [45:0] S_hand_mailbox_hdmi;
always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
    if (!S_hdmi_rst_n) begin
        S_hand_toggle_s0 <= 1'b0; S_hand_toggle_s1 <= 1'b0;
        S_hand_toggle_s2 <= 1'b0; S_hand_valid_pe <= 1'b0;
        S_hand_mailbox_hdmi <= 46'd0;
    end else begin
        S_hand_toggle_s0 <= S_hand_toggle_csi;
        S_hand_toggle_s1 <= S_hand_toggle_s0;
        S_hand_toggle_s2 <= S_hand_toggle_s1;
        S_hand_valid_pe <= S_hand_toggle_s1 ^ S_hand_toggle_s2;
        if (S_hand_toggle_s1 ^ S_hand_toggle_s2)
            S_hand_mailbox_hdmi <= S_hand_mailbox_csi;
    end
end
wire [40:0] S_hand_box_s1 = S_hand_mailbox_hdmi[45:5];
wire [1:0]  S_hand_id_s1 = S_hand_mailbox_hdmi[4:3];
wire [2:0]  S_hand_tips_s1 = S_hand_mailbox_hdmi[2:0];
  reg         S_t0_v_s0, S_t0_v_s1; reg [10:0] S_t0_x_s0, S_t0_x_s1; reg [10:0] S_t0_y_s0, S_t0_y_s1; reg [1:0] S_t0_sh_s0, S_t0_sh_s1;
  reg [10:0]  S_t0_xmin_s0, S_t0_xmin_s1, S_t0_xmax_s0, S_t0_xmax_s1, S_t0_ymin_s0, S_t0_ymin_s1, S_t0_ymax_s0, S_t0_ymax_s1;
  reg         S_t1_v_s0, S_t1_v_s1; reg [10:0] S_t1_x_s0, S_t1_x_s1; reg [10:0] S_t1_y_s0, S_t1_y_s1; reg [1:0] S_t1_sh_s0, S_t1_sh_s1;
  reg [10:0]  S_t1_xmin_s0, S_t1_xmin_s1, S_t1_xmax_s0, S_t1_xmax_s1, S_t1_ymin_s0, S_t1_ymin_s1, S_t1_ymax_s0, S_t1_ymax_s1;
  reg         S_t2_v_s0, S_t2_v_s1; reg [10:0] S_t2_x_s0, S_t2_x_s1; reg [10:0] S_t2_y_s0, S_t2_y_s1; reg [1:0] S_t2_sh_s0, S_t2_sh_s1;
  reg [10:0]  S_t2_xmin_s0, S_t2_xmin_s1, S_t2_xmax_s0, S_t2_xmax_s1, S_t2_ymin_s0, S_t2_ymin_s1, S_t2_ymax_s0, S_t2_ymax_s1;
// motion 计数 CDC: csi_rx_clk → hdmi_pixel_clk (2FF, 显示用途瞬时值可容忍亚稳态)
always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
    if (!S_hdmi_rst_n) begin
        S_motion_valid_s0 <= 1'b0;
        S_motion_valid_s1 <= 1'b0;
        S_motion_count_s0 <= 16'd0;
        S_motion_count_s1 <= 16'd0;
        S_track_valid_s0 <= 1'b0;
        S_track_valid_s1 <= 1'b0;
        S_track_cnt_s0   <= 4'd0;
        S_track_cnt_s1   <= 4'd0;
        S_digit_valid_s0 <= 1'b0; S_digit_valid_s1 <= 1'b0;
        S_digit_id_s0 <= 4'hf; S_digit_id_s1 <= 4'hf;
        S_digit_confidence_s0 <= 8'd0; S_digit_confidence_s1 <= 8'd0;
        S_t0_v_s0 <= 1'b0; S_t0_v_s1 <= 1'b0;
        S_t0_x_s0 <= 11'd0; S_t0_x_s1 <= 11'd0;
         S_t0_y_s0 <= 11'd0; S_t0_y_s1 <= 11'd0;
         S_t0_sh_s0 <= 2'd3; S_t0_sh_s1 <= 2'd3;
         S_t0_xmin_s0 <= 11'd0; S_t0_xmin_s1 <= 11'd0; S_t0_xmax_s0 <= 11'd0; S_t0_xmax_s1 <= 11'd0;
         S_t0_ymin_s0 <= 11'd0; S_t0_ymin_s1 <= 11'd0; S_t0_ymax_s0 <= 11'd0; S_t0_ymax_s1 <= 11'd0;
        S_t1_v_s0 <= 1'b0; S_t1_v_s1 <= 1'b0;
        S_t1_x_s0 <= 11'd0; S_t1_x_s1 <= 11'd0;
         S_t1_y_s0 <= 11'd0; S_t1_y_s1 <= 11'd0;
         S_t1_sh_s0 <= 2'd3; S_t1_sh_s1 <= 2'd3;
         S_t1_xmin_s0 <= 11'd0; S_t1_xmin_s1 <= 11'd0; S_t1_xmax_s0 <= 11'd0; S_t1_xmax_s1 <= 11'd0;
         S_t1_ymin_s0 <= 11'd0; S_t1_ymin_s1 <= 11'd0; S_t1_ymax_s0 <= 11'd0; S_t1_ymax_s1 <= 11'd0;
        S_t2_v_s0 <= 1'b0; S_t2_v_s1 <= 1'b0;
        S_t2_x_s0 <= 11'd0; S_t2_x_s1 <= 11'd0;
         S_t2_y_s0 <= 11'd0; S_t2_y_s1 <= 11'd0;
         S_t2_sh_s0 <= 2'd3; S_t2_sh_s1 <= 2'd3;
         S_t2_xmin_s0 <= 11'd0; S_t2_xmin_s1 <= 11'd0; S_t2_xmax_s0 <= 11'd0; S_t2_xmax_s1 <= 11'd0;
         S_t2_ymin_s0 <= 11'd0; S_t2_ymin_s1 <= 11'd0; S_t2_ymax_s0 <= 11'd0; S_t2_ymax_s1 <= 11'd0;
    end else begin
        S_motion_valid_s0 <= S_motion_lvl;      // 电平同步 (非脉冲)
        S_motion_valid_s1 <= S_motion_valid_s0;
        S_motion_count_s0 <= S_motion_count_sel;
        S_motion_count_s1 <= S_motion_count_s0;
        S_track_valid_s0  <= S_track_lvl;
        S_track_valid_s1  <= S_track_valid_s0;
        S_track_cnt_s0    <= S_track_cnt_sel;
        S_track_cnt_s1    <= S_track_cnt_s0;
        S_digit_valid_s0 <= S_digit_lvl;
        S_digit_valid_s1 <= S_digit_valid_s0;
        S_digit_id_s0 <= S_digit_id_sel;
        S_digit_id_s1 <= S_digit_id_s0;
        S_digit_confidence_s0 <= S_digit_conf_sel;
        S_digit_confidence_s1 <= S_digit_confidence_s0;
        S_t0_v_s0 <= S_t0_v_sel;  S_t0_v_s1 <= S_t0_v_s0;
        S_t0_x_s0 <= S_t0_x_sel;  S_t0_x_s1 <= S_t0_x_s0;
         S_t0_y_s0 <= S_t0_y_sel;  S_t0_y_s1 <= S_t0_y_s0;
         S_t0_sh_s0 <= S_t0_sh_sel; S_t0_sh_s1 <= S_t0_sh_s0;
         S_t0_xmin_s0 <= S_t0_xmin_sel; S_t0_xmin_s1 <= S_t0_xmin_s0;
         S_t0_xmax_s0 <= S_t0_xmax_sel; S_t0_xmax_s1 <= S_t0_xmax_s0;
         S_t0_ymin_s0 <= S_t0_ymin_sel; S_t0_ymin_s1 <= S_t0_ymin_s0;
         S_t0_ymax_s0 <= S_t0_ymax_sel; S_t0_ymax_s1 <= S_t0_ymax_s0;
        S_t1_v_s0 <= S_t1_v_sel;  S_t1_v_s1 <= S_t1_v_s0;
        S_t1_x_s0 <= S_t1_x_sel;  S_t1_x_s1 <= S_t1_x_s0;
         S_t1_y_s0 <= S_t1_y_sel;  S_t1_y_s1 <= S_t1_y_s0;
         S_t1_sh_s0 <= S_t1_sh_sel; S_t1_sh_s1 <= S_t1_sh_s0;
         S_t1_xmin_s0 <= S_t1_xmin_sel; S_t1_xmin_s1 <= S_t1_xmin_s0;
         S_t1_xmax_s0 <= S_t1_xmax_sel; S_t1_xmax_s1 <= S_t1_xmax_s0;
         S_t1_ymin_s0 <= S_t1_ymin_sel; S_t1_ymin_s1 <= S_t1_ymin_s0;
         S_t1_ymax_s0 <= S_t1_ymax_sel; S_t1_ymax_s1 <= S_t1_ymax_s0;
        S_t2_v_s0 <= S_t2_v_sel;  S_t2_v_s1 <= S_t2_v_s0;
        S_t2_x_s0 <= S_t2_x_sel;  S_t2_x_s1 <= S_t2_x_s0;
         S_t2_y_s0 <= S_t2_y_sel;  S_t2_y_s1 <= S_t2_y_s0;
         S_t2_sh_s0 <= S_t2_sh_sel; S_t2_sh_s1 <= S_t2_sh_s0;
         S_t2_xmin_s0 <= S_t2_xmin_sel; S_t2_xmin_s1 <= S_t2_xmin_s0;
         S_t2_xmax_s0 <= S_t2_xmax_sel; S_t2_xmax_s1 <= S_t2_xmax_s0;
         S_t2_ymin_s0 <= S_t2_ymin_sel; S_t2_ymin_s1 <= S_t2_ymin_s0;
         S_t2_ymax_s0 <= S_t2_ymax_sel; S_t2_ymax_s1 <= S_t2_ymax_s0;
    end
end
always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
    if (!S_rst_n) S_cam_frame_cnt <= 8'd0;
    else if (S_raw_tuser) S_cam_frame_cnt <= S_cam_frame_cnt + 8'd1;
end
reg [7:0] S_cam_frame_cnt_s0, S_cam_frame_cnt_s1;
always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
    if (!S_hdmi_rst_n) begin
        S_cam_frame_cnt_s0 <= 8'd0;
        S_cam_frame_cnt_s1 <= 8'd0;
    end else begin
        S_cam_frame_cnt_s0 <= S_cam_frame_cnt;
        S_cam_frame_cnt_s1 <= S_cam_frame_cnt_s0;
    end
end
// 电平→脉冲: 上升沿检测 (mixer 需要 1 拍脉冲锁存)
reg S_motion_valid_d1, S_track_valid_d1, S_digit_valid_d1;
always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
    if (!S_hdmi_rst_n) begin
        S_motion_valid_d1 <= 1'b0;
        S_track_valid_d1  <= 1'b0;
        S_digit_valid_d1 <= 1'b0;
    end else begin
        S_motion_valid_d1 <= S_motion_valid_s1;
        S_track_valid_d1  <= S_track_valid_s1;
        S_digit_valid_d1 <= S_digit_valid_s1;
    end
end
wire S_motion_valid_pe = S_motion_valid_s1 & ~S_motion_valid_d1;
wire S_track_valid_pe  = S_track_valid_s1  & ~S_track_valid_d1;
wire S_digit_valid_pe = S_digit_valid_s1 & ~S_digit_valid_d1;

// algo_mode 2FF 同步到显示域 (mixer OSD 用)
reg [2:0]  S_algo_mode_s0, S_algo_mode_s1;
always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
    if (!S_hdmi_rst_n) begin
        S_algo_mode_s0 <= 2'd0;
        S_algo_mode_s1 <= 2'd0;
    end else begin
        S_algo_mode_s0 <= S_algo_mode;
        S_algo_mode_s1 <= S_algo_mode_s0;
    end
end

ua_detect_switch_ctrl_embedded #(
    .WIDTH            (4),
    .DEBOUNCE_CYCLES (32'd100000), // 1 ms @ 100 MHz
    .SW_ACTIVE_LOW    (1)
) u_ua_detect_switch_ctrl (
    .I_clk    (S_100m_clk),
    .I_rst_n  (S_rst_n),
    .I_switch (I_detect_sw),
    .O_enable (S_detect_en_btn)
);

if (ENABLE_MODE_DIAG != 0) begin : gen_mode_ctrl
ua_mode_ctrl #(
    .DEBOUNCE_CYCLES(21'd1000000), // 10ms @ stable 100MHz control clock
    .INITIAL_MODE   (3'd0),        // Full-resolution photo diagnostic starts in normal RGB mode.
    .KEY2_TRACKING (1)
) u_ua_mode_ctrl (
    .I_clk          (S_100m_clk),
    .I_rst_n        (S_rst_n),
    .I_button       (I_button),
    .O_algo_mode    (S_algo_mode_btn),
    .O_mode_changed (),
    .O_button_state (S_button_state)
);
end else begin : gen_no_mode_ctrl
    assign S_algo_mode_btn = 3'd0;
    assign S_button_state = 4'd0;
end

if (ENABLE_USER_TOP_DIAG != 0) begin : gen_user_isp
isp_top_user #(
    .IMG_WIDTH  (IMG_WIDTH),
    .IMG_HEIGHT (IMG_HEIGHT),
    .ENABLE_TRACK(1),
    .ENABLE_ALGO(1),
    .ENABLE_MOTION(1),
    .ENABLE_MOTION_OVERLAY(1),
    .ENABLE_HAND(1),
    .ENABLE_STATS(1),
    .ENABLE_DIGIT(ENABLE_DIGIT_DIAG),
    .ENABLE_LOWLIGHT_ENHANCE(1),
    .ENABLE_CONTRAST_ENHANCE(1),
    // Photo v2 test: measured RAW pedestal estimate, then sRGB encoding.
    // HDMI/PC-only colour mismatch is deliberately not corrected here.
    .PHOTO_TONE_ENABLE(1),
    .RAW_BLACK_LEVEL(10'd64),
    .AWB_RUNTIME_CONTROL(1)
    ,.BRIGHTNESS_RUNTIME_CONTROL(1)
) u_isp_top (
.I_brightness_enable(gain_csi[5]),.I_gain_index(gain_csi[4:0]),
.axi4s_video_aclk(S_csi_rx_clk),
.I_rst_n         (S_rst_n),
.I_tlast         (S_raw_tlast	),
.I_tuser         (S_raw_tuser	),
.I_tdata         (S_raw_tdata	),
.I_tvalid        (S_raw_tvalid	),
.I_tdest         (10'd0),
.I_algo_mode     (S_algo_mode),
.I_awb_enable    (S_awb_enable_request),
.O_awb_status    (S_awb_status),
.O_aruco_rgb(S_aruco_rgb),.O_aruco_valid(S_aruco_valid),
.O_aruco_sof(S_aruco_sof),.O_aruco_eol(S_aruco_eol),
.O_tready        (S_ISP_O_tready),
.O_tdata         (S_ISP_O_tdata ),
.O_tlast         (S_ISP_O_tlast ),
.O_tuser         (S_ISP_O_tuser ),
.O_tvalid        (S_ISP_O_tvalid),
.I_tready        (),
.O_motion_valid  (S_isp_motion_valid),
.O_motion_count  (S_isp_motion_count),
.I_camera_step(S_camera_step),
.O_motion_view(S_motion_view_src),.O_motion_view_valid(S_motion_view_valid_src),
.O_digit_view(S_digit_view_src),.O_digit_view_valid(S_digit_view_valid_src),
.O_track_valid   (S_isp_track_valid),
.O_obj_cnt       (S_isp_track_cnt),
.O_t0_v          (S_isp_t0_v),   .O_t0_x(S_isp_t0_x), .O_t0_y(S_isp_t0_y), .O_t0_shape(S_isp_t0_sh),
.O_t0_xmin       (S_isp_t0_xmin), .O_t0_xmax(S_isp_t0_xmax), .O_t0_ymin(S_isp_t0_ymin), .O_t0_ymax(S_isp_t0_ymax),
.O_t1_v          (S_isp_t1_v),   .O_t1_x(S_isp_t1_x), .O_t1_y(S_isp_t1_y), .O_t1_shape(S_isp_t1_sh),
.O_t1_xmin       (S_isp_t1_xmin), .O_t1_xmax(S_isp_t1_xmax), .O_t1_ymin(S_isp_t1_ymin), .O_t1_ymax(S_isp_t1_ymax),
.O_t2_v          (S_isp_t2_v),   .O_t2_x(S_isp_t2_x), .O_t2_y(S_isp_t2_y), .O_t2_shape(S_isp_t2_sh),
.O_t2_xmin       (S_isp_t2_xmin), .O_t2_xmax(S_isp_t2_xmax), .O_t2_ymin(S_isp_t2_ymin), .O_t2_ymax(S_isp_t2_ymax),
.O_digit_valid   (S_isp_digit_valid), .O_digit_id(S_isp_digit_id),
.O_digit_confidence(S_isp_digit_confidence),
.O_hand_valid    (S_isp_hand_valid),
.O_hand_id       (S_isp_hand_id),
.O_hand_tip_count(S_isp_hand_tips),
.O_hand_box_valid(S_isp_hand_box_valid),
.O_hand_xmin(S_isp_hand_xmin), .O_hand_xmax(S_isp_hand_xmax),
.O_hand_ymin(S_isp_hand_ymin), .O_hand_ymax(S_isp_hand_ymax),
.O_ae_luma       (S_ae_luma),
.O_ae_luma_toggle(S_ae_luma_toggle),
.O_ae_highlight(S_ae_highlight)
  );
end else begin : gen_official_isp
assign S_aruco_rgb=0;assign S_aruco_valid=0;assign S_aruco_sof=0;assign S_aruco_eol=0;
assign S_awb_status = {1'b0,5'd10,5'd10};
isp_top u_isp_top_official (
.axi4s_video_aclk(S_csi_rx_clk),
.I_rst_n         (S_rst_n),
.I_tlast         (S_raw_tlast),
.I_tuser         (S_raw_tuser),
.I_tdata         (S_raw_tdata),
.I_tvalid        (S_raw_tvalid),
.I_tdest         (10'd0),
.O_tready        (S_ISP_O_tready),
.O_tdata         (S_ISP_O_tdata),
.O_tlast         (S_ISP_O_tlast),
.O_tuser         (S_ISP_O_tuser),
.O_tvalid        (S_ISP_O_tvalid),
.I_tready        ()
);
 assign S_isp_motion_valid = 1'b0;
 assign S_motion_view_src=53'd0;assign S_motion_view_valid_src=1'b0;
 assign S_digit_view_src=57'd0;assign S_digit_view_valid_src=1'b0;
 assign S_isp_motion_count = 16'd0;
 assign S_isp_track_valid = 1'b0;
 assign S_isp_track_cnt = 4'd0;
  assign S_isp_t0_v = 1'b0; assign S_isp_t0_x = 11'd0; assign S_isp_t0_y = 11'd0; assign S_isp_t0_sh = 2'd3;
  assign S_isp_t0_xmin = 11'd0; assign S_isp_t0_xmax = 11'd0; assign S_isp_t0_ymin = 11'd0; assign S_isp_t0_ymax = 11'd0;
  assign S_isp_t1_v = 1'b0; assign S_isp_t1_x = 11'd0; assign S_isp_t1_y = 11'd0; assign S_isp_t1_sh = 2'd3;
  assign S_isp_t1_xmin = 11'd0; assign S_isp_t1_xmax = 11'd0; assign S_isp_t1_ymin = 11'd0; assign S_isp_t1_ymax = 11'd0;
  assign S_isp_t2_v = 1'b0; assign S_isp_t2_x = 11'd0; assign S_isp_t2_y = 11'd0; assign S_isp_t2_sh = 2'd3;
  assign S_isp_t2_xmin = 11'd0; assign S_isp_t2_xmax = 11'd0; assign S_isp_t2_ymin = 11'd0; assign S_isp_t2_ymax = 11'd0;
 assign S_isp_digit_valid = 1'b0; assign S_isp_digit_id = 4'hf;
 assign S_isp_digit_confidence = 8'd0;
 assign S_isp_hand_valid = 1'b0;
 assign S_isp_hand_id = 2'd0;
 assign S_isp_hand_tips = 3'd0;
 assign S_isp_hand_box_valid = 1'b0;
 assign S_isp_hand_xmin = 10'd0; assign S_isp_hand_xmax = 10'd0;
 assign S_isp_hand_ymin = 10'd0; assign S_isp_hand_ymax = 10'd0;
 assign S_ae_luma = 8'd128;
 assign S_ae_luma_toggle = 1'b0;
 assign S_ae_highlight = 2'd0;
end
  end else begin : gen_no_ae
      assign S_ae_req = 1'b0;
      assign S_ae = 16'd512;
      assign S_ag = 16'd16;
      assign S_ae_luma_dbg = 8'd128;
  end
  endgenerate


    // [写 DDR] 将图像写入四个循环帧槽；S_lat_write_* 仅供延迟监视器观察。
    video_in u_video_in(
        .O_meta_start         (S_lat_write_start),
        .O_meta_slot          (S_lat_write_slot),
        .I_rst_n              (  S_rst_n             ),

        .I_camera_clk         ( S_csi_rx_clk          ),
        .I_camera_frame_start ( S_ISP_O_tuser  ),
        .I_camera_valid       ( S_ISP_O_tvalid ),
        .I_camera_data        ( S_ISP_O_tdata  ),
        .I_mipi_rx_error      ( 1'b0			      ),

        .I_ddr_clk            ( S_ddr_clk             ),
        .I_video_out_rd_busy  ( S_video_out_rd_busy   ),
        .O_video_in_wr_busy   ( S_video_in_wr_busy    ),
        .O_video_out_rp       ( S_video_out_rp        ),

        .O_ddr_user_wr_en     ( S_vi_ddr_wr_en        ),
        .O_ddr_user_addr      ( S_vi_ddr_wr_addr      ),
        .O_ddr_user_wr_data   ( S_vi_ddr_wr_data      ),
        .I_ddr_user_ready     ( S_ddr_user_ready      )
    );



    assign S_ddr_user_wr_en    = S_vi_ddr_wr_en;

    assign S_ddr_user_rd_en    = S_vo_ddr_rd_en;

    assign S_ddr_user_addr     = S_vi_ddr_wr_en ? S_vi_ddr_wr_addr :
                                 S_vo_ddr_rd_en ? S_vo_ddr_rd_addr : 'd0;

    assign S_ddr_user_wr_data  = S_vi_ddr_wr_data;


    assign S_video_out_rst_n = S_hdmi_rst_n;

    // [读 DDR] 读取完整帧到显示端，解耦相机写入和 HDMI 读取，避免直接撕裂。
    video_out u_video_out(
        .O_pixel_underflow(S_pixel_underflow),
        .O_meta_start        (S_lat_read_start),
        .O_meta_slot         (S_lat_read_slot),
        .I_rst_n             ( S_video_out_rst_n    ),
        .I_ddr_clk           ( S_ddr_clk            ),
 
        .O_video_out_rd_busy ( S_video_out_rd_busy  ),
        .I_video_in_wr_busy  ( S_video_in_wr_busy   ),
        .I_video_out_rp      ( S_video_out_rp       ),
 
        .O_ddr_user_rd_en    ( S_vo_ddr_rd_en       ),
        .O_ddr_user_addr     ( S_vo_ddr_rd_addr     ),
        .I_ddr_user_ready    ( S_ddr_user_ready     ),
        .I_ddr_user_rd_valid ( S_ddr_user_rd_valid  ),
        .I_ddr_user_rd_data  ( S_ddr_user_rd_data   ),

        .I_dsi_clk           ( S_hdmi_pixel_clk     ),
        .I_video_vsync       ( S_video_out_vsync    ),
        .I_video_rd_en       ( S_hdmi_window_rd_en  ),
        .O_vdieo_data        ( S_video_rd_data      )
    );



    // [DDR 适配] 把用户侧读写请求转换为 DDR 控制器所需端口。
    mc_to_user_interface u_mc_to_user_interface(
        .I_clk                   ( S_ddr_clk               ),
        .I_rst_n                 ( S_rst_n                 ),

        .I_ddr_user_wr_en        ( S_ddr_user_wr_en        ),
        .I_ddr_user_rd_en        ( S_ddr_user_rd_en        ),
        .I_ddr_user_addr         ( S_ddr_user_addr         ),
        .I_ddr_user_wr_data      ( S_ddr_user_wr_data      ),
        .O_ddr_user_ready        ( S_ddr_user_ready        ),
        .O_ddr_user_rd_valid     ( S_ddr_user_rd_valid     ),
        .O_ddr_user_rd_data      ( S_ddr_user_rd_data      ),
            
        .O_mc_app_en             ( S_mc_app_en             ),
        .O_mc_app_addr           ( S_mc_app_addr           ),
        .O_mc_app_cmd            ( S_mc_app_cmd            ),
        .I_mc_app_rdy            ( S_mc_app_rdy            ),
        .O_mc_app_wdf_wren       ( S_mc_app_wdf_wren       ),
        .O_mc_app_wdf_data       ( S_mc_app_wdf_data       ),
        .O_mc_app_wdf_end        ( S_mc_app_wdf_end        ),
        .O_mc_app_wdf_mask       ( S_mc_app_wdf_mask_wide  ),
        .I_mc_app_wdf_rdy        ( S_mc_app_wdf_rdy        ),
        .I_mc_app_rd_data        ( S_mc_app_rd_data        ),
        .I_mc_app_rd_data_end    ( S_mc_app_rd_data_end    ),
        .I_mc_app_rd_data_valid  ( S_mc_app_rd_data_valid  )
    );

    // MC 适配层沿用旧版 32 位 mask 端口，当前 128 位 DDR 数据总线只需要 16 位。
    // 适配层固定输出全零，因此显式取低 16 位，消除隐式截断且不改变写选通行为。
    assign S_mc_app_wdf_mask = S_mc_app_wdf_mask_wide[15:0];



    // [硬件 IP] DDR 物理控制器负责校准和存储器电气时序，用户 RTL 不应直接修改它。
    ph1p35_324_ddr_wrapper u_ph1p35_324_ddr_wrapper(
        .I_sys_clk              ( I_sys_clk              ),
        .I_sys_rst_n            ( S_rst_n                ),

        .O_ddr_clk              ( S_ddr_clk              ),
        .O_init_calib_complete  ( S_init_calib_complete  ),
        .I_mc_app_addr          ( S_mc_app_addr          ),
        .I_mc_app_cmd           ( S_mc_app_cmd           ),
        .I_mc_app_en            ( S_mc_app_en            ),
        .I_mc_app_wdf_data      ( S_mc_app_wdf_data      ),
        .I_mc_app_wdf_end       ( S_mc_app_wdf_end       ),
        .I_mc_app_wdf_mask      ( S_mc_app_wdf_mask      ),
        .I_mc_app_wdf_wren      ( S_mc_app_wdf_wren      ),
        .O_mc_app_rd_data       ( S_mc_app_rd_data       ),
        .O_mc_app_rd_data_end   ( S_mc_app_rd_data_end   ),
        .O_mc_app_rd_data_valid ( S_mc_app_rd_data_valid ),
        .O_mc_app_rdy           ( S_mc_app_rdy           ),
        .O_mc_app_wdf_rdy       ( S_mc_app_wdf_rdy       ),

        .ddr_addr               ( ddr_addr               ),
        .ddr_ba                 ( ddr_ba                 ),
        .ddr_cke                ( ddr_cke                ),
        .ddr_odt                ( ddr_odt                ),
        .ddr_cs_n               ( ddr_cs_n               ),
        .ddr_ras_n              ( ddr_ras_n              ),
        .ddr_cas_n              ( ddr_cas_n              ),
        .ddr_we_n               ( ddr_we_n               ),
        .ddr_ck_p               ( ddr_ck_p               ),
        .ddr_ck_n               ( ddr_ck_n               ),
        .ddr_dm                 ( ddr_dm                 ),
        .ddr_dq                 ( ddr_dq                 ),
        .ddr_dqs_p              ( ddr_dqs_p              ),
        .ddr_dqs_n              ( ddr_dqs_n              )
    );



    // [诊断旁路] 只传递时间戳，测 RAW 帧首到 HDMI 帧首，绝不修改像素或 DDR 仲裁。
    generate
    if (ENABLE_LAT_DIAG != 0) begin : gen_latency
    // Current 720p HDMI PLL is ~75.002 MHz, not the old 52 MHz mode.
    ua_frame_latency #(.PIXEL_HZ(75000000),.FPS_ENABLE(1),.IMG_HEIGHT(IMG_HEIGHT)) u_frame_latency (
        .I_rst_n(S_hdmi_rst_n),
        .I_camera_clk(S_csi_rx_clk), .I_raw_start(S_raw_tuser),
        .I_ddr_clk(S_ddr_clk),
        .I_write_start(S_lat_write_start), .I_write_slot(S_lat_write_slot),
        .I_write_word(S_vi_ddr_wr_en),
        .I_read_start(S_lat_read_start), .I_read_slot(S_lat_read_slot),
        .I_pixel_clk(S_hdmi_pixel_clk), .I_display_start(S_hdmi_user),
        .I_display_end(S_display_frame_end),.I_underflow(S_pixel_underflow),
        .O_in_fps_bcd(S_in_fps_bcd),.O_out_fps_bcd(S_out_fps_bcd),.O_second_tick(S_second_tick),
        .O_valid(S_latency_valid), .O_delay_ms(S_latency_ms)
    );
    end else begin : gen_no_latency
        assign S_in_fps_bcd=0;assign S_out_fps_bcd=0;assign S_second_tick=0;
        assign S_latency_valid = 1'b0;
        assign S_latency_ms = 16'd0;
    end
    endgenerate

    uivtc #(
        .H_ActiveSize ( IMG_WIDTH ),
        .H_FrameSize  ( 1650 ),
        .H_SyncStart  ( 1390 ),
        .H_SyncEnd    ( 1430 ),
        .V_ActiveSize ( IMG_HEIGHT ),
        .V_FrameSize  ( 750  ),
        .V_SyncStart  ( 725  ),
        .V_SyncEnd    ( 730  )
    )u_hdmi_vtc(
        .I_vtc_rstn    ( S_hdmi_rst_n    ),
        .I_vtc_clk     ( S_hdmi_pixel_clk ),
        .O_vtc_vs      ( S_hdmi_vsync     ),
        .O_vtc_hs      ( S_hdmi_hsync     ),
        .O_vtc_de_valid( S_hdmi_de        ),
        .O_vtc_user    ( S_hdmi_user      ),
        .O_vtc_last    ( S_hdmi_last      )
    );

    // [显示叠加] 把视频像素与模式、延迟、运动和目标 OSD 合成后送 HDMI TX。
    generate
    if (ENABLE_OSD_DIAG != 0) begin : gen_osd
    hdmi_mixer_user #(
        .STREAM_DIAG_ENABLE(1),
        .MOTION_OVERLAY_ENABLE(1),
        .DIGIT_AUTO_ENABLE(1),
        .H_OFFSET   ( 0    ),
        .V_OFFSET   ( 0    ),
        .IMG_WIDTH  ( IMG_WIDTH ),
        .IMG_HEIGHT ( IMG_HEIGHT ),
        .DEBUG_MODE ( 0    ),
        .DISPLAY_BRIGHT_ENABLE(0) // ISP finishing already handles brightness; no duplicate 1.5x gain.
    )u_hdmi_mixer_user(
        .I_clk           ( S_hdmi_pixel_clk   ),
        .I_rst_n         ( S_hdmi_rst_n       ),
        .I_video_vsync   ( S_hdmi_vsync       ),
        .I_video_hsync   ( S_hdmi_hsync       ),
        .I_video_de      ( S_hdmi_de          ),
        .I_video_user    ( S_hdmi_user        ),
        .I_video_last    ( S_hdmi_last        ),
        .O_frame_end_observe(S_display_frame_end),
        .I_in_fps_bcd(S_in_fps_bcd),.I_out_fps_bcd(S_out_fps_bcd),.I_second_tick(S_second_tick),
        .I_aruco_update(gen_ae.S_aruco_display_update),
        .I_debug_status  ( S_hdmi_debug_status),
        .I_algo_mode     ( gen_ae.S_algo_mode_s1    ),
        .I_motion_valid  ( gen_ae.S_motion_valid_pe ),
        .I_motion_view(gen_ae.S_motion_view_hdmi),.I_motion_view_valid(gen_ae.S_motion_view_valid_hdmi),
        .I_motion_count  ( gen_ae.S_motion_count_s1 ),
        .I_motion_enable ( gen_ae.S_detect_en_hdmi_s1[0] ),
        .I_track_valid   ( gen_ae.S_track_valid_pe  ),
        .I_track_cnt     ( gen_ae.S_track_cnt_s1    ),
        .I_track_enable  ( gen_ae.S_detect_en_hdmi_s1[1] ),
         .I_t0_v          ( gen_ae.S_t0_v_s1         ),
         .I_t0_x          ( gen_ae.S_t0_x_s1         ),  .I_t0_y( gen_ae.S_t0_y_s1 ),
         .I_t0_shape      ( gen_ae.S_t0_sh_s1        ),
         .I_t0_xmin       ( gen_ae.S_t0_xmin_s1      ), .I_t0_xmax( gen_ae.S_t0_xmax_s1 ),
         .I_t0_ymin       ( gen_ae.S_t0_ymin_s1      ), .I_t0_ymax( gen_ae.S_t0_ymax_s1 ),
         .I_t1_v          ( gen_ae.S_t1_v_s1         ),
         .I_t1_x          ( gen_ae.S_t1_x_s1         ),  .I_t1_y( gen_ae.S_t1_y_s1 ),
         .I_t1_shape      ( gen_ae.S_t1_sh_s1        ),
         .I_t1_xmin       ( gen_ae.S_t1_xmin_s1      ), .I_t1_xmax( gen_ae.S_t1_xmax_s1 ),
         .I_t1_ymin       ( gen_ae.S_t1_ymin_s1      ), .I_t1_ymax( gen_ae.S_t1_ymax_s1 ),
         .I_t2_v          ( gen_ae.S_t2_v_s1         ),
         .I_t2_x          ( gen_ae.S_t2_x_s1         ),  .I_t2_y( gen_ae.S_t2_y_s1 ),
         .I_t2_shape      ( gen_ae.S_t2_sh_s1        ),
         .I_t2_xmin       ( gen_ae.S_t2_xmin_s1      ), .I_t2_xmax( gen_ae.S_t2_xmax_s1 ),
         .I_t2_ymin       ( gen_ae.S_t2_ymin_s1      ), .I_t2_ymax( gen_ae.S_t2_ymax_s1 ),
        .I_digit_valid   ( gen_ae.S_digit_valid_pe ),
        .I_digit_view(gen_ae.S_digit_view_hdmi),.I_digit_view_valid(gen_ae.S_digit_view_valid_hdmi),
        .I_digit_id      ( gen_ae.S_digit_id_s1 ),
        .I_digit_confidence( gen_ae.S_digit_confidence_s1 ),
        .I_digit_enable  ( gen_ae.S_detect_en_hdmi_s1[3] ),
        .I_hand_valid    ( gen_ae.S_hand_valid_pe ),
        .I_hand_id       ( gen_ae.S_hand_id_s1 ),
        .I_hand_tips     ( gen_ae.S_hand_tips_s1 ),
        .I_hand_box_valid(gen_ae.S_hand_box_s1[40]),
        .I_hand_xmin     ( gen_ae.S_hand_box_s1[39:30] ),
        .I_hand_xmax     ( gen_ae.S_hand_box_s1[29:20] ),
        .I_hand_ymin     ( gen_ae.S_hand_box_s1[19:10] ),
        .I_hand_ymax     ( gen_ae.S_hand_box_s1[9:0] ),
        .I_hand_enable   ( gen_ae.S_detect_en_hdmi_s1[2] ),
        .I_aruco_enable  ( gen_ae.S_aruco_enable_hdmi_s1 ),
        // Result bank is declared inside gen_ae, not at module scope.
        // An unqualified name silently becomes an undriven one-bit net.
        .I_aruco_valid   ( gen_ae.S_aruco_display_valid ),
        .I_aruco_axes    ( gen_ae.S_aruco_display_axes ),
        .I_aruco_id_bcd  ( gen_ae.S_aruco_display_id_bcd ),
        .I_aruco_corner0 ( gen_ae.S_aruco_display_corner0 ),
        .I_aruco_corner1 ( gen_ae.S_aruco_display_corner1 ),
        .I_aruco_corner2 ( gen_ae.S_aruco_display_corner2 ),
        .I_aruco_corner3 ( gen_ae.S_aruco_display_corner3 ),
        .I_aruco_edge0   ( gen_ae.S_aruco_display_edge0 ),
        .I_aruco_edge1   ( gen_ae.S_aruco_display_edge1 ),
        .I_aruco_edge2   ( gen_ae.S_aruco_display_edge2 ),
        .I_aruco_edge3   ( gen_ae.S_aruco_display_edge3 ),
        .I_cam_frame_cnt ( gen_ae.S_cam_frame_cnt_s1),
        .I_latency_valid( S_latency_valid),
        .I_latency_ms   ( S_latency_ms),
        .O_video_rd_en   ( S_hdmi_window_rd_en),
        .I_video_rd_data ( S_video_rd_data    ),
        .O_hdmi_vsync    ( S_hdmi_out_vsync   ),
        .O_hdmi_hsync    ( S_hdmi_out_hsync   ),
        .O_hdmi_de       ( S_hdmi_out_de      ),
        .O_hdmi_data     ( S_hdmi_out_data    ),
        .O_hdmi_clean_data( S_hdmi_clean_data )
    );
    end else begin : gen_no_osd
        assign S_display_frame_end = 1'b0;
        // Diagnostic video passthrough: retain the DDR read request and VTC
        // timing while removing only the optional OSD arithmetic.
        assign S_hdmi_window_rd_en = S_hdmi_de;
        assign S_hdmi_out_vsync = S_hdmi_vsync;
        assign S_hdmi_out_hsync = S_hdmi_hsync;
        assign S_hdmi_out_de    = S_hdmi_de;
        assign S_hdmi_out_data  = S_video_rd_data;
        assign S_hdmi_clean_data = S_video_rd_data;
    end
    endgenerate

    wire [23:0] S_hdmi_colour_checked_data;
    ua_shared_colour_diagnostic_embedded u_colour_path_diagnostic (
        .I_clk(S_hdmi_pixel_clk),.I_rst_n(S_hdmi_rst_n),
        // Normal camera build. Dedicated diagnostic bits remain available.
        .I_enable(1'b0),
        .I_vs(S_hdmi_out_vsync),.I_de(S_hdmi_out_de),
        .I_hdmi_rgb(S_hdmi_out_data),.I_clean_rgb(S_hdmi_clean_data),
        .O_hdmi_rgb(S_hdmi_colour_checked_data),.O_clean_rgb()
    );

    hdmi_tx u_hdmi_tx(
        .I_pixel_clk        ( S_hdmi_pixel_clk  ),
        .I_serial_clk       ( S_hdmi_serial_clk ),
        .I_rst              ( ~S_hdmi_rst_n     ),
        .I_key_in           ( 1'b1              ), // 低有效按键：未使用时保持释放
        .I_edid_read_trig   ( 1'b0              ),
        .O_edid_read_valid  (                   ),
        .O_edid_read_data   (                   ),
        .I_video_rgb_enable ( 1'b1              ),
        .I_video_in_vs      ( S_hdmi_out_vsync  ),
        .I_video_in_de      ( S_hdmi_out_de     ),
        .I_video_in_user    ( 1'b0              ),
        .I_video_in_valid   ( 1'b0              ),
        .I_video_in_last    ( 1'b0              ),
        .O_video_in_ready   (                   ),
        .I_video_in_data    ( S_hdmi_colour_checked_data ),
        .I_audio_valid      ( 1'b0              ),
        .I_audio_left_data  ( 24'd0             ),
        .I_audio_right_data ( 24'd0             ),
        .I_i2s_BCLK         ( 1'b0              ),
        .I_i2s_LRCK         ( 1'b0              ),
        .I_i2s_DOUT         ( 1'b0              ),
        .O_ddc_scl          (                   ),
        .IO_ddc_sda         ( S_hdmi_ddc_sda   ),
        .O_hdmi_clk_p       (                   ),
        .O_hdmi_tx_p        (                   ),
        .O_tmds_ch0_p       ( O_tmds_ch0_p      ),
        .O_tmds_ch1_p       ( O_tmds_ch1_p      ),
        .O_tmds_ch2_p       ( O_tmds_ch2_p      ),
        .O_tmds_clk_p       ( O_tmds_clk_p      )
    );


endmodule
