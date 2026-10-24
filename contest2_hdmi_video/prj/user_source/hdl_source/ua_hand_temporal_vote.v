`timescale 1ns/1ps
// Exact deque(maxlen=5) + Counter.most_common tie behavior in fixed reference.
// Ties prefer the ID whose FIRST occurrence in the current chronological
// window is oldest, not lowest numeric ID. Five consecutive raw zeros clear
// held ID and vote window. Candidate-presence and held ID separately gate box.
module ua_hand_temporal_vote(
 input I_clk,I_rst_n,I_clear,I_frame_valid,input[1:0]I_raw,input I_best_present,
 output reg O_valid,output reg[1:0]O_id,output reg O_box_valid
);
reg[1:0]votes[0:4];reg[2:0]count,miss;
reg[1:0]next_votes[0:4];reg[2:0]next_count,frequency,best_frequency;
reg[1:0]winner,next_id;
integer i,j,k;
always @*begin
 next_count=count<5 ? count+3'd1 : 3'd5;
 for(i=0;i<5;i=i+1)begin
  next_votes[i]=votes[i];
  if(count==5)next_votes[i]=i==4 ? I_raw : votes[i+1];
  else if(i==count)next_votes[i]=I_raw;
 end
 winner=0;best_frequency=0;frequency=0;
 for(i=0;i<5;i=i+1)begin
  frequency=0;
  for(j=0;j<5;j=j+1)if(j<next_count && next_votes[j]==next_votes[i])frequency=frequency+3'd1;
  if(i<next_count && frequency>best_frequency)begin winner=next_votes[i];best_frequency=frequency;end
 end
 next_id=O_id;
 if(I_raw==0)begin if(miss>=4)next_id=0;end
 else if(winner!=0 && best_frequency>=(O_id==0 ? 2 : 3))next_id=winner;
end
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
  O_valid<=0;O_id<=0;O_box_valid<=0;count<=0;miss<=0;
  for(k=0;k<5;k=k+1)votes[k]<=0;
 end else if(I_clear)begin O_valid<=0;O_id<=0;O_box_valid<=0;count<=0;miss<=0;end
 else begin
  O_valid<=I_frame_valid;
  if(I_frame_valid)begin
   O_id<=next_id;O_box_valid<=I_best_present && next_id!=0;
   if(I_raw==0 && miss>=4)begin count<=0;miss<=5;end
   else begin
    count<=next_count;miss<=I_raw==0 ? miss+3'd1 : 3'd0;
    for(k=0;k<5;k=k+1)votes[k]<=next_votes[k];
   end
  end
 end
end
endmodule
