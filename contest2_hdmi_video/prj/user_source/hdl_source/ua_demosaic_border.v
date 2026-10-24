// BGGR, four RAW10 pixels/beat. Reflect-101 padding preserves CFA parity:
// row -1 is row 1 (not row 0), and column -1 is column 1.
// Wait for the following sensor row before emitting the centre row. Flush
// the final row during vertical blanking; allow WIDTH/4+8 clocks before SOF.
// Continuous/no-backpressure interface, matching the existing camera ISP.
module ua_demosaic_border #(
    parameter IMG_WIDTH=1280, IMG_HEIGHT=720,
    parameter data_complete_delay=50,
    parameter BAYER_MODE="BGGR", COALESCE_INPUT=1
)(
    input I_clk,I_rst_n,
    input [39:0] axi4s_video_tdata,
    input [9:0] axi4s_video_tdest,
    input axi4s_video_tlast,axi4s_video_tvalid,axi4s_video_tuser,
    output axi4s_video_tready,
    output O_tlast,O_tuser,O_tvalid,
    output [127:0] O_tdata,
    input O_tready
);
    wire [39:0] core_raw;
    wire core_valid,core_user,core_last;
    generate if(COALESCE_INPUT!=0) begin : gen_coalesce
        wire [31:0] aligned_raw8;
        // Only emit a COMPLETE row. No first-frame valid-width calibration:
        // CSI bubbles cannot expose unwritten RAM on startup or scene changes.
        ua_raw_line_coalesce4x #(.IMG_WIDTH(IMG_WIDTH)) u_line_coalesce(
            .clk(I_clk),.rst_n(I_rst_n),.raw(axi4s_video_tdata),
            .valid(axi4s_video_tvalid),.user(axi4s_video_tuser),
            .data_out(aligned_raw8),.last_out(core_last),
            .valid_out(core_valid),.user_out(core_user));
        assign core_raw={aligned_raw8[7:0],2'd0,aligned_raw8[15:8],2'd0,
                         aligned_raw8[23:16],2'd0,aligned_raw8[31:24],2'd0};
    end else begin : gen_direct_test
        assign core_raw=axi4s_video_tdata;
        assign core_last=axi4s_video_tlast;
        assign core_valid=axi4s_video_tvalid;
        assign core_user=axi4s_video_tuser;
    end endgenerate
    ua_bayer_window_core4x #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT),
        .BAYER_MODE(BAYER_MODE)) u_window_core(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.axi4s_video_tdata(core_raw),
        .axi4s_video_tdest(axi4s_video_tdest),.axi4s_video_tlast(core_last),
        .axi4s_video_tvalid(core_valid),.axi4s_video_tuser(core_user),
        .axi4s_video_tready(axi4s_video_tready),.O_tlast(O_tlast),.O_tuser(O_tuser),
        .O_tvalid(O_tvalid),.O_tdata(O_tdata),.O_tready(O_tready));
endmodule

// Two ping-pong rows. Burst input is no faster than one group/clock; camera
// horizontal/vertical blanking provides the few startup clocks of slack.
// A ready bank is consumed in exactly WIDTH/4 uninterrupted clocks.
module ua_raw_line_coalesce4x #(parameter IMG_WIDTH=1280)(
    input clk,rst_n,input [39:0] raw,input valid,user,
    output [31:0] data_out,output reg valid_out,user_out,last_out
);
    localparam G=IMG_WIDTH/4,AW=(G<=1)?1:$clog2(G);
    /* fehdl force_ram=1, ram_style="bram" */
    (* ram_style="bram" *) reg [31:0] bank0[0:G-1];
    /* fehdl force_ram=1, ram_style="bram" */
    (* ram_style="bram" *) reg [31:0] bank1[0:G-1];
    reg [AW-1:0] wx,rx;
    reg wb,rb,active;
    reg [1:0] ready_bank,sof_bank;
    reg [31:0] q0,q1;
    reg output_bank;
    wire [AW-1:0] write_x=user?{AW{1'b0}}:wx;
    wire write_bank=user?1'b0:wb;
    wire issue=(active || ready_bank[rb]) && !(valid && user);
    wire [AW-1:0] read_x=active?rx:{AW{1'b0}};
    wire [31:0] raw8={raw[9:2],raw[19:12],raw[29:22],raw[39:32]};
    always @(posedge clk) begin
        q0<=bank0[read_x];q1<=bank1[read_x];
        if(valid) begin
            if(write_bank) bank1[write_x]<=raw8;
            else bank0[write_x]<=raw8;
        end
    end
    assign data_out=output_bank?q1:q0;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            wx<=0;rx<=0;wb<=0;rb<=0;active<=0;
            ready_bank<=0;sof_bank<=0;output_bank<=0;
            valid_out<=0;user_out<=0;last_out<=0;
        end else begin
            valid_out<=issue;
            user_out<=issue && read_x==0 && sof_bank[rb];
            last_out<=issue && read_x==G-1;
            output_bank<=rb;
            if(issue) begin
                if(read_x==0) ready_bank[rb]<=0;
                if(read_x==G-1) begin
                    rx<=0;rb<=!rb;active<=0;
                end else begin rx<=read_x+1'b1;active<=1;end
            end
            if(valid && user) begin
                rx<=0;rb<=0;active<=0;ready_bank<=0;
            end
            if(valid) begin
                if(write_x==0) sof_bank[write_bank]<=user;
                if(write_x==G-1) begin
                    ready_bank[write_bank]<=1;
                    wx<=0;wb<=!write_bank;
                end else begin wx<=write_x+1'b1;wb<=write_bank;end
            end
        end
    end
endmodule

module ua_bayer_window_core4x #(
    parameter IMG_WIDTH=1280, IMG_HEIGHT=720,
    parameter data_complete_delay=50,
    parameter BAYER_MODE="BGGR"
)(
    input I_clk,I_rst_n,
    input [39:0] axi4s_video_tdata,
    input [9:0] axi4s_video_tdest,
    input axi4s_video_tlast,axi4s_video_tvalid,axi4s_video_tuser,
    output axi4s_video_tready,
    output O_tlast,O_tuser,O_tvalid,
    output [127:0] O_tdata,
    input O_tready
);
    localparam GROUPS=IMG_WIDTH/4;
    localparam AW=(GROUPS<=1)?1:$clog2(GROUPS);
    /* fehdl force_ram=1, ram_style="bram" */
    (* ram_style="bram" *) reg [31:0] even_line[0:GROUPS-1];
    /* fehdl force_ram=1, ram_style="bram" */
    (* ram_style="bram" *) reg [31:0] odd_line[0:GROUPS-1];
    reg [AW-1:0] x,flush_x;
    reg [11:0] y;
    reg flushing;
    wire [AW-1:0] ix=axi4s_video_tuser?{AW{1'b0}}:x;
    wire [11:0] iy=axi4s_video_tuser?12'd0:y;
    wire [31:0] raw={axi4s_video_tdata[9:2],axi4s_video_tdata[19:12],
                     axi4s_video_tdata[29:22],axi4s_video_tdata[39:32]};
    reg a_valid,a_first,a_last,a_user,a_phase;
    reg [31:0] even_q,odd_q,a_raw;
    reg a_flush,a_reflect_top;
    reg write_pending,write_bank;
    reg [AW-1:0] write_addr;
    reg [31:0] write_data;
    wire [AW-1:0] ram_addr=axi4s_video_tvalid?ix:flush_x;
    wire [31:0] a_top=a_reflect_top?a_raw:(a_phase?even_q:odd_q);
    wire [31:0] a_cur=a_phase?odd_q:even_q;
    wire [31:0] a_bot=a_flush?a_top:a_raw;
    // Read first, overwrite one clock later: no same-address read/write
    // collision in production, independent of the ERAM write mode.
    always @(posedge I_clk) begin
        // One synchronous read port per bank. Select the row AFTER RAM, not
        // by conditionally reading each bank into multiple pipeline registers.
        even_q<=(GROUPS==1 && write_pending && !write_bank)?write_data:even_line[ram_addr];
        odd_q<=(GROUPS==1 && write_pending && write_bank)?write_data:odd_line[ram_addr];
        if(write_pending) begin
            if(write_bank) odd_line[write_addr]<=write_data;
            else even_line[write_addr]<=write_data;
        end
        if(axi4s_video_tvalid) begin
            a_raw<=raw;
        end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            x<=0;y<=0;flush_x<=0;flushing<=0;
            a_valid<=0;a_first<=0;a_last<=0;a_user<=0;a_phase<=0;
            a_flush<=0;a_reflect_top<=0;
            write_pending<=0;write_addr<=0;write_bank<=0;write_data<=0;
        end else begin
            a_valid<=0;
            write_pending<=axi4s_video_tvalid;
            if(axi4s_video_tvalid) begin
                write_addr<=ix;write_bank<=iy[0];write_data<=raw;
            end
            if(axi4s_video_tvalid) begin
                a_valid<=iy!=0;
                a_flush<=0;a_reflect_top<=iy==1;
                a_first<=ix==0;a_last<=ix==GROUPS-1;
                a_user<=iy==1 && ix==0;
                a_phase<=!iy[0]; // centre row y-1
                x<=(ix==GROUPS-1)?{AW{1'b0}}:ix+1'b1;
                y<=(ix==GROUPS-1)?iy+1'b1:iy;
                if(axi4s_video_tuser) flushing<=0;
                if(iy==IMG_HEIGHT-1 && ix==GROUPS-1) begin
                    flushing<=1;flush_x<=0;
                end
            end else if(flushing) begin
                a_valid<=1;a_first<=flush_x==0;
                a_flush<=1;a_reflect_top<=0;
                a_last<=flush_x==GROUPS-1;a_user<=0;
                a_phase<=((IMG_HEIGHT-1)%2)!=0;
                flush_x<=flush_x+1'b1;
                if(flush_x==GROUPS-1) flushing<=0;
            end
        end
    end
    reg p_valid,p_first,p_last,p_user,p_phase;
    reg [31:0] p_top,p_cur,p_bot;
    reg [7:0] left_top,left_cur,left_bot;
    reg [95:0] top_window,cur_window,bot_window;
    reg window_valid,window_last,window_user,window_phase;
    // Hold one group for its right neighbour. Last groups use the same-colour
    // reflected pixel at WIDTH-2, not the opposite-colour WIDTH-1 pixel.
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            p_valid<=0;p_first<=0;p_last<=0;p_user<=0;p_phase<=0;
            p_top<=0;p_cur<=0;p_bot<=0;left_top<=0;left_cur<=0;left_bot<=0;
            window_valid<=0;window_last<=0;window_user<=0;window_phase<=0;
            top_window<=0;cur_window<=0;bot_window<=0;
        end else begin
            window_valid<=p_valid && (p_last || a_valid);
            window_last<=p_valid && (p_last || a_valid) && p_last;
            window_user<=p_valid && (p_last || a_valid) && p_user;
            window_phase<=p_phase;
            if(p_valid && (p_last || a_valid)) begin
                top_window<={24'd0,left_top,p_top,p_last?p_top[15:8]:a_top[31:24],24'd0};
                cur_window<={24'd0,left_cur,p_cur,p_last?p_cur[15:8]:a_cur[31:24],24'd0};
                bot_window<={24'd0,left_bot,p_bot,p_last?p_bot[15:8]:a_bot[31:24],24'd0};
                p_valid<=0;
            end
            if(a_valid) begin
                p_valid<=1;p_first<=a_first;p_last<=a_last;
                p_user<=a_user;p_phase<=a_phase;
                left_top<=a_first?a_top[23:16]:p_top[7:0];
                left_cur<=a_first?a_cur[23:16]:p_cur[7:0];
                left_bot<=a_first?a_bot[23:16]:p_bot[7:0];
                p_top<=a_top;p_cur<=a_cur;p_bot<=a_bot;
            end
        end
    end
    bilinear_interpolation #(.BAYER_MODE(BAYER_MODE)) u_interpolate(
        .I_clk(I_clk),.I_rst_n(I_rst_n),
        .I_tlast(window_last),.I_tuser(window_user),.I_tvalid(window_valid),
        .I_tready(axi4s_video_tready),.bayer_ypos(window_phase),
        .matrix_last_line(top_window),.matrix_cur_line(cur_window),
        .matrix_next_line(bot_window),.O_tlast(O_tlast),.O_tuser(O_tuser),
        .O_tdata(O_tdata),.O_tvalid(O_tvalid),.O_tready(O_tready));
endmodule
