// Frozen verified v47 baseline. Test-only; not a production compilation unit.
`timescale 1ns/1ps
// Isolated detection frontend, not yet selected by isp_top_user.
// Input: four RGB888 pixels/group; sampled source rows may arrive with bubbles.
// Keep y=7 mod 8, average adjacent groups -> square 8x8-source-pixel grid.
// Two immutable-owned frame banks, 3 bits/pixel: {working,loose,seed}.
// Capture never stalls the video bus. An unavailable bank drops a complete
// detection frame explicitly; neither a partial frame nor a busy bank is read.
module v47_ua_hand_mask_frame #(
    parameter integer IMG_WIDTH=1280,
    parameter integer IMG_HEIGHT=720,
    parameter integer EXTERNAL_CAPTURE_GATE=0
)(
    input wire I_clk,I_rst_n,I_clear,
    input wire I_sample_valid,I_frame_done,
    input wire [9:0] I_x_grp,I_y,
    input wire [95:0] I_rgb,
    output reg O_mask_valid,
    output reg O_mask_bank,
    output reg [15:0] O_frame_id,
    input wire I_mask_release,
    input wire I_read,
    input wire [11:0] I_read_addr,
    output wire O_read_valid,
    output wire [17:0] O_read_data,
    output reg O_drop_pulse,
    output reg O_input_fault,
    output reg [31:0] O_process_cycles,
    // Gate is sampled ONLY at frame start; never pauses/partially captures
    // video. Disabled by default for old two-bank ownership compatibility.
    input wire I_capture_allow,
    // Provisional native 160x90 samples, same averaging/phase as mask input.
    // A caller may use geometry scratch for R capture, then reuse it after
    // CCL statistics. Do not consume a partial/faulted/unpublished bank.
    output reg O_native_valid,O_native_bank,O_native_bright,
    output reg[13:0]O_native_address,output reg[9:0]O_native_red
);
    localparam integer W=IMG_WIDTH/8,H=IMG_HEIGHT/8;
    localparam integer RW=(W+5)/6,WORDS=RW*H;
    localparam [2:0] IDLE=0,LOAD=1,TAKE=2,WRITE=3,READY=4;
    reg [2:0] state;
    reg [1:0] allocated,pending;
    reg capture_active,capture_bank,capture_bad;
    reg [15:0] sequence_id,bank_id0,bank_id1;
    reg [7:0] capture_x,capture_y;
    reg [14:0] capture_pixels;
    reg [11:0] capture_addr;
    reg [2:0] capture_slot;
    reg [17:0] capture_word;
    reg capture_we;
    reg [11:0] capture_wa;
    reg [17:0] capture_wd;
    reg capture_wbank;
    reg even_valid;
    reg [9:0] even_x,even_y,even_r,even_g,even_b;
    wire [9:0] rs={2'b0,I_rgb[95:88]}+{2'b0,I_rgb[71:64]}+{2'b0,I_rgb[47:40]}+{2'b0,I_rgb[23:16]};
    wire [9:0] gs={2'b0,I_rgb[87:80]}+{2'b0,I_rgb[63:56]}+{2'b0,I_rgb[39:32]}+{2'b0,I_rgb[15:8]};
    wire [9:0] bs={2'b0,I_rgb[79:72]}+{2'b0,I_rgb[55:48]}+{2'b0,I_rgb[31:24]}+{2'b0,I_rgb[7:0]};
    wire [10:0] pr={1'b0,even_r}+{1'b0,rs},pg={1'b0,even_g}+{1'b0,gs},pb={1'b0,even_b}+{1'b0,bs};
    wire [9:0] r=pr[10:1],g=pg[10:1],b=pb[10:1];
    wire[13:0]native_row_address=W==160 ? (({7'd0,capture_y}<<7)+({7'd0,capture_y}<<5)) : capture_y*W;
    wire [9:0] rg=r-g,gb=g-b;
    wire [13:0] rg12={1'b0,rg,3'b000}+{2'b00,rg,2'b00};
    wire [14:0] gb32={gb,5'b00000};
    wire [9:0] gb_floor=(gb < 10'd8) ? 10'd8 : gb;
    wire [11:0] gb3={2'b00,gb_floor}+{1'b0,gb_floor,1'b0};
    wire seed=(r>=10'd96)&&({1'b0,r}>={1'b0,g}+11'd16)&&
              ({1'b0,g}>={1'b0,b}+11'd16)&&
              ({1'b0,rg}<={gb,1'b0})&&({rg,1'b0}>={1'b0,gb})&&
              (rg12>={4'b0,r})&&(gb32>={5'b0,g});
    wire loose=(r>=10'd16)&&({1'b0,r}>={1'b0,g}+11'd4)&&g>=b&&
               rg12>={4'b0,r}&&gb32>={5'b0,g}&&{2'b0,rg}<=gb3;
    reg [17:0] packed_next;
    always @* begin
        packed_next=capture_word;
        packed_next[capture_slot*3 +:3]={seed,loose,seed};
    end

    reg process_bank;
    reg [3:0] pass;
    reg [7:0] row;
    reg [5:0] word_col,load_word;
    reg [1:0] upper_slot,current_slot,lower_slot,load_slot,initial_row;
    reg initial_load;
    reg signed [9:0] load_y;
    reg [31:0] cycles;
    wire invalid_load=load_y<0 || load_y>=H;
    wire internal_read=state==LOAD&&!invalid_load;
    wire ram_read=I_rst_n&&!I_clear&&(internal_read||(state==READY&&O_mask_valid&&I_read));
    wire ram_bank=internal_read?process_bank:O_mask_bank;
    wire [11:0] ram_addr=internal_read?(load_y*RW+load_word):I_read_addr;
    wire ram_valid;
    wire [17:0] ram_data;
    wire process_we=I_rst_n&&!I_clear&&state==WRITE;
    wire [11:0] process_wa=row*RW+word_col;
    reg [17:0] process_wd;
    assign O_read_valid=ram_valid&&state==READY&&O_mask_valid;
    assign O_read_data=ram_data;

    // These small, unreset line caches use logic RAM; frame storage is ERAM.
    // Pointer rotation preserves the OLD preceding row during an in-place pass.
    // Re-reading an already updated previous row would incorrectly flood-fill.
    /* fehdl force_ram=0, ram_style="distributed" */ reg [17:0] line0[0:RW-1];
    /* fehdl force_ram=0, ram_style="distributed" */ reg [17:0] line1[0:RW-1];
    /* fehdl force_ram=0, ram_style="distributed" */ reg [17:0] line2[0:RW-1];
    wire cache_store=(state==TAKE)||(state==LOAD&&invalid_load);
    wire [17:0] cache_data=invalid_load?18'd0:ram_data;
    always @(posedge I_clk) begin
        if(cache_store&&load_slot==0)line0[load_word]<=cache_data;
        if(cache_store&&load_slot==1)line1[load_word]<=cache_data;
        if(cache_store&&load_slot==2)line2[load_word]<=cache_data;
    end
    function [17:0] cache_word;
        input [1:0] slot;input integer address;
        begin
            case(slot)
                0:cache_word=line0[address];
                1:cache_word=line1[address];
                default:cache_word=line2[address];
            endcase
        end
    endfunction
    function tap;
        input integer dy,dx,pixel;
        input border;
        integer absolute_x,absolute_y,slot,word_address;
        reg [1:0] bank;reg [17:0] value;
        begin
            absolute_x=word_col*6+pixel+dx;absolute_y=row+dy;
            if(absolute_x<0||absolute_x>=W||absolute_y<0||absolute_y>=H)tap=border;
            else begin
                slot=pixel+dx;word_address=word_col;
                if(slot<0)begin slot=slot+6;word_address=word_address-1;end
                else if(slot>=6)begin slot=slot-6;word_address=word_address+1;end
                bank=dy<0?upper_slot:dy==0?current_slot:lower_slot;
                value=cache_word(bank,word_address);tap=value[slot*3+2];
            end
        end
    endfunction
    integer k;reg bit_next;reg [17:0] original_word;
    always @* begin
        original_word=0;process_wd=0;bit_next=0;
        // State is an explicit dependency: Verilog @* does not include memory
        // reads hidden inside a function on all supported simulators.
        if(state==WRITE)begin
        original_word=cache_word(current_slot,word_col);process_wd=original_word;
        for(k=0;k<6;k=k+1)begin
            if(word_col*6+k>=W)process_wd[k*3 +:3]=3'b000;
            else begin
                case(pass)
                    0:bit_next=tap(0,0,k,1'b1)&tap(0,1,k,1'b1);
                    1:bit_next=tap(0,-1,k,1'b0)|tap(0,0,k,1'b0);
                    2,9,10:bit_next=tap(-1,-1,k,1'b0)|tap(-1,0,k,1'b0)|tap(0,-1,k,1'b0)|tap(0,0,k,1'b0);
                    3,8,11:bit_next=tap(0,0,k,1'b1)&tap(0,1,k,1'b1)&tap(1,0,k,1'b1)&tap(1,1,k,1'b1);
                    default:bit_next=(tap(-1,-1,k,1'b0)|tap(-1,0,k,1'b0)|tap(-1,1,k,1'b0)|
                                      tap(0,-1,k,1'b0)|tap(0,0,k,1'b0)|tap(0,1,k,1'b0)|
                                      tap(1,-1,k,1'b0)|tap(1,0,k,1'b0)|tap(1,1,k,1'b0))&original_word[k*3+1];
                endcase
                process_wd[k*3+2]=bit_next;
                if(pass==3)process_wd[k*3]=bit_next;
            end
        end
        end
    end

    v47_ua_hand_mask_ram #(.WORDS(WORDS)) storage(
        .I_clk(I_clk),.I_rst_n(I_rst_n),
        .I_capture_we(capture_we&&I_rst_n&&!I_clear),.I_capture_bank(capture_wbank),.I_capture_addr(capture_wa),.I_capture_data(capture_wd),
        .I_process_we(process_we),.I_process_bank(process_bank),.I_process_addr(process_wa),.I_process_data(process_wd),
        .I_read(ram_read),.I_read_bank(ram_bank),.I_read_addr(ram_addr),.O_valid(ram_valid),.O_data(ram_data));

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)begin
            state<=IDLE;allocated<=0;pending<=0;capture_active<=0;capture_bank<=0;capture_bad<=0;
            capture_x<=0;capture_y<=0;capture_pixels<=0;capture_addr<=0;capture_slot<=0;capture_word<=0;
            capture_we<=0;capture_wa<=0;capture_wd<=0;capture_wbank<=0;
            even_valid<=0;even_x<=0;even_y<=0;even_r<=0;even_g<=0;even_b<=0;
            sequence_id<=0;bank_id0<=0;bank_id1<=0;
            O_mask_valid<=0;O_mask_bank<=0;O_frame_id<=0;O_drop_pulse<=0;O_input_fault<=0;O_process_cycles<=0;
            O_native_valid<=0;O_native_bank<=0;O_native_bright<=0;O_native_address<=0;O_native_red<=0;
            process_bank<=0;pass<=0;row<=0;word_col<=0;load_word<=0;upper_slot<=0;current_slot<=1;lower_slot<=2;
            load_slot<=0;initial_row<=0;initial_load<=0;load_y<=0;cycles<=0;
        end else if(I_clear)begin
            state<=IDLE;allocated<=0;pending<=0;capture_active<=0;capture_bad<=0;capture_we<=0;even_valid<=0;
            capture_pixels<=0;capture_addr<=0;capture_slot<=0;capture_word<=0;capture_x<=0;capture_y<=0;
            O_mask_valid<=0;O_drop_pulse<=0;O_input_fault<=0;O_process_cycles<=0;cycles<=0;
            O_native_valid<=0;O_native_bright<=0;
        end else begin
            capture_we<=0;O_drop_pulse<=0;O_native_valid<=0;
            if(state!=IDLE&&state!=READY)cycles<=cycles+1'b1;
            if(I_sample_valid&&I_y[2:0]==3'd7)begin
                if(!I_x_grp[0])begin
                    even_r<=rs;even_g<=gs;even_b<=bs;even_x<=I_x_grp;even_y<=I_y;even_valid<=1;
                    if(I_x_grp==0&&I_y==7)begin
                        capture_bad<=0;capture_pixels<=0;capture_addr<=0;capture_slot<=0;capture_word<=0;capture_x<=0;capture_y<=0;
                        if(EXTERNAL_CAPTURE_GATE && !I_capture_allow)begin capture_active<=0;O_drop_pulse<=1;end
                        else if(!allocated[0])begin capture_bank<=0;allocated[0]<=1;capture_active<=1;end
                        else if(!allocated[1])begin capture_bank<=1;allocated[1]<=1;capture_active<=1;end
                        else begin capture_active<=0;O_drop_pulse<=1;end
                    end
                end else begin
                    even_valid<=0;
                    if(capture_active)begin
                        if(!even_valid||even_x+1'b1!=I_x_grp||even_y!=I_y||
                           I_x_grp[9:1]!=capture_x||I_y[9:3]!=capture_y)begin capture_bad<=1;O_input_fault<=1;end
                        else if(!capture_bad)begin
                            O_native_valid<=1;O_native_bank<=capture_bank;
                            O_native_address<=native_row_address+{6'd0,capture_x};O_native_red<=r;
                            O_native_bright<=r>=960 && g>=960 && b>=960;
                        end
                        capture_pixels<=capture_pixels+1'b1;
                        if(capture_x==W-1)begin capture_x<=0;capture_y<=capture_y+1'b1;end
                        else capture_x<=capture_x+1'b1;
                        if(capture_slot==5||capture_x==W-1)begin
                            capture_we<=1;capture_wbank<=capture_bank;capture_wa<=capture_addr;capture_wd<=packed_next;
                            capture_addr<=capture_addr+1'b1;capture_slot<=0;capture_word<=0;
                        end else begin capture_slot<=capture_slot+1'b1;capture_word<=packed_next;end
                    end
                end
            end
            if(I_frame_done)begin
                sequence_id<=sequence_id+1'b1;even_valid<=0;
                if(capture_active)begin
                    capture_active<=0;
                    if(!capture_bad&&capture_pixels==W*H&&capture_addr==WORDS)begin
                        pending[capture_bank]<=1;
                        if(capture_bank)bank_id1<=sequence_id;else bank_id0<=sequence_id;
                    end else begin allocated[capture_bank]<=0;O_drop_pulse<=1;O_input_fault<=1;end
                end
            end
            case(state)
                IDLE:if(pending!=0)begin
                    process_bank<=!pending[0];pending[!pending[0]]<=0;pass<=0;row<=0;word_col<=0;
                    upper_slot<=0;current_slot<=1;lower_slot<=2;load_slot<=0;load_y<=-10'sd1;load_word<=0;
                    initial_row<=0;initial_load<=1;cycles<=0;state<=LOAD;
                end
                LOAD:if(invalid_load)begin
                    if(load_word==RW-1)begin
                        load_word<=0;
                        if(initial_load&&initial_row<2)begin initial_row<=initial_row+1'b1;load_slot<=load_slot+1'b1;load_y<=load_y+1'b1;end
                        else begin word_col<=0;state<=WRITE;end
                    end else load_word<=load_word+1'b1;
                end else state<=TAKE;
                TAKE:begin
                    if(load_word==RW-1)begin
                        load_word<=0;
                        if(initial_load&&initial_row<2)begin initial_row<=initial_row+1'b1;load_slot<=load_slot+1'b1;load_y<=load_y+1'b1;state<=LOAD;end
                        else begin word_col<=0;state<=WRITE;end
                    end else begin load_word<=load_word+1'b1;state<=LOAD;end
                end
                WRITE:begin
                    if(word_col==RW-1)begin
                        word_col<=0;load_word<=0;
                        if(row==H-1)begin
                            if(pass==11)begin
                                O_mask_valid<=1;O_mask_bank<=process_bank;O_frame_id<=process_bank?bank_id1:bank_id0;
                                O_process_cycles<=cycles+1'b1;state<=READY;
                            end else begin
                                pass<=pass+1'b1;row<=0;upper_slot<=0;current_slot<=1;lower_slot<=2;
                                load_slot<=0;load_y<=-10'sd1;initial_row<=0;initial_load<=1;state<=LOAD;
                            end
                        end else begin
                            row<=row+1'b1;load_slot<=upper_slot;load_y<={2'b0,row}+10'd2;
                            upper_slot<=current_slot;current_slot<=lower_slot;lower_slot<=upper_slot;
                            initial_load<=0;state<=LOAD;
                        end
                    end else word_col<=word_col+1'b1;
                end
                READY:if(I_mask_release)begin O_mask_valid<=0;allocated[process_bank]<=0;state<=IDLE;end
                default:begin state<=IDLE;allocated<=0;pending<=0;O_mask_valid<=0;O_input_fault<=1;end
            endcase
        end
    end
`ifndef SYNTHESIS
    initial begin
        if(IMG_WIDTH%8||IMG_HEIGHT%8||W>160||H>90||W<6||H<2)$fatal(1,"Unsupported hand-mask geometry");
    end
    always @(posedge I_clk)if(I_rst_n&&!I_clear)begin
        if(capture_we&&process_we&&capture_wbank==process_bank)$fatal(1,"Hand bank ownership collision");
        if(ram_read&&ram_addr>=WORDS)$fatal(1,"Hand mask read out of bounds");
    end
`endif
endmodule

// Explicit 1024x18 blocks avoid power-of-two depth padding of a 2430-word bank.
// Default geometry: 3 ERAM per bank, 6 total. Synchronous read, one cycle.
module v47_ua_hand_mask_ram #(parameter integer WORDS=2430)(
    input wire I_clk,I_rst_n,
    input wire I_capture_we,I_capture_bank,
    input wire [11:0] I_capture_addr,input wire [17:0] I_capture_data,
    input wire I_process_we,I_process_bank,
    input wire [11:0] I_process_addr,input wire [17:0] I_process_data,
    input wire I_read,I_read_bank,input wire [11:0] I_read_addr,
    output reg O_valid,output reg [17:0] O_data
);
    localparam integer BLOCKS=(WORDS+1023)/1024;
    wire [17:0] read_values[0:2*BLOCKS-1];
    reg [2:0] read_select;
    genvar bank,block_id;
    generate for(bank=0;bank<2;bank=bank+1)begin:banks
        for(block_id=0;block_id<BLOCKS;block_id=block_id+1)begin:blocks
            /* fehdl force_ram=1, ram_style="bram" */ reg [17:0] mem[0:1023];
            reg [17:0] q;
            always @(posedge I_clk)begin
                if(I_capture_we&&I_capture_bank==bank&&I_capture_addr[11:10]==block_id)mem[I_capture_addr[9:0]]<=I_capture_data;
                else if(I_process_we&&I_process_bank==bank&&I_process_addr[11:10]==block_id)mem[I_process_addr[9:0]]<=I_process_data;
                if(I_read&&I_read_bank==bank&&I_read_addr[11:10]==block_id)q<=mem[I_read_addr[9:0]];
            end
            assign read_values[bank*BLOCKS+block_id]=q;
        end
    end endgenerate
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin O_valid<=0;read_select<=0;end
        else begin
            O_valid<=I_read;
            if(I_read)read_select<=I_read_bank*BLOCKS+I_read_addr[11:10];
        end
    end
    integer i;
    always @* begin O_data=0;for(i=0;i<2*BLOCKS;i=i+1)if(read_select==i)O_data=read_values[i];end
endmodule
