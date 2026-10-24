`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// SC500 analogue-gain lookup.
//
// I is the offset code supplied by uicfgcs500_720p (I_ag - 16).  The SC500CS
// data sheet defines four 32-step analogue-gain bands:
//   0x0320..0x033f = 1.000x..1.969x
//   0x0720..0x073f = 2.000x..3.938x
//   0x0f20..0x0f3f = 4.000x..7.875x
//   0x1f20..0x1f3f = 8.000x..15.750x
// The old project stopped at 0x0f29 (5.125x), leaving the legal upper range
// unused and making dark scenes remain dark after exposure reached VTS-10.
//////////////////////////////////////////////////////////////////////////////////
module SC500GainTbl(
    input             I_clk,
    input             I_rstn,
    input      [6:0]  I,
    output reg [15:0] O
);

    // Keep the original one-cycle registered interface so the I2C table's
    // timing is unchanged. Each band differs only in ANA GAIN[7:4].
    always @(posedge I_clk) begin
        case (I[6:5])
            2'b00: O <= {8'h03, 8'h20 + I[4:0]};
            2'b01: O <= {8'h07, 8'h20 + I[4:0]};
            2'b10: O <= {8'h0f, 8'h20 + I[4:0]};
            2'b11: O <= {8'h1f, 8'h20 + I[4:0]};
        endcase
    end

endmodule
