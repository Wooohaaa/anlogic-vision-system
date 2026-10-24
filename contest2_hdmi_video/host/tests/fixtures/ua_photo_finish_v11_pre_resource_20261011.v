`ifndef UA_PHOTO_FINISH_96_V
`define UA_PHOTO_FINISH_96_V
// Natural-photo finishing, four RGB888 pixels/beat, no backpressure.
// Thresholded separable range filter (not a full Gaussian bilateral filter):
// horizontal [1,2,1], then 1/2 current + 1/2 filtered preceding row. A neighbour is
// admitted only when ALL RGB channel differences are small. Strong edges
// retain the centre at rejected boundaries. Recursive spatial averaging uses
// one RGB line RAM; it is NOT temporal/frame averaging. For widths <16 pixels
// use a two-row FIR instead, avoiding feedback RAM read/write collisions.
// no frame storage, iterative divider or DSP. Six register stages including
// tone and guarded saturation. valid/user/last follow every stage and bubbles.
module ua_photo_finish_96 #(
    parameter integer IMG_WIDTH=1280,
    parameter integer TONE_ENABLE=1,
    parameter integer INPUT_BITS=8
)(
    input I_clk,I_rst_n,I_tvalid,I_tuser,I_tlast,
    input [12*INPUT_BITS-1:0] I_tdata,
    input [1:0] I_strength,
    output reg O_tvalid,O_tuser,O_tlast,
    output reg [95:0] O_tdata
);
    localparam integer PIXEL_BITS=3*INPUT_BITS;
    localparam integer WORD_BITS=12*INPUT_BITS;
    localparam integer LUT_SIZE=1<<INPUT_BITS;
    localparam integer GROUPS=IMG_WIDTH/4;
    localparam integer ADDR_W=(GROUPS<=1)?1:$clog2(GROUPS);
    reg [WORD_BITS-1:0] word_r,h_data,p_data,v_data;
    wire [95:0] encoded_data;
    reg encoded_valid,encoded_user,encoded_last;
    reg [PIXEL_BITS-1:0] left_r,last_pixel;
    reg word_valid,word_user,word_last,line_first;
    reg h_valid,h_user,h_last,p_valid,p_user,p_last,v_valid,v_user,v_last;
    reg [1:0] frame_strength,word_strength,h_strength,p_strength,v_strength;
    reg [ADDR_W-1:0] line_x;
    reg [ADDR_W-1:0] p_x,v_x;
    reg row_history,p_history;
    reg [WORD_BITS-1:0] previous_line;
    reg [WORD_BITS-1:0] line_mem[0:GROUPS-1];
    wire [ADDR_W-1:0] access_x=h_user ? {ADDR_W{1'b0}} : line_x;
    wire [PIXEL_BITS-1:0] right_pixel=word_last || !I_tvalid || I_tuser ?
                              word_r[PIXEL_BITS-1:0] : I_tdata[4*PIXEL_BITS-1:3*PIXEL_BITS];

    function [INPUT_BITS-1:0] abs_diff;
      input [INPUT_BITS-1:0] a,b;
      begin abs_diff=(a>=b)?a-b:b-a;end
    endfunction
    function similar;
      input [PIXEL_BITS-1:0] c,n;
      reg [INPUT_BITS-1:0] threshold;
      reg dark_pixel;
      integer k;
      begin
        dark_pixel=1'b1;
        for(k=0;k<3;k=k+1)
          if(c[k*INPUT_BITS+:INPUT_BITS]>=64) dark_pixel=1'b0;
        threshold=dark_pixel?18:12;
        similar=1'b1;
        for(k=0;k<3;k=k+1)
          if(abs_diff(c[k*INPUT_BITS+:INPUT_BITS],n[k*INPUT_BITS+:INPUT_BITS])>threshold)
            similar=1'b0;
      end
    endfunction
    function [PIXEL_BITS-1:0] horizontal;
      input [PIXEL_BITS-1:0] l,c,r;
      reg [PIXEL_BITS-1:0] a,b;
      reg [INPUT_BITS+1:0] total;
      integer k;
      begin
        a=similar(c,l)?l:c;b=similar(c,r)?r:c;
        for(k=0;k<3;k=k+1) begin
          total={2'b0,a[k*INPUT_BITS+:INPUT_BITS]}+
                {1'b0,c[k*INPUT_BITS+:INPUT_BITS],1'b0}+
                {2'b0,b[k*INPUT_BITS+:INPUT_BITS]}+2'd2;
          horizontal[k*INPUT_BITS+:INPUT_BITS]=total[INPUT_BITS+1:2];
        end
      end
    endfunction
    function [PIXEL_BITS-1:0] vertical;
      input [PIXEL_BITS-1:0] c,n;input history;
      reg [INPUT_BITS:0] total;
      integer k;
      begin
        if(!history || !similar(c,n)) vertical=c;
        else for(k=0;k<3;k=k+1) begin
          total={1'b0,c[k*INPUT_BITS+:INPUT_BITS]}+
                {1'b0,n[k*INPUT_BITS+:INPUT_BITS]}+1'b1;
          vertical[k*INPUT_BITS+:INPUT_BITS]=total[INPUT_BITS:1];
        end
      end
    endfunction
    // Black stays black; a gentle toe rejects amplified dark pedestal/noise.
    // Continuous monotone mid-tone lift and highlight shoulder; no +32 RGB
    // floor and no second 1.5x display gain. End points map exactly 0/255.
    function [7:0] legacy_tone;
      input [7:0] c;input [1:0] strength;
      reg [9:0] d,value;
      begin
        d=0;value=0;
        if(c<16) value={3'b0,c[7:1]};
        else if(c<32) begin
          d={2'b0,c}-10'd16;
          value=10'd8+d+((strength==2)?(d>>1):10'd0);
        end else if(strength==2) begin
          if(c<64) begin d={2'b0,c}-10'd32;value=10'd32+d+(d>>1)+(d>>2);end
          else if(c<128) begin d={2'b0,c}-10'd64;value=10'd88+d+(d>>1);end
          else if(c<192) begin d={2'b0,c}-10'd128;value=10'd184+d-(d>>2);end
          else begin d={2'b0,c}-10'd192;value=10'd232+(d>>2)+(d>>3);end
        end else if(strength==1) begin
          if(c<64) begin d={2'b0,c}-10'd32;value=10'd24+d+(d>>1);end
          else if(c<128) begin d={2'b0,c}-10'd64;value=10'd72+d+(d>>2);end
          else if(c<192) begin d={2'b0,c}-10'd128;value=10'd152+d;end
          else begin d={2'b0,c}-10'd192;value=10'd216+(d>>1)+(d>>3);end
        end else begin
          if(c<64) value={2'b0,c}-10'd8;
          else if(c<128) begin d={2'b0,c}-10'd64;value=10'd56+d+(d>>3);end
          else if(c<192) begin d={2'b0,c}-10'd128;value=10'd128+d+(d>>3);end
          else begin d={2'b0,c}-10'd192;value=10'd200+d-(d>>3);end
        end
        legacy_tone=(c==255 || value>255)?8'hff:value[7:0];
      end
    endfunction
    // v7: fixed contrast LUT after sRGB-based soft toe, same six-cycle path.
    // Encoded anchors: 0/0,16/6,32/20,64/48,128/144,192/216,224/240,255/255.
    // Preserve shadow separation, brighten midtones without lifting the black
    // pedestal. Fixed gains/curve avoid frame-dependent contrast pumping.
    // Dark details remain nonzero; no scene-dependent histogram pumping.
    // At encoded y<=128: max(0,y-10). Above: taper the 10-code reduction
    // linearly to zero at 255. This is display mapping, not RAW black level.
    // https://www.w3.org/Graphics/Color/srgb
    // Fixed encoding: scene statistics cannot change the tone curve.
    // Strength argument retained only for interface compatibility.
    function [7:0] tone_legacy8;
      input [7:0] c; input [1:0] strength;
      begin
        case(c)
        8'd0: tone_legacy8=8'd0;
        8'd1: tone_legacy8=8'd1;
        8'd2: tone_legacy8=8'd5;
        8'd3: tone_legacy8=8'd8;
        8'd4: tone_legacy8=8'd13;
        8'd5: tone_legacy8=8'd17;
        8'd6: tone_legacy8=8'd20;
        8'd7: tone_legacy8=8'd24;
        8'd8: tone_legacy8=8'd27;
        8'd9: tone_legacy8=8'd30;
        8'd10: tone_legacy8=8'd32;
        8'd11: tone_legacy8=8'd35;
        8'd12: tone_legacy8=8'd37;
        8'd13: tone_legacy8=8'd39;
        8'd14: tone_legacy8=8'd41;
        8'd15: tone_legacy8=8'd44;
        8'd16: tone_legacy8=8'd45;
        8'd17: tone_legacy8=8'd47;
        8'd18: tone_legacy8=8'd50;
        8'd19: tone_legacy8=8'd53;
        8'd20: tone_legacy8=8'd56;
        8'd21: tone_legacy8=8'd59;
        8'd22: tone_legacy8=8'd62;
        8'd23: tone_legacy8=8'd65;
        8'd24: tone_legacy8=8'd66;
        8'd25: tone_legacy8=8'd69;
        8'd26: tone_legacy8=8'd72;
        8'd27: tone_legacy8=8'd75;
        8'd28: tone_legacy8=8'd77;
        8'd29: tone_legacy8=8'd80;
        8'd30: tone_legacy8=8'd81;
        8'd31: tone_legacy8=8'd84;
        8'd32: tone_legacy8=8'd86;
        8'd33: tone_legacy8=8'd89;
        8'd34: tone_legacy8=8'd90;
        8'd35: tone_legacy8=8'd93;
        8'd36: tone_legacy8=8'd95;
        8'd37: tone_legacy8=8'd96;
        8'd38: tone_legacy8=8'd99;
        8'd39: tone_legacy8=8'd101;
        8'd40: tone_legacy8=8'd102;
        8'd41: tone_legacy8=8'd105;
        8'd42: tone_legacy8=8'd107;
        8'd43: tone_legacy8=8'd108;
        8'd44: tone_legacy8=8'd110;
        8'd45: tone_legacy8=8'd113;
        8'd46: tone_legacy8=8'd114;
        8'd47: tone_legacy8=8'd116;
        8'd48: tone_legacy8=8'd117;
        8'd49: tone_legacy8=8'd119;
        8'd50: tone_legacy8=8'd120;
        8'd51: tone_legacy8=8'd123;
        8'd52: tone_legacy8=8'd125;
        8'd53: tone_legacy8=8'd126;
        8'd54: tone_legacy8=8'd128;
        8'd55: tone_legacy8=8'd129;
        8'd56: tone_legacy8=8'd131;
        8'd57: tone_legacy8=8'd132;
        8'd58: tone_legacy8=8'd134;
        8'd59: tone_legacy8=8'd135;
        8'd60: tone_legacy8=8'd137;
        8'd61: tone_legacy8=8'd138;
        8'd62: tone_legacy8=8'd141;
        8'd63: tone_legacy8=8'd143;
        8'd64: tone_legacy8=8'd144;
        8'd65: tone_legacy8=8'd145;
        8'd66: tone_legacy8=8'd146;
        8'd67: tone_legacy8=8'd147;
        8'd68: tone_legacy8=8'd149;
        8'd69: tone_legacy8=8'd150;
        8'd70: tone_legacy8=8'd151;
        8'd71: tone_legacy8=8'd152;
        8'd72: tone_legacy8=8'd153;
        8'd73: tone_legacy8=8'd154;
        8'd74: tone_legacy8=8'd155;
        8'd75: tone_legacy8=8'd158;
        8'd76: tone_legacy8=8'd158;
        8'd77: tone_legacy8=8'd159;
        8'd78: tone_legacy8=8'd160;
        8'd79: tone_legacy8=8'd161;
        8'd80: tone_legacy8=8'd162;
        8'd81: tone_legacy8=8'd163;
        8'd82: tone_legacy8=8'd164;
        8'd83: tone_legacy8=8'd165;
        8'd84: tone_legacy8=8'd165;
        8'd85: tone_legacy8=8'd167;
        8'd86: tone_legacy8=8'd168;
        8'd87: tone_legacy8=8'd169;
        8'd88: tone_legacy8=8'd170;
        8'd89: tone_legacy8=8'd170;
        8'd90: tone_legacy8=8'd172;
        8'd91: tone_legacy8=8'd173;
        8'd92: tone_legacy8=8'd174;
        8'd93: tone_legacy8=8'd176;
        8'd94: tone_legacy8=8'd176;
        8'd95: tone_legacy8=8'd177;
        8'd96: tone_legacy8=8'd178;
        8'd97: tone_legacy8=8'd179;
        8'd98: tone_legacy8=8'd180;
        8'd99: tone_legacy8=8'd180;
        8'd100: tone_legacy8=8'd181;
        8'd101: tone_legacy8=8'd182;
        8'd102: tone_legacy8=8'd183;
        8'd103: tone_legacy8=8'd183;
        8'd104: tone_legacy8=8'd185;
        8'd105: tone_legacy8=8'd186;
        8'd106: tone_legacy8=8'd188;
        8'd107: tone_legacy8=8'd188;
        8'd108: tone_legacy8=8'd189;
        8'd109: tone_legacy8=8'd190;
        8'd110: tone_legacy8=8'd190;
        8'd111: tone_legacy8=8'd191;
        8'd112: tone_legacy8=8'd192;
        8'd113: tone_legacy8=8'd194;
        8'd114: tone_legacy8=8'd194;
        8'd115: tone_legacy8=8'd195;
        8'd116: tone_legacy8=8'd196;
        8'd117: tone_legacy8=8'd196;
        8'd118: tone_legacy8=8'd197;
        8'd119: tone_legacy8=8'd198;
        8'd120: tone_legacy8=8'd198;
        8'd121: tone_legacy8=8'd199;
        8'd122: tone_legacy8=8'd200;
        8'd123: tone_legacy8=8'd201;
        8'd124: tone_legacy8=8'd201;
        8'd125: tone_legacy8=8'd204;
        8'd126: tone_legacy8=8'd205;
        8'd127: tone_legacy8=8'd205;
        8'd128: tone_legacy8=8'd206;
        8'd129: tone_legacy8=8'd207;
        8'd130: tone_legacy8=8'd207;
        8'd131: tone_legacy8=8'd208;
        8'd132: tone_legacy8=8'd208;
        8'd133: tone_legacy8=8'd209;
        8'd134: tone_legacy8=8'd210;
        8'd135: tone_legacy8=8'd210;
        8'd136: tone_legacy8=8'd212;
        8'd137: tone_legacy8=8'd213;
        8'd138: tone_legacy8=8'd213;
        8'd139: tone_legacy8=8'd214;
        8'd140: tone_legacy8=8'd215;
        8'd141: tone_legacy8=8'd215;
        8'd142: tone_legacy8=8'd216;
        8'd143: tone_legacy8=8'd216;
        8'd144: tone_legacy8=8'd218;
        8'd145: tone_legacy8=8'd218;
        8'd146: tone_legacy8=8'd218;
        8'd147: tone_legacy8=8'd219;
        8'd148: tone_legacy8=8'd219;
        8'd149: tone_legacy8=8'd220;
        8'd150: tone_legacy8=8'd221;
        8'd151: tone_legacy8=8'd221;
        8'd152: tone_legacy8=8'd221;
        8'd153: tone_legacy8=8'd221;
        8'd154: tone_legacy8=8'd222;
        8'd155: tone_legacy8=8'd223;
        8'd156: tone_legacy8=8'd223;
        8'd157: tone_legacy8=8'd224;
        8'd158: tone_legacy8=8'd224;
        8'd159: tone_legacy8=8'd224;
        8'd160: tone_legacy8=8'd225;
        8'd161: tone_legacy8=8'd225;
        8'd162: tone_legacy8=8'd226;
        8'd163: tone_legacy8=8'd226;
        8'd164: tone_legacy8=8'd227;
        8'd165: tone_legacy8=8'd227;
        8'd166: tone_legacy8=8'd228;
        8'd167: tone_legacy8=8'd229;
        8'd168: tone_legacy8=8'd229;
        8'd169: tone_legacy8=8'd230;
        8'd170: tone_legacy8=8'd230;
        8'd171: tone_legacy8=8'd230;
        8'd172: tone_legacy8=8'd230;
        8'd173: tone_legacy8=8'd231;
        8'd174: tone_legacy8=8'd231;
        8'd175: tone_legacy8=8'd232;
        8'd176: tone_legacy8=8'd232;
        8'd177: tone_legacy8=8'd233;
        8'd178: tone_legacy8=8'd233;
        8'd179: tone_legacy8=8'd233;
        8'd180: tone_legacy8=8'd234;
        8'd181: tone_legacy8=8'd234;
        8'd182: tone_legacy8=8'd235;
        8'd183: tone_legacy8=8'd235;
        8'd184: tone_legacy8=8'd236;
        8'd185: tone_legacy8=8'd236;
        8'd186: tone_legacy8=8'd236;
        8'd187: tone_legacy8=8'd236;
        8'd188: tone_legacy8=8'd237;
        8'd189: tone_legacy8=8'd237;
        8'd190: tone_legacy8=8'd239;
        8'd191: tone_legacy8=8'd239;
        8'd192: tone_legacy8=8'd239;
        8'd193: tone_legacy8=8'd240;
        8'd194: tone_legacy8=8'd240;
        8'd195: tone_legacy8=8'd240;
        8'd196: tone_legacy8=8'd240;
        8'd197: tone_legacy8=8'd241;
        8'd198: tone_legacy8=8'd241;
        8'd199: tone_legacy8=8'd241;
        8'd200: tone_legacy8=8'd241;
        8'd201: tone_legacy8=8'd242;
        8'd202: tone_legacy8=8'd242;
        8'd203: tone_legacy8=8'd242;
        8'd204: tone_legacy8=8'd242;
        8'd205: tone_legacy8=8'd243;
        8'd206: tone_legacy8=8'd243;
        8'd207: tone_legacy8=8'd243;
        8'd208: tone_legacy8=8'd243;
        8'd209: tone_legacy8=8'd244;
        8'd210: tone_legacy8=8'd244;
        8'd211: tone_legacy8=8'd244;
        8'd212: tone_legacy8=8'd244;
        8'd213: tone_legacy8=8'd245;
        8'd214: tone_legacy8=8'd245;
        8'd215: tone_legacy8=8'd246;
        8'd216: tone_legacy8=8'd246;
        8'd217: tone_legacy8=8'd246;
        8'd218: tone_legacy8=8'd246;
        8'd219: tone_legacy8=8'd246;
        8'd220: tone_legacy8=8'd247;
        8'd221: tone_legacy8=8'd247;
        8'd222: tone_legacy8=8'd247;
        8'd223: tone_legacy8=8'd247;
        8'd224: tone_legacy8=8'd248;
        8'd225: tone_legacy8=8'd248;
        8'd226: tone_legacy8=8'd248;
        8'd227: tone_legacy8=8'd248;
        8'd228: tone_legacy8=8'd249;
        8'd229: tone_legacy8=8'd249;
        8'd230: tone_legacy8=8'd249;
        8'd231: tone_legacy8=8'd249;
        8'd232: tone_legacy8=8'd250;
        8'd233: tone_legacy8=8'd250;
        8'd234: tone_legacy8=8'd250;
        8'd235: tone_legacy8=8'd250;
        8'd236: tone_legacy8=8'd250;
        8'd237: tone_legacy8=8'd251;
        8'd238: tone_legacy8=8'd251;
        8'd239: tone_legacy8=8'd251;
        8'd240: tone_legacy8=8'd251;
        8'd241: tone_legacy8=8'd252;
        8'd242: tone_legacy8=8'd252;
        8'd243: tone_legacy8=8'd253;
        8'd244: tone_legacy8=8'd253;
        8'd245: tone_legacy8=8'd253;
        8'd246: tone_legacy8=8'd253;
        8'd247: tone_legacy8=8'd253;
        8'd248: tone_legacy8=8'd254;
        8'd249: tone_legacy8=8'd254;
        8'd250: tone_legacy8=8'd254;
        8'd251: tone_legacy8=8'd254;
        8'd252: tone_legacy8=8'd255;
        8'd253: tone_legacy8=8'd255;
        8'd254: tone_legacy8=8'd255;
        8'd255: tone_legacy8=8'd255;
        default: tone_legacy8=8'd0;
        endcase
      end
    endfunction
    // v11: 9-bit linear samples survive AWB gains up to 2.0 (0..510).
    // Encode once after linear denoising. Black=0, 255->240, 510->254.
    // Legacy 8-bit callers retain the v10 curve for compatibility.
    function [7:0] tone;
      input [INPUT_BITS-1:0] c;input [1:0] strength;
      begin
        if(INPUT_BITS==8) tone=tone_legacy8(c,strength);
        else begin
          case(c)
            9'd0: tone=8'd0;
            9'd1: tone=8'd3;
            9'd2: tone=8'd6;
            9'd3: tone=8'd10;
            9'd4: tone=8'd14;
            9'd5: tone=8'd18;
            9'd6: tone=8'd21;
            9'd7: tone=8'd25;
            9'd8: tone=8'd28;
            9'd9: tone=8'd31;
            9'd10: tone=8'd33;
            9'd11: tone=8'd36;
            9'd12: tone=8'd38;
            9'd13: tone=8'd41;
            9'd14: tone=8'd43;
            9'd15: tone=8'd46;
            9'd16: tone=8'd48;
            9'd17: tone=8'd51;
            9'd18: tone=8'd53;
            9'd19: tone=8'd56;
            9'd20: tone=8'd58;
            9'd21: tone=8'd61;
            9'd22: tone=8'd63;
            9'd23: tone=8'd66;
            9'd24: tone=8'd68;
            9'd25: tone=8'd71;
            9'd26: tone=8'd73;
            9'd27: tone=8'd76;
            9'd28: tone=8'd78;
            9'd29: tone=8'd81;
            9'd30: tone=8'd83;
            9'd31: tone=8'd86;
            9'd32: tone=8'd88;
            9'd33: tone=8'd90;
            9'd34: tone=8'd92;
            9'd35: tone=8'd93;
            9'd36: tone=8'd95;
            9'd37: tone=8'd97;
            9'd38: tone=8'd99;
            9'd39: tone=8'd100;
            9'd40: tone=8'd102;
            9'd41: tone=8'd104;
            9'd42: tone=8'd106;
            9'd43: tone=8'd107;
            9'd44: tone=8'd109;
            9'd45: tone=8'd111;
            9'd46: tone=8'd113;
            9'd47: tone=8'd114;
            9'd48: tone=8'd116;
            9'd49: tone=8'd118;
            9'd50: tone=8'd120;
            9'd51: tone=8'd121;
            9'd52: tone=8'd123;
            9'd53: tone=8'd125;
            9'd54: tone=8'd127;
            9'd55: tone=8'd128;
            9'd56: tone=8'd130;
            9'd57: tone=8'd132;
            9'd58: tone=8'd134;
            9'd59: tone=8'd135;
            9'd60: tone=8'd137;
            9'd61: tone=8'd139;
            9'd62: tone=8'd141;
            9'd63: tone=8'd142;
            9'd64: tone=8'd144;
            9'd65: tone=8'd145;
            9'd66: tone=8'd146;
            9'd67: tone=8'd147;
            9'd68: tone=8'd148;
            9'd69: tone=8'd149;
            9'd70: tone=8'd150;
            9'd71: tone=8'd151;
            9'd72: tone=8'd152;
            9'd73: tone=8'd153;
            9'd74: tone=8'd154;
            9'd75: tone=8'd155;
            9'd76: tone=8'd156;
            9'd77: tone=8'd157;
            9'd78: tone=8'd158;
            9'd79: tone=8'd159;
            9'd80: tone=8'd161;
            9'd81: tone=8'd162;
            9'd82: tone=8'd163;
            9'd83: tone=8'd164;
            9'd84: tone=8'd165;
            9'd85: tone=8'd166;
            9'd86: tone=8'd167;
            9'd87: tone=8'd168;
            9'd88: tone=8'd169;
            9'd89: tone=8'd170;
            9'd90: tone=8'd171;
            9'd91: tone=8'd172;
            9'd92: tone=8'd173;
            9'd93: tone=8'd174;
            9'd94: tone=8'd175;
            9'd95: tone=8'd176;
            9'd96: tone=8'd177;
            9'd97: tone=8'd178;
            9'd98: tone=8'd179;
            9'd99: tone=8'd180;
            9'd100: tone=8'd181;
            9'd101: tone=8'd182;
            9'd102: tone=8'd182;
            9'd103: tone=8'd183;
            9'd104: tone=8'd184;
            9'd105: tone=8'd185;
            9'd106: tone=8'd186;
            9'd107: tone=8'd187;
            9'd108: tone=8'd188;
            9'd109: tone=8'd189;
            9'd110: tone=8'd190;
            9'd111: tone=8'd191;
            9'd112: tone=8'd192;
            9'd113: tone=8'd192;
            9'd114: tone=8'd193;
            9'd115: tone=8'd194;
            9'd116: tone=8'd195;
            9'd117: tone=8'd196;
            9'd118: tone=8'd197;
            9'd119: tone=8'd198;
            9'd120: tone=8'd199;
            9'd121: tone=8'd200;
            9'd122: tone=8'd201;
            9'd123: tone=8'd201;
            9'd124: tone=8'd202;
            9'd125: tone=8'd203;
            9'd126: tone=8'd204;
            9'd127: tone=8'd205;
            9'd128: tone=8'd206;
            9'd129: tone=8'd206;
            9'd130: tone=8'd207;
            9'd131: tone=8'd207;
            9'd132: tone=8'd207;
            9'd133: tone=8'd208;
            9'd134: tone=8'd208;
            9'd135: tone=8'd208;
            9'd136: tone=8'd209;
            9'd137: tone=8'd209;
            9'd138: tone=8'd209;
            9'd139: tone=8'd209;
            9'd140: tone=8'd210;
            9'd141: tone=8'd210;
            9'd142: tone=8'd210;
            9'd143: tone=8'd211;
            9'd144: tone=8'd211;
            9'd145: tone=8'd211;
            9'd146: tone=8'd212;
            9'd147: tone=8'd212;
            9'd148: tone=8'd212;
            9'd149: tone=8'd213;
            9'd150: tone=8'd213;
            9'd151: tone=8'd213;
            9'd152: tone=8'd214;
            9'd153: tone=8'd214;
            9'd154: tone=8'd214;
            9'd155: tone=8'd214;
            9'd156: tone=8'd215;
            9'd157: tone=8'd215;
            9'd158: tone=8'd215;
            9'd159: tone=8'd216;
            9'd160: tone=8'd216;
            9'd161: tone=8'd216;
            9'd162: tone=8'd217;
            9'd163: tone=8'd217;
            9'd164: tone=8'd218;
            9'd165: tone=8'd218;
            9'd166: tone=8'd218;
            9'd167: tone=8'd219;
            9'd168: tone=8'd219;
            9'd169: tone=8'd219;
            9'd170: tone=8'd220;
            9'd171: tone=8'd220;
            9'd172: tone=8'd221;
            9'd173: tone=8'd221;
            9'd174: tone=8'd221;
            9'd175: tone=8'd222;
            9'd176: tone=8'd222;
            9'd177: tone=8'd222;
            9'd178: tone=8'd223;
            9'd179: tone=8'd223;
            9'd180: tone=8'd224;
            9'd181: tone=8'd224;
            9'd182: tone=8'd224;
            9'd183: tone=8'd225;
            9'd184: tone=8'd225;
            9'd185: tone=8'd225;
            9'd186: tone=8'd226;
            9'd187: tone=8'd226;
            9'd188: tone=8'd227;
            9'd189: tone=8'd227;
            9'd190: tone=8'd227;
            9'd191: tone=8'd228;
            9'd192: tone=8'd228;
            9'd193: tone=8'd228;
            9'd194: tone=8'd228;
            9'd195: tone=8'd229;
            9'd196: tone=8'd229;
            9'd197: tone=8'd229;
            9'd198: tone=8'd229;
            9'd199: tone=8'd230;
            9'd200: tone=8'd230;
            9'd201: tone=8'd230;
            9'd202: tone=8'd230;
            9'd203: tone=8'd230;
            9'd204: tone=8'd231;
            9'd205: tone=8'd231;
            9'd206: tone=8'd231;
            9'd207: tone=8'd231;
            9'd208: tone=8'd232;
            9'd209: tone=8'd232;
            9'd210: tone=8'd232;
            9'd211: tone=8'd232;
            9'd212: tone=8'd232;
            9'd213: tone=8'd233;
            9'd214: tone=8'd233;
            9'd215: tone=8'd233;
            9'd216: tone=8'd233;
            9'd217: tone=8'd233;
            9'd218: tone=8'd234;
            9'd219: tone=8'd234;
            9'd220: tone=8'd234;
            9'd221: tone=8'd234;
            9'd222: tone=8'd235;
            9'd223: tone=8'd235;
            9'd224: tone=8'd235;
            9'd225: tone=8'd235;
            9'd226: tone=8'd235;
            9'd227: tone=8'd235;
            9'd228: tone=8'd236;
            9'd229: tone=8'd236;
            9'd230: tone=8'd236;
            9'd231: tone=8'd236;
            9'd232: tone=8'd236;
            9'd233: tone=8'd236;
            9'd234: tone=8'd237;
            9'd235: tone=8'd237;
            9'd236: tone=8'd237;
            9'd237: tone=8'd237;
            9'd238: tone=8'd237;
            9'd239: tone=8'd237;
            9'd240: tone=8'd238;
            9'd241: tone=8'd238;
            9'd242: tone=8'd238;
            9'd243: tone=8'd238;
            9'd244: tone=8'd238;
            9'd245: tone=8'd238;
            9'd246: tone=8'd239;
            9'd247: tone=8'd239;
            9'd248: tone=8'd239;
            9'd249: tone=8'd239;
            9'd250: tone=8'd239;
            9'd251: tone=8'd239;
            9'd252: tone=8'd240;
            9'd253: tone=8'd240;
            9'd254: tone=8'd240;
            9'd255: tone=8'd240;
            9'd256: tone=8'd240;
            9'd257: tone=8'd240;
            9'd258: tone=8'd240;
            9'd259: tone=8'd240;
            9'd260: tone=8'd240;
            9'd261: tone=8'd241;
            9'd262: tone=8'd241;
            9'd263: tone=8'd241;
            9'd264: tone=8'd241;
            9'd265: tone=8'd241;
            9'd266: tone=8'd241;
            9'd267: tone=8'd241;
            9'd268: tone=8'd241;
            9'd269: tone=8'd241;
            9'd270: tone=8'd241;
            9'd271: tone=8'd241;
            9'd272: tone=8'd242;
            9'd273: tone=8'd242;
            9'd274: tone=8'd242;
            9'd275: tone=8'd242;
            9'd276: tone=8'd242;
            9'd277: tone=8'd242;
            9'd278: tone=8'd242;
            9'd279: tone=8'd242;
            9'd280: tone=8'd242;
            9'd281: tone=8'd242;
            9'd282: tone=8'd242;
            9'd283: tone=8'd243;
            9'd284: tone=8'd243;
            9'd285: tone=8'd243;
            9'd286: tone=8'd243;
            9'd287: tone=8'd243;
            9'd288: tone=8'd243;
            9'd289: tone=8'd243;
            9'd290: tone=8'd243;
            9'd291: tone=8'd243;
            9'd292: tone=8'd243;
            9'd293: tone=8'd244;
            9'd294: tone=8'd244;
            9'd295: tone=8'd244;
            9'd296: tone=8'd244;
            9'd297: tone=8'd244;
            9'd298: tone=8'd244;
            9'd299: tone=8'd244;
            9'd300: tone=8'd244;
            9'd301: tone=8'd244;
            9'd302: tone=8'd244;
            9'd303: tone=8'd244;
            9'd304: tone=8'd245;
            9'd305: tone=8'd245;
            9'd306: tone=8'd245;
            9'd307: tone=8'd245;
            9'd308: tone=8'd245;
            9'd309: tone=8'd245;
            9'd310: tone=8'd245;
            9'd311: tone=8'd245;
            9'd312: tone=8'd245;
            9'd313: tone=8'd245;
            9'd314: tone=8'd245;
            9'd315: tone=8'd246;
            9'd316: tone=8'd246;
            9'd317: tone=8'd246;
            9'd318: tone=8'd246;
            9'd319: tone=8'd246;
            9'd320: tone=8'd246;
            9'd321: tone=8'd246;
            9'd322: tone=8'd246;
            9'd323: tone=8'd246;
            9'd324: tone=8'd246;
            9'd325: tone=8'd246;
            9'd326: tone=8'd246;
            9'd327: tone=8'd246;
            9'd328: tone=8'd247;
            9'd329: tone=8'd247;
            9'd330: tone=8'd247;
            9'd331: tone=8'd247;
            9'd332: tone=8'd247;
            9'd333: tone=8'd247;
            9'd334: tone=8'd247;
            9'd335: tone=8'd247;
            9'd336: tone=8'd247;
            9'd337: tone=8'd247;
            9'd338: tone=8'd247;
            9'd339: tone=8'd247;
            9'd340: tone=8'd247;
            9'd341: tone=8'd247;
            9'd342: tone=8'd247;
            9'd343: tone=8'd247;
            9'd344: tone=8'd248;
            9'd345: tone=8'd248;
            9'd346: tone=8'd248;
            9'd347: tone=8'd248;
            9'd348: tone=8'd248;
            9'd349: tone=8'd248;
            9'd350: tone=8'd248;
            9'd351: tone=8'd248;
            9'd352: tone=8'd248;
            9'd353: tone=8'd248;
            9'd354: tone=8'd248;
            9'd355: tone=8'd248;
            9'd356: tone=8'd248;
            9'd357: tone=8'd248;
            9'd358: tone=8'd248;
            9'd359: tone=8'd248;
            9'd360: tone=8'd249;
            9'd361: tone=8'd249;
            9'd362: tone=8'd249;
            9'd363: tone=8'd249;
            9'd364: tone=8'd249;
            9'd365: tone=8'd249;
            9'd366: tone=8'd249;
            9'd367: tone=8'd249;
            9'd368: tone=8'd249;
            9'd369: tone=8'd249;
            9'd370: tone=8'd249;
            9'd371: tone=8'd249;
            9'd372: tone=8'd249;
            9'd373: tone=8'd249;
            9'd374: tone=8'd249;
            9'd375: tone=8'd249;
            9'd376: tone=8'd250;
            9'd377: tone=8'd250;
            9'd378: tone=8'd250;
            9'd379: tone=8'd250;
            9'd380: tone=8'd250;
            9'd381: tone=8'd250;
            9'd382: tone=8'd250;
            9'd383: tone=8'd250;
            9'd384: tone=8'd250;
            9'd385: tone=8'd250;
            9'd386: tone=8'd250;
            9'd387: tone=8'd250;
            9'd388: tone=8'd250;
            9'd389: tone=8'd250;
            9'd390: tone=8'd250;
            9'd391: tone=8'd250;
            9'd392: tone=8'd250;
            9'd393: tone=8'd250;
            9'd394: tone=8'd250;
            9'd395: tone=8'd250;
            9'd396: tone=8'd250;
            9'd397: tone=8'd250;
            9'd398: tone=8'd250;
            9'd399: tone=8'd250;
            9'd400: tone=8'd251;
            9'd401: tone=8'd251;
            9'd402: tone=8'd251;
            9'd403: tone=8'd251;
            9'd404: tone=8'd251;
            9'd405: tone=8'd251;
            9'd406: tone=8'd251;
            9'd407: tone=8'd251;
            9'd408: tone=8'd251;
            9'd409: tone=8'd251;
            9'd410: tone=8'd251;
            9'd411: tone=8'd251;
            9'd412: tone=8'd251;
            9'd413: tone=8'd251;
            9'd414: tone=8'd251;
            9'd415: tone=8'd251;
            9'd416: tone=8'd251;
            9'd417: tone=8'd251;
            9'd418: tone=8'd251;
            9'd419: tone=8'd251;
            9'd420: tone=8'd251;
            9'd421: tone=8'd251;
            9'd422: tone=8'd251;
            9'd423: tone=8'd251;
            9'd424: tone=8'd251;
            9'd425: tone=8'd251;
            9'd426: tone=8'd251;
            9'd427: tone=8'd251;
            9'd428: tone=8'd251;
            9'd429: tone=8'd251;
            9'd430: tone=8'd251;
            9'd431: tone=8'd251;
            9'd432: tone=8'd252;
            9'd433: tone=8'd252;
            9'd434: tone=8'd252;
            9'd435: tone=8'd252;
            9'd436: tone=8'd252;
            9'd437: tone=8'd252;
            9'd438: tone=8'd252;
            9'd439: tone=8'd252;
            9'd440: tone=8'd252;
            9'd441: tone=8'd252;
            9'd442: tone=8'd252;
            9'd443: tone=8'd252;
            9'd444: tone=8'd252;
            9'd445: tone=8'd252;
            9'd446: tone=8'd252;
            9'd447: tone=8'd252;
            9'd448: tone=8'd252;
            9'd449: tone=8'd252;
            9'd450: tone=8'd252;
            9'd451: tone=8'd252;
            9'd452: tone=8'd252;
            9'd453: tone=8'd252;
            9'd454: tone=8'd252;
            9'd455: tone=8'd252;
            9'd456: tone=8'd252;
            9'd457: tone=8'd252;
            9'd458: tone=8'd252;
            9'd459: tone=8'd252;
            9'd460: tone=8'd252;
            9'd461: tone=8'd252;
            9'd462: tone=8'd252;
            9'd463: tone=8'd252;
            9'd464: tone=8'd253;
            9'd465: tone=8'd253;
            9'd466: tone=8'd253;
            9'd467: tone=8'd253;
            9'd468: tone=8'd253;
            9'd469: tone=8'd253;
            9'd470: tone=8'd253;
            9'd471: tone=8'd253;
            9'd472: tone=8'd253;
            9'd473: tone=8'd253;
            9'd474: tone=8'd253;
            9'd475: tone=8'd253;
            9'd476: tone=8'd253;
            9'd477: tone=8'd253;
            9'd478: tone=8'd253;
            9'd479: tone=8'd253;
            9'd480: tone=8'd253;
            9'd481: tone=8'd253;
            9'd482: tone=8'd253;
            9'd483: tone=8'd253;
            9'd484: tone=8'd253;
            9'd485: tone=8'd253;
            9'd486: tone=8'd253;
            9'd487: tone=8'd253;
            9'd488: tone=8'd253;
            9'd489: tone=8'd253;
            9'd490: tone=8'd253;
            9'd491: tone=8'd253;
            9'd492: tone=8'd253;
            9'd493: tone=8'd253;
            9'd494: tone=8'd253;
            9'd495: tone=8'd254;
            9'd496: tone=8'd254;
            9'd497: tone=8'd254;
            9'd498: tone=8'd254;
            9'd499: tone=8'd254;
            9'd500: tone=8'd254;
            9'd501: tone=8'd254;
            9'd502: tone=8'd254;
            9'd503: tone=8'd254;
            9'd504: tone=8'd254;
            9'd505: tone=8'd254;
            9'd506: tone=8'd254;
            9'd507: tone=8'd254;
            9'd508: tone=8'd254;
            9'd509: tone=8'd254;
            9'd510: tone=8'd254;
            9'd511: tone=8'd254;
            default: tone=8'd254;
          endcase
        end
      end
    endfunction
    function [23:0] tone_pixel;
      input [23:0] c;input [1:0] strength;
      begin tone_pixel=(TONE_ENABLE==0)?c:
        {tone(c[23:16],strength),tone(c[15:8],strength),tone(c[7:0],strength)};
      end
    endfunction

    function [7:0] sat_channel;
      input [7:0] c,midpoint;
      reg [7:0] delta;
      begin
        // Called only under lo>24, hi<224: range<=198, |c-mid|<=99.
        // Quarter-range expansion stays in 1..247, no independent RGB clipping.
        if(c>=midpoint) begin
          delta=(c-midpoint)>>2;
          sat_channel=c+delta;
        end else begin
          delta=(midpoint-c)>>2;
          sat_channel=c-delta;
        end
      end
    endfunction
    function [23:0] saturate_pixel;
      input [23:0] c;
      reg [7:0] lo,hi,midpoint;
      reg [8:0] sum;
      begin
        lo=c[23:16];hi=c[23:16];
        if(c[15:8]<lo) lo=c[15:8];
        if(c[7:0]<lo) lo=c[7:0];
        if(c[15:8]>hi) hi=c[15:8];
        if(c[7:0]>hi) hi=c[7:0];
        sum={1'b0,lo}+{1'b0,hi};
        midpoint=sum[8:1];
        // Do not amplify dark chroma noise, near-white tint or gamut extremes.
        if(TONE_ENABLE==0 || lo<=8'd24 || hi>=8'd224 ||
           hi<=8'd80 || hi-lo<=8'd16) saturate_pixel=c;
        else saturate_pixel={sat_channel(c[23:16],midpoint),
          sat_channel(c[15:8],midpoint),sat_channel(c[7:0],midpoint)};
      end
    endfunction

    // Six identical dual-read ROM banks replace twelve combinational tables.
    // No external init file: 256 legacy entries or 512 headroom entries.
    // Registered ROM reads occupy the existing encoded stage (no extra delay).
    // ROM output registers need not reset; valid is reset and masks stale data.
    genvar bank;
    generate if(TONE_ENABLE!=0) begin : gen_tone_rom
      for(bank=0;bank<6;bank=bank+1) begin : bank_pair
        /* fehdl force_ram=1, ram_style="bram" */
        reg [7:0] lut[0:LUT_SIZE-1];
        reg [7:0] qa,qb;
        integer init_index;
        initial for(init_index=0;init_index<LUT_SIZE;init_index=init_index+1)
          lut[init_index]=tone(init_index,2'd0);
        always @(posedge I_clk)
          if(v_valid) qa<=lut[v_data[bank*2*INPUT_BITS+:INPUT_BITS]];
        always @(posedge I_clk)
          if(v_valid) qb<=lut[v_data[(bank*2+1)*INPUT_BITS+:INPUT_BITS]];
        assign encoded_data[bank*16+:8]=qa;
        assign encoded_data[bank*16+8+:8]=qb;
      end
    end else begin : gen_tone_passthrough
      reg [95:0] bypass;
      integer bypass_channel;
      always @(posedge I_clk)
        if(v_valid) begin
          for(bypass_channel=0;bypass_channel<12;bypass_channel=bypass_channel+1)
            bypass[bypass_channel*8+:8]<=((v_data[bypass_channel*INPUT_BITS+:INPUT_BITS]>255)?8'hff:v_data[bypass_channel*INPUT_BITS+:INPUT_BITS]);
        end
      assign encoded_data=bypass;
    end endgenerate

    // RAM itself is not reset. First-row history is invalid at each frame,
    // and each location is overwritten before a later row may read it.
    // Feedback write is two clocks after the read, before the next row's read
    // when GROUPS>=4. Addresses travel with valid beats, not wall-clock counts.
    // First row ignores RAM contents, then overwrites them with the new frame.
    always @(posedge I_clk) if(I_rst_n) begin
      if(h_valid) previous_line<=line_mem[access_x];
      if(GROUPS>=4) begin
        if(v_valid) line_mem[v_x]<=v_data;
      end else if(h_valid) line_mem[access_x]<=h_data;
    end
    always @(posedge I_clk or negedge I_rst_n) begin
      if(!I_rst_n) begin
        word_r<=0;left_r<=0;last_pixel<=0;word_valid<=0;word_user<=0;word_last<=0;
        line_first<=1;frame_strength<=0;word_strength<=0;
        h_data<=0;h_valid<=0;h_user<=0;h_last<=0;h_strength<=0;
        p_data<=0;p_valid<=0;p_user<=0;p_last<=0;p_strength<=0;p_history<=0;
        v_data<=0;v_valid<=0;v_user<=0;v_last<=0;v_strength<=0;
        line_x<=0;p_x<=0;v_x<=0;row_history<=0;
        O_tdata<=0;O_tvalid<=0;O_tuser<=0;O_tlast<=0;
        encoded_valid<=0;encoded_user<=0;encoded_last<=0;
      end else begin
        word_valid<=I_tvalid;word_user<=I_tvalid && I_tuser;word_last<=I_tvalid && I_tlast;
        if(I_tvalid) begin
          word_r<=I_tdata;
          left_r<=(line_first || I_tuser)?I_tdata[4*PIXEL_BITS-1:3*PIXEL_BITS]:last_pixel;
          last_pixel<=I_tdata[PIXEL_BITS-1:0];line_first<=I_tlast;
          if(I_tuser) frame_strength<=I_strength;
          word_strength<=I_tuser?I_strength:frame_strength;
        end
        h_valid<=word_valid;h_user<=word_user;h_last<=word_last;h_strength<=word_strength;
        if(word_valid) h_data<={
          horizontal(left_r,word_r[4*PIXEL_BITS-1:3*PIXEL_BITS],word_r[3*PIXEL_BITS-1:2*PIXEL_BITS]),
          horizontal(word_r[4*PIXEL_BITS-1:3*PIXEL_BITS],word_r[3*PIXEL_BITS-1:2*PIXEL_BITS],word_r[2*PIXEL_BITS-1:PIXEL_BITS]),
          horizontal(word_r[3*PIXEL_BITS-1:2*PIXEL_BITS],word_r[2*PIXEL_BITS-1:PIXEL_BITS],word_r[PIXEL_BITS-1:0]),
          horizontal(word_r[2*PIXEL_BITS-1:PIXEL_BITS],word_r[PIXEL_BITS-1:0],right_pixel)};
        p_valid<=h_valid;p_user<=h_user;p_last<=h_last;p_strength<=h_strength;
        if(h_valid) begin
          p_data<=h_data;p_x<=access_x;p_history<=h_user?1'b0:row_history;
          if(h_user) row_history<=h_last;
          else if(h_last) row_history<=1;
          line_x<=h_last?{ADDR_W{1'b0}}:access_x+1'b1;
        end
        v_valid<=p_valid;v_user<=p_user;v_last<=p_last;v_strength<=p_strength;
        v_x<=p_x;
        if(p_valid) v_data<={vertical(p_data[4*PIXEL_BITS-1:3*PIXEL_BITS],previous_line[4*PIXEL_BITS-1:3*PIXEL_BITS],p_history),
          vertical(p_data[3*PIXEL_BITS-1:2*PIXEL_BITS],previous_line[3*PIXEL_BITS-1:2*PIXEL_BITS],p_history),
          vertical(p_data[2*PIXEL_BITS-1:PIXEL_BITS],previous_line[2*PIXEL_BITS-1:PIXEL_BITS],p_history),
          vertical(p_data[PIXEL_BITS-1:0],previous_line[PIXEL_BITS-1:0],p_history)};
        encoded_valid<=v_valid;encoded_user<=v_user;encoded_last<=v_last;
        O_tvalid<=encoded_valid;O_tuser<=encoded_user;O_tlast<=encoded_last;
        if(encoded_valid) O_tdata<={saturate_pixel(encoded_data[95:72]),
          saturate_pixel(encoded_data[71:48]),saturate_pixel(encoded_data[47:24]),
          saturate_pixel(encoded_data[23:0])};
        else O_tdata<=0;
      end
    end
endmodule
`endif
