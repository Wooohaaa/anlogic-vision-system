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
    parameter integer TONE_ENABLE=1
)(
    input I_clk,I_rst_n,I_tvalid,I_tuser,I_tlast,
    input [95:0] I_tdata,
    input [1:0] I_strength,
    output reg O_tvalid,O_tuser,O_tlast,
    output reg [95:0] O_tdata
);
    localparam integer GROUPS=IMG_WIDTH/4;
    localparam integer ADDR_W=(GROUPS<=1)?1:$clog2(GROUPS);
    reg [95:0] word_r,h_data,p_data,v_data;
    wire [95:0] encoded_data;
    reg encoded_valid,encoded_user,encoded_last;
    reg [23:0] left_r,last_pixel;
    reg word_valid,word_user,word_last,line_first;
    reg h_valid,h_user,h_last,p_valid,p_user,p_last,v_valid,v_user,v_last;
    reg [1:0] frame_strength,word_strength,h_strength,p_strength,v_strength;
    reg [ADDR_W-1:0] line_x;
    reg [ADDR_W-1:0] p_x,v_x;
    reg row_history,p_history;
    reg [95:0] previous_line;
    reg [95:0] line_mem[0:GROUPS-1];
    wire [ADDR_W-1:0] access_x=h_user ? {ADDR_W{1'b0}} : line_x;
    wire [23:0] right_pixel=word_last || !I_tvalid || I_tuser ?
                              word_r[23:0] : I_tdata[95:72];

    function [7:0] abs_diff;
      input [7:0] a,b;
      begin abs_diff=(a>=b)?a-b:b-a;end
    endfunction
    function similar;
      input [23:0] c,n;
      reg [7:0] threshold;
      begin
        threshold=(c[23:16]<64 && c[15:8]<64 && c[7:0]<64)?8'd18:8'd12;
        similar=abs_diff(c[23:16],n[23:16])<=threshold &&
                abs_diff(c[15:8],n[15:8])<=threshold &&
                abs_diff(c[7:0],n[7:0])<=threshold;
      end
    endfunction
    function [23:0] horizontal;
      input [23:0] l,c,r;
      reg [23:0] a,b;
      reg [9:0] sr,sg,sb;
      begin
        a=similar(c,l)?l:c;b=similar(c,r)?r:c;
        sr={2'b0,a[23:16]}+{1'b0,c[23:16],1'b0}+{2'b0,b[23:16]}+10'd2;
        sg={2'b0,a[15:8]}+{1'b0,c[15:8],1'b0}+{2'b0,b[15:8]}+10'd2;
        sb={2'b0,a[7:0]}+{1'b0,c[7:0],1'b0}+{2'b0,b[7:0]}+10'd2;
        horizontal={sr[9:2],sg[9:2],sb[9:2]};
      end
    endfunction
    function [23:0] vertical;
      input [23:0] c,n;input history;
      reg [8:0] sr,sg,sb;
      begin
        if(!history || !similar(c,n)) vertical=c;
        else begin
          sr={1'b0,c[23:16]}+{1'b0,n[23:16]}+9'd1;
          sg={1'b0,c[15:8]}+{1'b0,n[15:8]}+9'd1;
          sb={1'b0,c[7:0]}+{1'b0,n[7:0]}+9'd1;
          vertical={sr[8:1],sg[8:1],sb[8:1]};
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
    function [7:0] tone;
      input [7:0] c; input [1:0] strength;
      begin
        case(c)
        8'd0: tone=8'd0;
        8'd1: tone=8'd1;
        8'd2: tone=8'd5;
        8'd3: tone=8'd8;
        8'd4: tone=8'd13;
        8'd5: tone=8'd17;
        8'd6: tone=8'd20;
        8'd7: tone=8'd24;
        8'd8: tone=8'd27;
        8'd9: tone=8'd30;
        8'd10: tone=8'd32;
        8'd11: tone=8'd35;
        8'd12: tone=8'd37;
        8'd13: tone=8'd39;
        8'd14: tone=8'd41;
        8'd15: tone=8'd44;
        8'd16: tone=8'd45;
        8'd17: tone=8'd47;
        8'd18: tone=8'd50;
        8'd19: tone=8'd53;
        8'd20: tone=8'd56;
        8'd21: tone=8'd59;
        8'd22: tone=8'd62;
        8'd23: tone=8'd65;
        8'd24: tone=8'd66;
        8'd25: tone=8'd69;
        8'd26: tone=8'd72;
        8'd27: tone=8'd75;
        8'd28: tone=8'd77;
        8'd29: tone=8'd80;
        8'd30: tone=8'd81;
        8'd31: tone=8'd84;
        8'd32: tone=8'd86;
        8'd33: tone=8'd89;
        8'd34: tone=8'd90;
        8'd35: tone=8'd93;
        8'd36: tone=8'd95;
        8'd37: tone=8'd96;
        8'd38: tone=8'd99;
        8'd39: tone=8'd101;
        8'd40: tone=8'd102;
        8'd41: tone=8'd105;
        8'd42: tone=8'd107;
        8'd43: tone=8'd108;
        8'd44: tone=8'd110;
        8'd45: tone=8'd113;
        8'd46: tone=8'd114;
        8'd47: tone=8'd116;
        8'd48: tone=8'd117;
        8'd49: tone=8'd119;
        8'd50: tone=8'd120;
        8'd51: tone=8'd123;
        8'd52: tone=8'd125;
        8'd53: tone=8'd126;
        8'd54: tone=8'd128;
        8'd55: tone=8'd129;
        8'd56: tone=8'd131;
        8'd57: tone=8'd132;
        8'd58: tone=8'd134;
        8'd59: tone=8'd135;
        8'd60: tone=8'd137;
        8'd61: tone=8'd138;
        8'd62: tone=8'd141;
        8'd63: tone=8'd143;
        8'd64: tone=8'd144;
        8'd65: tone=8'd145;
        8'd66: tone=8'd146;
        8'd67: tone=8'd147;
        8'd68: tone=8'd149;
        8'd69: tone=8'd150;
        8'd70: tone=8'd151;
        8'd71: tone=8'd152;
        8'd72: tone=8'd153;
        8'd73: tone=8'd154;
        8'd74: tone=8'd155;
        8'd75: tone=8'd158;
        8'd76: tone=8'd158;
        8'd77: tone=8'd159;
        8'd78: tone=8'd160;
        8'd79: tone=8'd161;
        8'd80: tone=8'd162;
        8'd81: tone=8'd163;
        8'd82: tone=8'd164;
        8'd83: tone=8'd165;
        8'd84: tone=8'd165;
        8'd85: tone=8'd167;
        8'd86: tone=8'd168;
        8'd87: tone=8'd169;
        8'd88: tone=8'd170;
        8'd89: tone=8'd170;
        8'd90: tone=8'd172;
        8'd91: tone=8'd173;
        8'd92: tone=8'd174;
        8'd93: tone=8'd176;
        8'd94: tone=8'd176;
        8'd95: tone=8'd177;
        8'd96: tone=8'd178;
        8'd97: tone=8'd179;
        8'd98: tone=8'd180;
        8'd99: tone=8'd180;
        8'd100: tone=8'd181;
        8'd101: tone=8'd182;
        8'd102: tone=8'd183;
        8'd103: tone=8'd183;
        8'd104: tone=8'd185;
        8'd105: tone=8'd186;
        8'd106: tone=8'd188;
        8'd107: tone=8'd188;
        8'd108: tone=8'd189;
        8'd109: tone=8'd190;
        8'd110: tone=8'd190;
        8'd111: tone=8'd191;
        8'd112: tone=8'd192;
        8'd113: tone=8'd194;
        8'd114: tone=8'd194;
        8'd115: tone=8'd195;
        8'd116: tone=8'd196;
        8'd117: tone=8'd196;
        8'd118: tone=8'd197;
        8'd119: tone=8'd198;
        8'd120: tone=8'd198;
        8'd121: tone=8'd199;
        8'd122: tone=8'd200;
        8'd123: tone=8'd201;
        8'd124: tone=8'd201;
        8'd125: tone=8'd204;
        8'd126: tone=8'd205;
        8'd127: tone=8'd205;
        8'd128: tone=8'd206;
        8'd129: tone=8'd207;
        8'd130: tone=8'd207;
        8'd131: tone=8'd208;
        8'd132: tone=8'd208;
        8'd133: tone=8'd209;
        8'd134: tone=8'd210;
        8'd135: tone=8'd210;
        8'd136: tone=8'd212;
        8'd137: tone=8'd213;
        8'd138: tone=8'd213;
        8'd139: tone=8'd214;
        8'd140: tone=8'd215;
        8'd141: tone=8'd215;
        8'd142: tone=8'd216;
        8'd143: tone=8'd216;
        8'd144: tone=8'd218;
        8'd145: tone=8'd218;
        8'd146: tone=8'd218;
        8'd147: tone=8'd219;
        8'd148: tone=8'd219;
        8'd149: tone=8'd220;
        8'd150: tone=8'd221;
        8'd151: tone=8'd221;
        8'd152: tone=8'd221;
        8'd153: tone=8'd221;
        8'd154: tone=8'd222;
        8'd155: tone=8'd223;
        8'd156: tone=8'd223;
        8'd157: tone=8'd224;
        8'd158: tone=8'd224;
        8'd159: tone=8'd224;
        8'd160: tone=8'd225;
        8'd161: tone=8'd225;
        8'd162: tone=8'd226;
        8'd163: tone=8'd226;
        8'd164: tone=8'd227;
        8'd165: tone=8'd227;
        8'd166: tone=8'd228;
        8'd167: tone=8'd229;
        8'd168: tone=8'd229;
        8'd169: tone=8'd230;
        8'd170: tone=8'd230;
        8'd171: tone=8'd230;
        8'd172: tone=8'd230;
        8'd173: tone=8'd231;
        8'd174: tone=8'd231;
        8'd175: tone=8'd232;
        8'd176: tone=8'd232;
        8'd177: tone=8'd233;
        8'd178: tone=8'd233;
        8'd179: tone=8'd233;
        8'd180: tone=8'd234;
        8'd181: tone=8'd234;
        8'd182: tone=8'd235;
        8'd183: tone=8'd235;
        8'd184: tone=8'd236;
        8'd185: tone=8'd236;
        8'd186: tone=8'd236;
        8'd187: tone=8'd236;
        8'd188: tone=8'd237;
        8'd189: tone=8'd237;
        8'd190: tone=8'd239;
        8'd191: tone=8'd239;
        8'd192: tone=8'd239;
        8'd193: tone=8'd240;
        8'd194: tone=8'd240;
        8'd195: tone=8'd240;
        8'd196: tone=8'd240;
        8'd197: tone=8'd241;
        8'd198: tone=8'd241;
        8'd199: tone=8'd241;
        8'd200: tone=8'd241;
        8'd201: tone=8'd242;
        8'd202: tone=8'd242;
        8'd203: tone=8'd242;
        8'd204: tone=8'd242;
        8'd205: tone=8'd243;
        8'd206: tone=8'd243;
        8'd207: tone=8'd243;
        8'd208: tone=8'd243;
        8'd209: tone=8'd244;
        8'd210: tone=8'd244;
        8'd211: tone=8'd244;
        8'd212: tone=8'd244;
        8'd213: tone=8'd245;
        8'd214: tone=8'd245;
        8'd215: tone=8'd246;
        8'd216: tone=8'd246;
        8'd217: tone=8'd246;
        8'd218: tone=8'd246;
        8'd219: tone=8'd246;
        8'd220: tone=8'd247;
        8'd221: tone=8'd247;
        8'd222: tone=8'd247;
        8'd223: tone=8'd247;
        8'd224: tone=8'd248;
        8'd225: tone=8'd248;
        8'd226: tone=8'd248;
        8'd227: tone=8'd248;
        8'd228: tone=8'd249;
        8'd229: tone=8'd249;
        8'd230: tone=8'd249;
        8'd231: tone=8'd249;
        8'd232: tone=8'd250;
        8'd233: tone=8'd250;
        8'd234: tone=8'd250;
        8'd235: tone=8'd250;
        8'd236: tone=8'd250;
        8'd237: tone=8'd251;
        8'd238: tone=8'd251;
        8'd239: tone=8'd251;
        8'd240: tone=8'd251;
        8'd241: tone=8'd252;
        8'd242: tone=8'd252;
        8'd243: tone=8'd253;
        8'd244: tone=8'd253;
        8'd245: tone=8'd253;
        8'd246: tone=8'd253;
        8'd247: tone=8'd253;
        8'd248: tone=8'd254;
        8'd249: tone=8'd254;
        8'd250: tone=8'd254;
        8'd251: tone=8'd254;
        8'd252: tone=8'd255;
        8'd253: tone=8'd255;
        8'd254: tone=8'd255;
        8'd255: tone=8'd255;
        default: tone=8'd0;
        endcase
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
    // No external init file: constants are initialized from the exact v7 LUT.
    // Registered ROM reads occupy the existing encoded stage (no extra delay).
    // ROM output registers need not reset; valid is reset and masks stale data.
    genvar bank;
    generate if(TONE_ENABLE!=0) begin : gen_tone_rom
      for(bank=0;bank<6;bank=bank+1) begin : bank_pair
        /* fehdl force_ram=1, ram_style="bram" */
        reg [7:0] lut[0:255];
        reg [7:0] qa,qb;
        integer init_index;
        initial for(init_index=0;init_index<256;init_index=init_index+1)
          lut[init_index]=tone(init_index,2'd0);
        always @(posedge I_clk)
          if(v_valid) qa<=lut[v_data[bank*16+:8]];
        always @(posedge I_clk)
          if(v_valid) qb<=lut[v_data[bank*16+8+:8]];
        assign encoded_data[bank*16+:8]=qa;
        assign encoded_data[bank*16+8+:8]=qb;
      end
    end else begin : gen_tone_passthrough
      reg [95:0] bypass;
      always @(posedge I_clk)
        if(v_valid) bypass<=v_data;
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
          left_r<=(line_first || I_tuser)?I_tdata[95:72]:last_pixel;
          last_pixel<=I_tdata[23:0];line_first<=I_tlast;
          if(I_tuser) frame_strength<=I_strength;
          word_strength<=I_tuser?I_strength:frame_strength;
        end
        h_valid<=word_valid;h_user<=word_user;h_last<=word_last;h_strength<=word_strength;
        if(word_valid) h_data<={
          horizontal(left_r,word_r[95:72],word_r[71:48]),
          horizontal(word_r[95:72],word_r[71:48],word_r[47:24]),
          horizontal(word_r[71:48],word_r[47:24],word_r[23:0]),
          horizontal(word_r[47:24],word_r[23:0],right_pixel)};
        p_valid<=h_valid;p_user<=h_user;p_last<=h_last;p_strength<=h_strength;
        if(h_valid) begin
          p_data<=h_data;p_x<=access_x;p_history<=h_user?1'b0:row_history;
          if(h_user) row_history<=h_last;
          else if(h_last) row_history<=1;
          line_x<=h_last?{ADDR_W{1'b0}}:access_x+1'b1;
        end
        v_valid<=p_valid;v_user<=p_user;v_last<=p_last;v_strength<=p_strength;
        v_x<=p_x;
        if(p_valid) v_data<={vertical(p_data[95:72],previous_line[95:72],p_history),
          vertical(p_data[71:48],previous_line[71:48],p_history),
          vertical(p_data[47:24],previous_line[47:24],p_history),
          vertical(p_data[23:0],previous_line[23:0],p_history)};
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
