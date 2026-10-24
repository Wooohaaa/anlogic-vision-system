`timescale 1ns/1ps
// Final reference classifier: two-cut widths, axial acceptance, asymmetric
// thumb suppression, and single-finger direction. No temporal voting here.
// IDs: 0 ambiguous(two tips),1 fist,2 point,3 open(>=3 tips).
// Tips arrive in distance-descending order. End may accompany last valid or
// be sent alone for empty input. More than seven or out-of-box tips fault.
// All probes refer to the immutable selected-component local bitmap.
module ua_hand_tip_filter #(parameter PARALLEL_COMPARE=0,DSP_PRODUCT=1)(
 input I_clk,I_rst_n,I_clear,I_start,
 input[7:0]I_width,I_center_x,input[6:0]I_height,I_center_y,input[10:0]I_radius_q4,
 input signed[9:0]I_wrist_dx2,I_wrist_dy2,
 input I_tip_valid,I_tip_end,input[7:0]I_tip_x,input[6:0]I_tip_y,
 output O_start_ready,O_tip_ready,
 output O_probe,output[7:0]O_probe_x,output[6:0]O_probe_y,
 input I_probe_ready,I_probe_valid,I_probe_pixel,
 output reg O_busy,O_done,O_fault,output reg[1:0]O_raw,output reg[2:0]O_tip_count
);
localparam IDLE=0,LOAD=1,DISPATCH=2,MUL_START=3,MUL_WAIT=4,
 WIDTH_START=5,WIDTH_WAIT=6,RESOLVE=7,FINISH=8,FAIL=9,NEXT_TIP=10;
reg[3:0]state,operation;
reg[7:0]width,cx,tx[0:1];reg[6:0]height,cy,ty[0:1];reg[10:0]radius;
reg signed[9:0]wx,wy;reg[2:0]original_count;reg tip;
reg[19:0]wrist2;reg[17:0]distance2[0:1];reg signed[20:0]dot[0:1];
reg[41:0]dot_square[0:1];reg[37:0]norm_product[0:1];
reg[1:0]accepted,complete;
wire primary=distance2[1]>distance2[0];
wire secondary=!primary;
reg signed[31:0]held_product;
wire signed[9:0]dx=($signed({1'b0,tx[tip]})-$signed({1'b0,cx}))*10'sd2;
wire signed[9:0]dy=($signed({2'b0,ty[tip]})-$signed({2'b0,cy}))*10'sd2;
wire[9:0]abs_dx=dx[9] ? -dx : dx,abs_dy=dy[9] ? -dy : dy;
wire[9:0]abs_wx=wx[9] ? -wx : wx,abs_wy=wy[9] ? -wy : wy;
wire[20:0]abs_dot=dot[tip][20] ? -dot[tip] : dot[tip];
reg[41:0]mul_a;reg[20:0]mul_b;wire mul_done;wire[62:0]product;
reg[62:0]scaled_left;reg compare_single;
wire signed[31:0]signed_product=(operation==4 ? (dx[9]^wx[9]) : (dy[9]^wy[9])) ?
                                             -$signed(product[31:0]) : $signed(product[31:0]);
generate if(PARALLEL_COMPARE)begin:gen_parallel_reference_product
 wire[63:0]full_product;
 ua_hand_product_serial product_core(.I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(I_clear || state==FAIL),
 .I_start(state==MUL_START),.I_a(mul_a[31:0]),.I_b({11'd0,mul_b}),.O_busy(),.O_done(mul_done),.O_product(full_product));
 assign product=full_product[62:0];
end else begin:gen_shared_product
ua_hand_product_serial #(.A_BITS(42),.B_BITS(21),.HARD_MULTIPLY(DSP_PRODUCT)) product_core(.I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(I_clear || state==FAIL),
 .I_start(state==MUL_START),.I_a(mul_a),.I_b(mul_b),.O_busy(),.O_done(mul_done),.O_product(product));
end endgenerate
always @*begin
 mul_a=0;mul_b=0;
 case(operation)
 0:begin mul_a={32'd0,abs_wx};mul_b={11'd0,abs_wx};end
 1:begin mul_a={32'd0,abs_wy};mul_b={11'd0,abs_wy};end
 2:begin mul_a={32'd0,abs_dx};mul_b={11'd0,abs_dx};end
 3:begin mul_a={32'd0,abs_dy};mul_b={11'd0,abs_dy};end
 4:begin mul_a={32'd0,abs_dx};mul_b={11'd0,abs_wx};end
 5:begin mul_a={32'd0,abs_dy};mul_b={11'd0,abs_wy};end
 6:begin mul_a={21'd0,abs_dot};mul_b=abs_dot;end
 7:begin mul_a={24'd0,distance2[tip]};mul_b={1'd0,wrist2};end
 8:begin mul_a=dot_square[tip];mul_b=21'd25;end
 9:begin mul_a={4'd0,norm_product[tip]};mul_b=compare_single ? 21'd16 : 21'd9;end
 10:begin mul_a=dot_square[primary];mul_b=21'd100;end
 11:begin mul_a={4'd0,norm_product[primary]};mul_b=21'd81;end
 12:begin mul_a=dot_square[secondary];mul_b=21'd400;end
 13:begin mul_a={4'd0,norm_product[secondary]};mul_b=21'd289;end
 endcase
end
wire width_ready,width_done,width_fault,width_narrow;wire[1:0]width_valid;
ua_hand_tip_width width_core(.I_clk(I_clk),.I_rst_n(I_rst_n),.I_clear(I_clear || state==FAIL),
 .I_start(state==WIDTH_START),.I_width(width),.I_center_x(cx),.I_tip_x(tx[tip]),
 .I_height(height),.I_center_y(cy),.I_tip_y(ty[tip]),.I_radius_q4(radius),
 .O_start_ready(width_ready),.O_probe(O_probe),.O_probe_x(O_probe_x),.O_probe_y(O_probe_y),
 .I_probe_ready(I_probe_ready),.I_probe_valid(I_probe_valid),.I_probe_pixel(I_probe_pixel),
 .O_busy(),.O_done(width_done),.O_fault(width_fault),.O_narrow(width_narrow),
 .O_width_valid(width_valid),.O_width0(),.O_width1());
wire[31:0]secondary25=({14'd0,distance2[secondary]}<<4)+({14'd0,distance2[secondary]}<<3)+{14'd0,distance2[secondary]};
wire thumb_precheck=complete[primary] && ({14'd0,distance2[primary]}<<4)>=secondary25 && dot[primary]<0;
wire single=accepted[0] ? 1'b0 : 1'b1;
// Verification/resource comparison branch. Default serial datapath prunes
// these parallel scaled adders; retain this exact contract as an A/B control.
wire[63:0]parallel_dot25=({22'd0,dot_square[tip]}<<4)+({22'd0,dot_square[tip]}<<3)+{22'd0,dot_square[tip]};
wire[63:0]parallel_norm9=({26'd0,norm_product[tip]}<<3)+{26'd0,norm_product[tip]};
wire[63:0]parallel_primary100=({22'd0,dot_square[primary]}<<6)+({22'd0,dot_square[primary]}<<5)+({22'd0,dot_square[primary]}<<2);
wire[63:0]parallel_primary81=({26'd0,norm_product[primary]}<<6)+({26'd0,norm_product[primary]}<<4)+{26'd0,norm_product[primary]};
wire[63:0]parallel_secondary400=({22'd0,dot_square[secondary]}<<8)+({22'd0,dot_square[secondary]}<<7)+({22'd0,dot_square[secondary]}<<4);
wire[63:0]parallel_secondary289=({26'd0,norm_product[secondary]}<<8)+({26'd0,norm_product[secondary]}<<5)+{26'd0,norm_product[secondary]};
wire parallel_thumb=thumb_precheck && parallel_primary100>=parallel_primary81 &&
 (dot[secondary]>=0 || parallel_secondary400<parallel_secondary289);
wire[63:0]parallel_single25=({22'd0,dot_square[single]}<<4)+({22'd0,dot_square[single]}<<3)+{22'd0,dot_square[single]};
wire parallel_single=dot[single]<0 && parallel_single25>=({26'd0,norm_product[single]}<<4);
assign O_start_ready=state==IDLE && width_ready && !I_clear && I_rst_n;
assign O_tip_ready=state==LOAD && !I_clear && I_rst_n;
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
  state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_raw<=0;O_tip_count<=0;original_count<=0;
  width<=0;height<=0;cx<=0;cy<=0;radius<=0;wx<=0;wy<=0;tip<=0;operation<=0;wrist2<=0;
  accepted<=0;complete<=0;held_product<=0;scaled_left<=0;compare_single<=0;
 end else if(I_clear)begin state<=IDLE;O_busy<=0;O_done<=0;O_fault<=0;O_raw<=0;O_tip_count<=0;end
 else begin
  O_done<=0;
  case(state)
  IDLE:if(I_start && O_start_ready)begin
   width<=I_width;height<=I_height;cx<=I_center_x;cy<=I_center_y;radius<=I_radius_q4;wx<=I_wrist_dx2;wy<=I_wrist_dy2;
   O_busy<=1;O_fault<=0;O_raw<=0;O_tip_count<=0;original_count<=0;accepted<=0;complete<=0;
   state<=I_width==0 || I_width>160 || I_height==0 || I_height>90 || I_center_x>=I_width || I_center_y>=I_height ? FAIL : LOAD;
  end
  LOAD:begin
   if(I_tip_valid)begin
    if(original_count==7 || I_tip_x>=width || I_tip_y>=height)state<=FAIL;
    else begin
     original_count<=original_count+3'd1;
     if(original_count<2)begin tx[original_count[0]]<=I_tip_x;ty[original_count[0]]<=I_tip_y;end
     if(I_tip_end)state<=DISPATCH;
    end
   end else if(I_tip_end)state<=DISPATCH;
  end
  DISPATCH:begin
   if(original_count==0)begin O_raw<=1;O_tip_count<=0;state<=FINISH;end
   else if(original_count>=3)begin O_raw<=3;O_tip_count<=original_count;state<=FINISH;end
   else begin operation<=0;tip<=0;state<=MUL_START;end
  end
  MUL_START:state<=MUL_WAIT;
  MUL_WAIT:if(mul_done)begin
   state<=MUL_START;operation<=operation+4'd1;
   case(operation)
   0:held_product<=product[31:0];
   1:wrist2<=held_product+product[31:0];
   2:held_product<=product[31:0];
   3:distance2[tip]<=held_product+product[31:0];
   4:held_product<=signed_product;
   5:dot[tip]<=held_product+signed_product;
   6:dot_square[tip]<=product[41:0];
   7:begin norm_product[tip]<=product[37:0];state<=WIDTH_START;end
   8,10,12:scaled_left<=product;
   9:begin
    if(compare_single)begin
     O_raw<=dot[tip]<0 && scaled_left>=product ? 2 : 1;
     O_tip_count<=dot[tip]<0 && scaled_left>=product ? 1 : 0;state<=FINISH;
    end else begin accepted[tip]<=dot[tip]<0 && scaled_left>=product;state<=NEXT_TIP;end
   end
   11:begin
    if(scaled_left<product)begin O_raw<=0;O_tip_count<=2;state<=FINISH;end
    else if(dot[secondary]>=0)begin O_raw<=2;O_tip_count<=1;state<=FINISH;end
   end
   13:begin O_raw<=scaled_left<product ? 2 : 0;O_tip_count<=scaled_left<product ? 1 : 2;state<=FINISH;end
   default:state<=FAIL;
   endcase
  end
  WIDTH_START:if(width_ready)state<=WIDTH_WAIT;
  WIDTH_WAIT:if(width_done)begin
   if(width_fault)state<=FAIL;
   else begin
    complete[tip]<=&width_valid;
    if(PARALLEL_COMPARE)begin
     accepted[tip]<=width_narrow && (original_count==1 || (dot[tip]<0 && parallel_dot25>=parallel_norm9));state<=NEXT_TIP;
    end else if(width_narrow && original_count==2)begin operation<=8;compare_single<=0;state<=MUL_START;end
    else begin accepted[tip]<=width_narrow;state<=NEXT_TIP;end
   end
  end
  NEXT_TIP:begin
   if(!tip && original_count==2)begin tip<=1;operation<=2;state<=MUL_START;end
   else state<=RESOLVE;
  end
  RESOLVE:begin
   if(accepted==0)begin O_raw<=1;O_tip_count<=0;state<=FINISH;end
   else if(PARALLEL_COMPARE)begin
    if(accepted==3)begin O_raw<=parallel_thumb ? 2 : 0;O_tip_count<=parallel_thumb ? 1 : 2;end
    else begin O_raw<=parallel_single ? 2 : 1;O_tip_count<=parallel_single ? 1 : 0;end
    state<=FINISH;
   end
   else if(accepted==3)begin
    if(thumb_precheck)begin operation<=10;state<=MUL_START;end
    else begin O_raw<=0;O_tip_count<=2;state<=FINISH;end
   end else begin tip<=single;operation<=8;compare_single<=1;state<=MUL_START;end
  end
  FINISH:begin O_busy<=0;O_done<=1;state<=IDLE;end
  FAIL:begin O_busy<=0;O_done<=1;O_fault<=1;O_raw<=0;O_tip_count<=0;state<=IDLE;end
  default:state<=FAIL;
  endcase
 end
end
endmodule
