`ifndef UA_EXPOSURE_SEG6_V
`define UA_EXPOSURE_SEG6_V

// ============================================================================
// ua_exposure_seg6 : six-digit active-low seven-segment status display
//
// The product exposure controller has sixteen fixed AE/AG profiles.  This
// small scanner displays the selected profile as a decimal value from 00 to
// 15.  The board's digit wiring is reversed relative to the logical number:
// seg_sel[0] is the tens position and seg_sel[1] is the units position; the other
// four digits remain blank.  Keeping the decode local avoids division,
// modulo, and a large numeric formatter in the video path.
//
// Clock domain: S_100m_clk.  The top level supplies I_level through a pair of
// synchronizing flip-flops because ua_auto_exposure runs at 24 MHz.
// Electrical convention follows the supplied static seven-segment example:
// O_seg_sel and O_seg_led are active low, and O_seg_led is {dp,g,f,e,d,c,b,a}.
// ============================================================================
`timescale 1ns/1ps
module ua_exposure_seg6 #(
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

    // Active-low codes for {dp,g,f,e,d,c,b,a}, matching the board example.
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

    // 100 MHz / (2 * 50000) = 1 kHz digit alternation.  Each digit is
    // refreshed at 500 Hz, well above visible flicker on the board display.
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            scan_count <= 32'd0;
            scan_digit <= 1'b0;
            O_seg_sel  <= 6'b111111;
            O_seg_led  <= 8'hff;
        end else if (scan_count >= SCAN_LIMIT) begin
            scan_count <= 32'd0;
            scan_digit <= ~scan_digit;
            // Use the digit that becomes active after this edge.  Updating
            // select and segment outputs in this same sequential block keeps
            // the two buses aligned and avoids combinational ghosting.
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

`endif // UA_EXPOSURE_SEG6_V
