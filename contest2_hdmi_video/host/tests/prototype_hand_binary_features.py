"""Two-class resource feasibility: area, hull and grid perimeter, NO MCU.

Feature distributions are research evidence only, not RTL or deployed quality.
Select from all grown CCL regions using unchanged cheap color/box gates and
area*clipped(floor mean R). This intentionally explores replacing expensive
seed association/palm/defect/width classification, not pretending equivalence.
"""
import argparse,csv,hashlib,json,sys
from pathlib import Path
import cv2
import numpy as np
from test_hand_blob_scan import ROOT
sys.path.insert(0,str(ROOT/'host'))
from hand_fpga_grid_model import masks,candidates

def metrics(region):
 yy,xx=np.nonzero(region);x=int(xx.min());y=int(yy.min());w=int(xx.max())-x+1;h=int(yy.max())-y+1
 local=region[y:y+h,x:x+w].astype(np.int16);padded=np.pad(local,1)
 perimeter=int(np.abs(np.diff(padded,axis=0)).sum()+np.abs(np.diff(padded,axis=1)).sum())
 points=np.stack((xx,yy),axis=1).astype(np.int32);hull=cv2.convexHull(points)[:,0,:]
 area2=abs(sum(int(a[0])*int(b[1])-int(a[1])*int(b[0]) for a,b in zip(hull,np.roll(hull,-1,axis=0))))
 hp=sum(abs(int(a[0])-int(b[0]))+abs(int(a[1])-int(b[1])) for a,b in zip(hull,np.roll(hull,-1,axis=0)))
 area=len(xx)
 support=[]
 for orientation in (local,local.T):
  rows3=rows4=0
  for row in orientation:
   d=np.diff(np.pad(row,(1,1)));starts=np.flatnonzero(d==1);ends=np.flatnonzero(d==-1)-1
   count=0;previous=-99
   for start,end in zip(starts,ends):
    if end-start+1<2:continue
    if start-previous-1>=2:count+=1
    previous=int(end)
   rows3+=count>=3;rows4+=count>=4
  support.extend((int(rows3),int(rows4)))
 return dict(x=x,y=y,w=w,h=h,area=area,anchor_key=int((yy*256+xx).min()),perimeter=perimeter,hull_perimeter=hp,hull_area2=area2,
  solidity=round(2*area/max(area2,1),5),convexity=round((hp+4)/max(perimeter,1),5),
  compactness=round(16*area/max(perimeter*perimeter,1),5),aspect=round(h/w,5),extent=round(area/(w*h),5),
  row3=support[0],row4=support[1],col3=support[2],col4=support[3])

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--regions',choices=('grown','both','associated'),default='grown');a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);records=[];all_records=[];input_hashes={};summary={}
 for dataset,folder,labels_name in [('old','hand_hdmi_20261017','hand_hdmi_20261017_labels.json'),('new','hand_hdmi_162050','hand_hdmi_162050_labels_audited.json')]:
  path=ROOT/'tmp'/folder/'native/groups.bin';labelpath=ROOT/'host/tests'/labels_name
  labels=json.loads(labelpath.read_text());words=np.memmap(path,dtype='>u4',mode='r').reshape(-1,180,320)
  for src in (path,labelpath):input_hashes[str(src.relative_to(ROOT))]=hashlib.sha256(src.read_bytes()).hexdigest()
  backlit=False
  for frame,packed in enumerate(words):
   rgb=[((packed>>s)&1023).astype(np.int32) for s in (20,10,0)]
   r,g,b=[(v[1::2,::2]+v[1::2,1::2])>>1 for v in rgb];seed,grown=masks(r,g,b)
   inputs=[]
   if a.regions=='associated':
    inputs=[(0,region,x,y,w,h,area) for region,x,y,w,h,area in candidates(r,g,b)]
   else:
    for mode,mask in ([(1,grown)] if a.regions=='grown' else [(0,seed),(1,grown)]):
     n,regions,stats,_=cv2.connectedComponentsWithStats(mask,8)
     inputs.extend((mode,regions==k,*map(int,stats[k])) for k in range(1,n))
   found=[]
   label=next((s['id'] for s in labels['segments'] if s['start']<=frame<=s['end']),-1)
   for k,(mode,region,x,y,w,h,area) in enumerate(inputs):
    if area<50 or area>2500 or w<12 or h<10 or x<=1 or x+w>=159 or h>3.5*w or w>3*h or 5*h<3*w:continue
    mean=int(r[region].sum())//area
    if mean<(160 if backlit else 96):continue
    found.append((area*min(mean*100,38400),k,region,mean))
    all_records.append(dict(dataset=dataset,frame=frame,label=label,mode=mode,score=area*min(mean*100,38400),mean_r=mean,**metrics(region)))
   best=max(found,key=lambda c:c[0]) if found else None
   row=dict(dataset=dataset,frame=frame,label=label,found=int(best is not None))
   row.update(metrics(best[2]) if best else {k:0 for k in ('x','y','w','h','area','perimeter','hull_perimeter','hull_area2','solidity','convexity','compactness','aspect','extent','row3','row4','col3','col4')})
   records.append(row)
   bright=int(((r>=960)&(g>=960)&(b>=960)).sum())
   if bright>=450:backlit=True
   elif bright<225:backlit=False
  stats_by_label={}
  for label in (0,1,2,3):
   rows=[row for row in records if row['dataset']==dataset and row['label']==label]
   valid=[row for row in rows if row['found']]
   stats_by_label[label]=dict(frames=len(rows),found=len(valid),quantiles={key:np.quantile([v[key] for v in valid],[0,.1,.5,.9,1]).round(4).tolist() for key in ('solidity','convexity','compactness','aspect','extent','row3','col3')} if valid else {})
  summary[dataset]=stats_by_label
 with (a.out/'features.csv').open('w',newline='') as f:
  writer=csv.DictWriter(f,records[0]);writer.writeheader();writer.writerows(records)
 with (a.out/'all_candidates.csv').open('w',newline='') as f:
  writer=csv.DictWriter(f,all_records[0]);writer.writeheader();writer.writerows(all_records)
 (a.out/'result.json').write_text(json.dumps(dict(status='BINARY_FEATURE_RESEARCH_NOT_RTL',regions=a.regions,summary=summary,input_hashes=input_hashes),indent=2))
 print(json.dumps(summary,indent=2))
if __name__=='__main__':main()
