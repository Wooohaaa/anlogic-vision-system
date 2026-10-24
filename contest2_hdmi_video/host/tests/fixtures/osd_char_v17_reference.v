// OSD 16x16 1-bit character ROM.
// ASCII glyphs are generated from alexfru/512_8 Bold (Public Domain).
// The 8x8 source bitmap is doubled horizontally and vertically so the
// existing 16x16 OSD cell and pixel timing remain unchanged.
// CHAR_AN/CHAR_LU are project-specific glyphs and are intentionally kept.
module osd_char_v17_reference (
    input wire [7:0] I_char,
    input wire [3:0] I_row,
    output reg [15:0] O_row_bits
);

    localparam CHAR_AN = 8'h80;
    localparam CHAR_LU = 8'h81;

    function [15:0] F_bold_expand;
        input [7:0] I_bits;
        begin
            F_bold_expand = {
                {2{I_bits[7]}}, {2{I_bits[6]}},
                {2{I_bits[5]}}, {2{I_bits[4]}},
                {2{I_bits[3]}}, {2{I_bits[2]}},
                {2{I_bits[1]}}, {2{I_bits[0]}}
            };
        end
    endfunction

    // 512_8 stores eight rows per code point.  Only printable ASCII is
    // needed by the current OSD, but keeping the complete range makes
    // the library usable for future debug strings without RTL changes.
    function [7:0] F_bold_row;
        input [7:0] I_char_code;
        input [2:0] I_row8;
        begin
            F_bold_row = 8'h00;
            case (I_char_code)
                8'h20: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'h00;
                        3'd4: F_bold_row = 8'h00;
                        3'd5: F_bold_row = 8'h00;
                        3'd6: F_bold_row = 8'h00;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h21: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h30;
                        3'd2: F_bold_row = 8'h78;
                        3'd3: F_bold_row = 8'h78;
                        3'd4: F_bold_row = 8'h30;
                        3'd5: F_bold_row = 8'h00;
                        3'd6: F_bold_row = 8'h30;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h22: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hC6;
                        3'd2: F_bold_row = 8'hC6;
                        3'd3: F_bold_row = 8'h6C;
                        3'd4: F_bold_row = 8'h00;
                        3'd5: F_bold_row = 8'h00;
                        3'd6: F_bold_row = 8'h00;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h23: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h6C;
                        3'd2: F_bold_row = 8'hFE;
                        3'd3: F_bold_row = 8'h6C;
                        3'd4: F_bold_row = 8'h6C;
                        3'd5: F_bold_row = 8'hFE;
                        3'd6: F_bold_row = 8'h6C;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h24: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h10;
                        3'd1: F_bold_row = 8'h7C;
                        3'd2: F_bold_row = 8'hD0;
                        3'd3: F_bold_row = 8'h7C;
                        3'd4: F_bold_row = 8'h16;
                        3'd5: F_bold_row = 8'hD6;
                        3'd6: F_bold_row = 8'h7C;
                        3'd7: F_bold_row = 8'h10;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h25: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h44;
                        3'd2: F_bold_row = 8'hE8;
                        3'd3: F_bold_row = 8'h50;
                        3'd4: F_bold_row = 8'h28;
                        3'd5: F_bold_row = 8'h5C;
                        3'd6: F_bold_row = 8'h88;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h26: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h30;
                        3'd2: F_bold_row = 8'h58;
                        3'd3: F_bold_row = 8'h72;
                        3'd4: F_bold_row = 8'hDC;
                        3'd5: F_bold_row = 8'hCC;
                        3'd6: F_bold_row = 8'h7A;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h27: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h18;
                        3'd2: F_bold_row = 8'h18;
                        3'd3: F_bold_row = 8'h30;
                        3'd4: F_bold_row = 8'h00;
                        3'd5: F_bold_row = 8'h00;
                        3'd6: F_bold_row = 8'h00;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h28: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h0C;
                        3'd2: F_bold_row = 8'h18;
                        3'd3: F_bold_row = 8'h18;
                        3'd4: F_bold_row = 8'h18;
                        3'd5: F_bold_row = 8'h18;
                        3'd6: F_bold_row = 8'h0C;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h29: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h60;
                        3'd2: F_bold_row = 8'h30;
                        3'd3: F_bold_row = 8'h30;
                        3'd4: F_bold_row = 8'h30;
                        3'd5: F_bold_row = 8'h30;
                        3'd6: F_bold_row = 8'h60;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h2A: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h48;
                        3'd3: F_bold_row = 8'h30;
                        3'd4: F_bold_row = 8'hFC;
                        3'd5: F_bold_row = 8'h30;
                        3'd6: F_bold_row = 8'h48;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h2B: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h30;
                        3'd3: F_bold_row = 8'h30;
                        3'd4: F_bold_row = 8'hFC;
                        3'd5: F_bold_row = 8'h30;
                        3'd6: F_bold_row = 8'h30;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h2C: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'h00;
                        3'd4: F_bold_row = 8'h00;
                        3'd5: F_bold_row = 8'h18;
                        3'd6: F_bold_row = 8'h18;
                        3'd7: F_bold_row = 8'h30;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h2D: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'h00;
                        3'd4: F_bold_row = 8'h7C;
                        3'd5: F_bold_row = 8'h00;
                        3'd6: F_bold_row = 8'h00;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h2E: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'h00;
                        3'd4: F_bold_row = 8'h00;
                        3'd5: F_bold_row = 8'h00;
                        3'd6: F_bold_row = 8'h30;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h2F: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h06;
                        3'd2: F_bold_row = 8'h0C;
                        3'd3: F_bold_row = 8'h18;
                        3'd4: F_bold_row = 8'h30;
                        3'd5: F_bold_row = 8'h60;
                        3'd6: F_bold_row = 8'hC0;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h30: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h7C;
                        3'd2: F_bold_row = 8'hCE;
                        3'd3: F_bold_row = 8'hD6;
                        3'd4: F_bold_row = 8'hD6;
                        3'd5: F_bold_row = 8'hE6;
                        3'd6: F_bold_row = 8'h7C;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h31: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h30;
                        3'd2: F_bold_row = 8'h70;
                        3'd3: F_bold_row = 8'hF0;
                        3'd4: F_bold_row = 8'h30;
                        3'd5: F_bold_row = 8'h30;
                        3'd6: F_bold_row = 8'hFC;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h32: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h7C;
                        3'd2: F_bold_row = 8'hC6;
                        3'd3: F_bold_row = 8'h06;
                        3'd4: F_bold_row = 8'h7C;
                        3'd5: F_bold_row = 8'hC0;
                        3'd6: F_bold_row = 8'hFE;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h33: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h7C;
                        3'd2: F_bold_row = 8'hC6;
                        3'd3: F_bold_row = 8'h1C;
                        3'd4: F_bold_row = 8'h06;
                        3'd5: F_bold_row = 8'hC6;
                        3'd6: F_bold_row = 8'h7C;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h34: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h3C;
                        3'd2: F_bold_row = 8'h6C;
                        3'd3: F_bold_row = 8'hCC;
                        3'd4: F_bold_row = 8'hFE;
                        3'd5: F_bold_row = 8'h0C;
                        3'd6: F_bold_row = 8'h0C;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h35: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hFE;
                        3'd2: F_bold_row = 8'hC0;
                        3'd3: F_bold_row = 8'hFC;
                        3'd4: F_bold_row = 8'h06;
                        3'd5: F_bold_row = 8'hC6;
                        3'd6: F_bold_row = 8'h7C;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h36: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h7C;
                        3'd2: F_bold_row = 8'hC0;
                        3'd3: F_bold_row = 8'hFC;
                        3'd4: F_bold_row = 8'hC6;
                        3'd5: F_bold_row = 8'hC6;
                        3'd6: F_bold_row = 8'h7C;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h37: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hFE;
                        3'd2: F_bold_row = 8'h06;
                        3'd3: F_bold_row = 8'h0C;
                        3'd4: F_bold_row = 8'h0C;
                        3'd5: F_bold_row = 8'h18;
                        3'd6: F_bold_row = 8'h18;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h38: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h7C;
                        3'd2: F_bold_row = 8'hC6;
                        3'd3: F_bold_row = 8'h7C;
                        3'd4: F_bold_row = 8'hC6;
                        3'd5: F_bold_row = 8'hC6;
                        3'd6: F_bold_row = 8'h7C;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h39: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h7C;
                        3'd2: F_bold_row = 8'hC6;
                        3'd3: F_bold_row = 8'hC6;
                        3'd4: F_bold_row = 8'h7E;
                        3'd5: F_bold_row = 8'h06;
                        3'd6: F_bold_row = 8'h7C;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h3A: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'h30;
                        3'd4: F_bold_row = 8'h00;
                        3'd5: F_bold_row = 8'h00;
                        3'd6: F_bold_row = 8'h30;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h3B: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'h30;
                        3'd4: F_bold_row = 8'h00;
                        3'd5: F_bold_row = 8'h30;
                        3'd6: F_bold_row = 8'h30;
                        3'd7: F_bold_row = 8'h60;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h3C: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h18;
                        3'd3: F_bold_row = 8'h30;
                        3'd4: F_bold_row = 8'h60;
                        3'd5: F_bold_row = 8'h30;
                        3'd6: F_bold_row = 8'h18;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h3D: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'h7C;
                        3'd4: F_bold_row = 8'h00;
                        3'd5: F_bold_row = 8'h7C;
                        3'd6: F_bold_row = 8'h00;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h3E: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h30;
                        3'd3: F_bold_row = 8'h18;
                        3'd4: F_bold_row = 8'h0C;
                        3'd5: F_bold_row = 8'h18;
                        3'd6: F_bold_row = 8'h30;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h3F: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h7C;
                        3'd2: F_bold_row = 8'hC6;
                        3'd3: F_bold_row = 8'h0C;
                        3'd4: F_bold_row = 8'h18;
                        3'd5: F_bold_row = 8'h00;
                        3'd6: F_bold_row = 8'h18;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h40: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h7C;
                        3'd2: F_bold_row = 8'hCE;
                        3'd3: F_bold_row = 8'hDA;
                        3'd4: F_bold_row = 8'hCE;
                        3'd5: F_bold_row = 8'hC0;
                        3'd6: F_bold_row = 8'h7E;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h41: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h10;
                        3'd2: F_bold_row = 8'h38;
                        3'd3: F_bold_row = 8'h6C;
                        3'd4: F_bold_row = 8'h6C;
                        3'd5: F_bold_row = 8'hFE;
                        3'd6: F_bold_row = 8'hC6;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h42: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hFC;
                        3'd2: F_bold_row = 8'h66;
                        3'd3: F_bold_row = 8'h7C;
                        3'd4: F_bold_row = 8'h66;
                        3'd5: F_bold_row = 8'h66;
                        3'd6: F_bold_row = 8'hFC;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h43: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h7C;
                        3'd2: F_bold_row = 8'hC6;
                        3'd3: F_bold_row = 8'hC0;
                        3'd4: F_bold_row = 8'hC0;
                        3'd5: F_bold_row = 8'hC6;
                        3'd6: F_bold_row = 8'h7C;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h44: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hFC;
                        3'd2: F_bold_row = 8'h66;
                        3'd3: F_bold_row = 8'h66;
                        3'd4: F_bold_row = 8'h66;
                        3'd5: F_bold_row = 8'h66;
                        3'd6: F_bold_row = 8'hFC;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h45: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hFE;
                        3'd2: F_bold_row = 8'h62;
                        3'd3: F_bold_row = 8'h78;
                        3'd4: F_bold_row = 8'h60;
                        3'd5: F_bold_row = 8'h62;
                        3'd6: F_bold_row = 8'hFE;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h46: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hFE;
                        3'd2: F_bold_row = 8'h62;
                        3'd3: F_bold_row = 8'h78;
                        3'd4: F_bold_row = 8'h60;
                        3'd5: F_bold_row = 8'h60;
                        3'd6: F_bold_row = 8'hF0;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h47: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h7C;
                        3'd2: F_bold_row = 8'hC6;
                        3'd3: F_bold_row = 8'hC0;
                        3'd4: F_bold_row = 8'hCE;
                        3'd5: F_bold_row = 8'hC6;
                        3'd6: F_bold_row = 8'h7C;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h48: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hC6;
                        3'd2: F_bold_row = 8'hC6;
                        3'd3: F_bold_row = 8'hFE;
                        3'd4: F_bold_row = 8'hC6;
                        3'd5: F_bold_row = 8'hC6;
                        3'd6: F_bold_row = 8'hC6;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h49: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hFC;
                        3'd2: F_bold_row = 8'h30;
                        3'd3: F_bold_row = 8'h30;
                        3'd4: F_bold_row = 8'h30;
                        3'd5: F_bold_row = 8'h30;
                        3'd6: F_bold_row = 8'hFC;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h4A: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h1E;
                        3'd2: F_bold_row = 8'h0C;
                        3'd3: F_bold_row = 8'h0C;
                        3'd4: F_bold_row = 8'h0C;
                        3'd5: F_bold_row = 8'hCC;
                        3'd6: F_bold_row = 8'h78;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h4B: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hE6;
                        3'd2: F_bold_row = 8'h6C;
                        3'd3: F_bold_row = 8'h78;
                        3'd4: F_bold_row = 8'h6C;
                        3'd5: F_bold_row = 8'h66;
                        3'd6: F_bold_row = 8'hE6;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h4C: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hF0;
                        3'd2: F_bold_row = 8'h60;
                        3'd3: F_bold_row = 8'h60;
                        3'd4: F_bold_row = 8'h60;
                        3'd5: F_bold_row = 8'h64;
                        3'd6: F_bold_row = 8'hFC;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h4D: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hC6;
                        3'd2: F_bold_row = 8'hEE;
                        3'd3: F_bold_row = 8'hFE;
                        3'd4: F_bold_row = 8'hD6;
                        3'd5: F_bold_row = 8'hC6;
                        3'd6: F_bold_row = 8'hC6;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h4E: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hC6;
                        3'd2: F_bold_row = 8'hE6;
                        3'd3: F_bold_row = 8'hD6;
                        3'd4: F_bold_row = 8'hD6;
                        3'd5: F_bold_row = 8'hCE;
                        3'd6: F_bold_row = 8'hC6;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h4F: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h7C;
                        3'd2: F_bold_row = 8'hC6;
                        3'd3: F_bold_row = 8'hC6;
                        3'd4: F_bold_row = 8'hC6;
                        3'd5: F_bold_row = 8'hC6;
                        3'd6: F_bold_row = 8'h7C;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h50: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hFC;
                        3'd2: F_bold_row = 8'h66;
                        3'd3: F_bold_row = 8'h66;
                        3'd4: F_bold_row = 8'h7C;
                        3'd5: F_bold_row = 8'h60;
                        3'd6: F_bold_row = 8'hF0;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h51: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h7C;
                        3'd2: F_bold_row = 8'hC6;
                        3'd3: F_bold_row = 8'hC6;
                        3'd4: F_bold_row = 8'hC6;
                        3'd5: F_bold_row = 8'hDE;
                        3'd6: F_bold_row = 8'h7C;
                        3'd7: F_bold_row = 8'h06;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h52: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hFC;
                        3'd2: F_bold_row = 8'h66;
                        3'd3: F_bold_row = 8'h66;
                        3'd4: F_bold_row = 8'h7C;
                        3'd5: F_bold_row = 8'h66;
                        3'd6: F_bold_row = 8'hF6;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h53: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h7C;
                        3'd2: F_bold_row = 8'hC0;
                        3'd3: F_bold_row = 8'h7C;
                        3'd4: F_bold_row = 8'h06;
                        3'd5: F_bold_row = 8'hC6;
                        3'd6: F_bold_row = 8'h7C;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h54: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hFC;
                        3'd2: F_bold_row = 8'hB4;
                        3'd3: F_bold_row = 8'h30;
                        3'd4: F_bold_row = 8'h30;
                        3'd5: F_bold_row = 8'h30;
                        3'd6: F_bold_row = 8'h78;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h55: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hC6;
                        3'd2: F_bold_row = 8'hC6;
                        3'd3: F_bold_row = 8'hC6;
                        3'd4: F_bold_row = 8'hC6;
                        3'd5: F_bold_row = 8'hC6;
                        3'd6: F_bold_row = 8'h7C;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h56: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hC6;
                        3'd2: F_bold_row = 8'hC6;
                        3'd3: F_bold_row = 8'h6C;
                        3'd4: F_bold_row = 8'h6C;
                        3'd5: F_bold_row = 8'h38;
                        3'd6: F_bold_row = 8'h10;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h57: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hC6;
                        3'd2: F_bold_row = 8'hC6;
                        3'd3: F_bold_row = 8'hD6;
                        3'd4: F_bold_row = 8'hD6;
                        3'd5: F_bold_row = 8'h6C;
                        3'd6: F_bold_row = 8'h6C;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h58: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hC6;
                        3'd2: F_bold_row = 8'h6C;
                        3'd3: F_bold_row = 8'h38;
                        3'd4: F_bold_row = 8'h38;
                        3'd5: F_bold_row = 8'h6C;
                        3'd6: F_bold_row = 8'hC6;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h59: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hCC;
                        3'd2: F_bold_row = 8'hCC;
                        3'd3: F_bold_row = 8'h78;
                        3'd4: F_bold_row = 8'h30;
                        3'd5: F_bold_row = 8'h30;
                        3'd6: F_bold_row = 8'h78;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h5A: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hFE;
                        3'd2: F_bold_row = 8'hCC;
                        3'd3: F_bold_row = 8'h18;
                        3'd4: F_bold_row = 8'h30;
                        3'd5: F_bold_row = 8'h66;
                        3'd6: F_bold_row = 8'hFE;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h5B: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h3E;
                        3'd2: F_bold_row = 8'h30;
                        3'd3: F_bold_row = 8'h30;
                        3'd4: F_bold_row = 8'h30;
                        3'd5: F_bold_row = 8'h30;
                        3'd6: F_bold_row = 8'h3E;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h5C: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hC0;
                        3'd2: F_bold_row = 8'h60;
                        3'd3: F_bold_row = 8'h30;
                        3'd4: F_bold_row = 8'h18;
                        3'd5: F_bold_row = 8'h0C;
                        3'd6: F_bold_row = 8'h06;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h5D: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hF8;
                        3'd2: F_bold_row = 8'h18;
                        3'd3: F_bold_row = 8'h18;
                        3'd4: F_bold_row = 8'h18;
                        3'd5: F_bold_row = 8'h18;
                        3'd6: F_bold_row = 8'hF8;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h5E: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h38;
                        3'd2: F_bold_row = 8'h6C;
                        3'd3: F_bold_row = 8'h00;
                        3'd4: F_bold_row = 8'h00;
                        3'd5: F_bold_row = 8'h00;
                        3'd6: F_bold_row = 8'h00;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h5F: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'h00;
                        3'd4: F_bold_row = 8'h00;
                        3'd5: F_bold_row = 8'h00;
                        3'd6: F_bold_row = 8'h00;
                        3'd7: F_bold_row = 8'hFE;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h60: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h30;
                        3'd2: F_bold_row = 8'h18;
                        3'd3: F_bold_row = 8'h00;
                        3'd4: F_bold_row = 8'h00;
                        3'd5: F_bold_row = 8'h00;
                        3'd6: F_bold_row = 8'h00;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h61: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'h7A;
                        3'd4: F_bold_row = 8'hCC;
                        3'd5: F_bold_row = 8'hCC;
                        3'd6: F_bold_row = 8'h76;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h62: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hE0;
                        3'd2: F_bold_row = 8'h60;
                        3'd3: F_bold_row = 8'h7C;
                        3'd4: F_bold_row = 8'h66;
                        3'd5: F_bold_row = 8'h66;
                        3'd6: F_bold_row = 8'hDC;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h63: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'h3C;
                        3'd4: F_bold_row = 8'h60;
                        3'd5: F_bold_row = 8'h60;
                        3'd6: F_bold_row = 8'h3C;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h64: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h1C;
                        3'd2: F_bold_row = 8'h0C;
                        3'd3: F_bold_row = 8'h7C;
                        3'd4: F_bold_row = 8'hCC;
                        3'd5: F_bold_row = 8'hCC;
                        3'd6: F_bold_row = 8'h76;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h65: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'h78;
                        3'd4: F_bold_row = 8'h9C;
                        3'd5: F_bold_row = 8'hE0;
                        3'd6: F_bold_row = 8'h78;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h66: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h3C;
                        3'd2: F_bold_row = 8'h66;
                        3'd3: F_bold_row = 8'hF0;
                        3'd4: F_bold_row = 8'h60;
                        3'd5: F_bold_row = 8'h60;
                        3'd6: F_bold_row = 8'hF0;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h67: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'h76;
                        3'd4: F_bold_row = 8'hCC;
                        3'd5: F_bold_row = 8'h7C;
                        3'd6: F_bold_row = 8'h0C;
                        3'd7: F_bold_row = 8'h78;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h68: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hE0;
                        3'd2: F_bold_row = 8'h60;
                        3'd3: F_bold_row = 8'h6C;
                        3'd4: F_bold_row = 8'h76;
                        3'd5: F_bold_row = 8'h66;
                        3'd6: F_bold_row = 8'hE6;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h69: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h30;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'h70;
                        3'd4: F_bold_row = 8'h30;
                        3'd5: F_bold_row = 8'h30;
                        3'd6: F_bold_row = 8'h38;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h6A: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h18;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'h38;
                        3'd4: F_bold_row = 8'h18;
                        3'd5: F_bold_row = 8'h18;
                        3'd6: F_bold_row = 8'h18;
                        3'd7: F_bold_row = 8'h70;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h6B: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'hE0;
                        3'd2: F_bold_row = 8'h60;
                        3'd3: F_bold_row = 8'h6C;
                        3'd4: F_bold_row = 8'h78;
                        3'd5: F_bold_row = 8'h6C;
                        3'd6: F_bold_row = 8'hE6;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h6C: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h70;
                        3'd2: F_bold_row = 8'h30;
                        3'd3: F_bold_row = 8'h30;
                        3'd4: F_bold_row = 8'h30;
                        3'd5: F_bold_row = 8'h30;
                        3'd6: F_bold_row = 8'h38;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h6D: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'hEC;
                        3'd4: F_bold_row = 8'hD6;
                        3'd5: F_bold_row = 8'hD6;
                        3'd6: F_bold_row = 8'hC6;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h6E: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'hDC;
                        3'd4: F_bold_row = 8'h76;
                        3'd5: F_bold_row = 8'h66;
                        3'd6: F_bold_row = 8'h66;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h6F: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'h78;
                        3'd4: F_bold_row = 8'hCC;
                        3'd5: F_bold_row = 8'hCC;
                        3'd6: F_bold_row = 8'h78;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h70: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'hDC;
                        3'd4: F_bold_row = 8'h66;
                        3'd5: F_bold_row = 8'h7C;
                        3'd6: F_bold_row = 8'h60;
                        3'd7: F_bold_row = 8'hF0;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h71: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'h76;
                        3'd4: F_bold_row = 8'hCC;
                        3'd5: F_bold_row = 8'h7C;
                        3'd6: F_bold_row = 8'h0C;
                        3'd7: F_bold_row = 8'h1E;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h72: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'hDC;
                        3'd4: F_bold_row = 8'h66;
                        3'd5: F_bold_row = 8'h60;
                        3'd6: F_bold_row = 8'hF0;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h73: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'h78;
                        3'd4: F_bold_row = 8'hE0;
                        3'd5: F_bold_row = 8'h1C;
                        3'd6: F_bold_row = 8'hF8;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h74: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h60;
                        3'd3: F_bold_row = 8'hF8;
                        3'd4: F_bold_row = 8'h60;
                        3'd5: F_bold_row = 8'h6C;
                        3'd6: F_bold_row = 8'h38;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h75: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'hCC;
                        3'd4: F_bold_row = 8'hCC;
                        3'd5: F_bold_row = 8'hCC;
                        3'd6: F_bold_row = 8'h76;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h76: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'hC6;
                        3'd4: F_bold_row = 8'h6C;
                        3'd5: F_bold_row = 8'h38;
                        3'd6: F_bold_row = 8'h10;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h77: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'hC6;
                        3'd4: F_bold_row = 8'hD6;
                        3'd5: F_bold_row = 8'hD6;
                        3'd6: F_bold_row = 8'h6C;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h78: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'hCC;
                        3'd4: F_bold_row = 8'h78;
                        3'd5: F_bold_row = 8'h78;
                        3'd6: F_bold_row = 8'hCC;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h79: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'hCC;
                        3'd4: F_bold_row = 8'hCC;
                        3'd5: F_bold_row = 8'h7C;
                        3'd6: F_bold_row = 8'h0C;
                        3'd7: F_bold_row = 8'h78;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h7A: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h00;
                        3'd2: F_bold_row = 8'h00;
                        3'd3: F_bold_row = 8'h7C;
                        3'd4: F_bold_row = 8'h18;
                        3'd5: F_bold_row = 8'h30;
                        3'd6: F_bold_row = 8'h7C;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h7B: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h1C;
                        3'd2: F_bold_row = 8'h30;
                        3'd3: F_bold_row = 8'hE0;
                        3'd4: F_bold_row = 8'h30;
                        3'd5: F_bold_row = 8'h30;
                        3'd6: F_bold_row = 8'h1C;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h7C: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h30;
                        3'd2: F_bold_row = 8'h30;
                        3'd3: F_bold_row = 8'h30;
                        3'd4: F_bold_row = 8'h30;
                        3'd5: F_bold_row = 8'h30;
                        3'd6: F_bold_row = 8'h30;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h7D: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h70;
                        3'd2: F_bold_row = 8'h18;
                        3'd3: F_bold_row = 8'h0E;
                        3'd4: F_bold_row = 8'h18;
                        3'd5: F_bold_row = 8'h18;
                        3'd6: F_bold_row = 8'h70;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                8'h7E: begin
                    case (I_row8)
                        3'd0: F_bold_row = 8'h00;
                        3'd1: F_bold_row = 8'h76;
                        3'd2: F_bold_row = 8'hDC;
                        3'd3: F_bold_row = 8'h00;
                        3'd4: F_bold_row = 8'h00;
                        3'd5: F_bold_row = 8'h00;
                        3'd6: F_bold_row = 8'h00;
                        3'd7: F_bold_row = 8'h00;
                        default: F_bold_row = 8'h00;
                    endcase
                end
                default: F_bold_row = 8'h00;
            endcase
        end
    endfunction

    always @(*) begin
        case (I_char)
            CHAR_AN: begin
                case (I_row)
                    4'd0: O_row_bits = 16'h0200;
                    4'd1: O_row_bits = 16'h7ff0;
                    4'd2: O_row_bits = 16'h4410;
                    4'd3: O_row_bits = 16'h0400;
                    4'd4: O_row_bits = 16'h7ff0;
                    4'd5: O_row_bits = 16'h0840;
                    4'd6: O_row_bits = 16'h1040;
                    4'd7: O_row_bits = 16'h1c80;
                    4'd8: O_row_bits = 16'h0300;
                    4'd9: O_row_bits = 16'h0cc0;
                    4'd10: O_row_bits = 16'h7020;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_LU: begin
                case (I_row)
                    4'd0: O_row_bits = 16'h79e0;
                    4'd1: O_row_bits = 16'h4a20;
                    4'd2: O_row_bits = 16'h4d40;
                    4'd3: O_row_bits = 16'h7880;
                    4'd4: O_row_bits = 16'h1140;
                    4'd5: O_row_bits = 16'h1630;
                    4'd6: O_row_bits = 16'h5be0;
                    4'd7: O_row_bits = 16'h5220;
                    4'd8: O_row_bits = 16'h5220;
                    4'd9: O_row_bits = 16'h5be0;
                    4'd10: O_row_bits = 16'h6220;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            default: O_row_bits = F_bold_expand(F_bold_row(I_char, I_row[3:1]));
        endcase
    end
endmodule
