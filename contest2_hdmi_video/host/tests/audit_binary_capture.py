"""Diagnose captured HDMI RGB against binary rules; not pristine ISP or RTL proof."""
import argparse,json,hashlib,sys
from collections import Counter,deque
from pathlib import Path
import cv2
import numpy as np
from test_hand_blob_scan import ROOT
from prototype_hand_binary_features import metrics
from evaluate_hand_binary_rules import classify
sys.path.insert(0,str(ROOT/'host'))
from hand_fpga_grid_model import masks

def main():
 p=argparse.ArgumentParser();p.add_argument('--input',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False)
 words=np.memmap(a.input/'groups.bin',dtype='>u4',mode='r').reshape(-1,180,320)
 manifest=json.loads((a.input/'manifest.json').read_text());fps=manifest['fps']
 votes=deque(maxlen=5);held=miss=0;backlit=False;trace=[];counts=Counter();panels=[]
 selected={0,90,150,210,240,270,300,390,480}
 for frame,packed in enumerate(words):
  channels=[((packed>>s)&1023).astype(np.int32) for s in (20,10,0)]
  r,g,b=[(v[1::2,::2]+v[1::2,1::2])>>1 for v in channels]
  seed,grown=masks(r,g,b);components=[];qualified=[]
  for mode,mask in enumerate((seed,grown)):
   n,labels,stats,_=cv2.connectedComponentsWithStats(mask,8)
   for k in range(1,n):
    x,y,w,h,area=map(int,stats[k]);region=labels==k
    reasons=[]
    if area<200:reasons.append('area_small')
    if area>2500:reasons.append('area_large')
    if w<12 or h<10:reasons.append('size_small')
    if x<=1 or x+w>=159:reasons.append('x_border')
    if 2*h>7*w or w>3*h or 5*h<3*w:reasons.append('aspect')
    mean=int(r[region].sum())//area
    if mean<(160 if backlit else 96):reasons.append('dark')
    raw=0;data={}
    if area>=20:
     data=metrics(region);data['mode']=mode;raw=classify(data)
    if not raw:reasons.append('shape')
    row=dict(mode=mode,x=x,y=y,w=w,h=h,area=area,mean_r=mean,raw=raw,reject=reasons,
             row3=int(data.get('row3',0)),extent=round(area/(w*h),4))
    components.append(row)
    if not reasons:
     qualified.append((area*min(mean,384),-int(data['anchor_key']),-mode,row))
  best=max(qualified,key=lambda c:c[:3])[3] if qualified else None
  raw=best['raw'] if best else 0;votes.append(raw)
  if not raw:
   miss+=1
   if miss>=5:held=0;votes.clear()
  else:
   miss=0;v,n=Counter(votes).most_common(1)[0]
   if v and n>=(2 if not held else 3):held=v
  bright=int(((r>=960)&(g>=960)&(b>=960)).sum())
  trace.append(dict(frame=frame,time_s=frame/fps,seed=int(seed.sum()),grown=int(grown.sum()),backlit=backlit,
                    raw=raw,id=held,best=best,components=sorted(components,key=lambda c:-c['area'])[:12]))
  counts[str(held)]+=1
  if frame in selected:
   image=cv2.imread(str(a.input/f'frame_{frame:04d}.jpg'))
   if image is None:raise RuntimeError('Selected source thumbnail missing')
   thumb=cv2.resize(image,(320,180),interpolation=cv2.INTER_AREA)
   sm=cv2.cvtColor(cv2.resize(seed*255,(320,180),interpolation=cv2.INTER_NEAREST),cv2.COLOR_GRAY2BGR)
   gm=cv2.cvtColor(cv2.resize(grown*255,(320,180),interpolation=cv2.INTER_NEAREST),cv2.COLOR_GRAY2BGR)
   text=np.full((180,400,3),240,np.uint8)
   lines=[f'{frame/fps:.2f}s f{frame} model id={held} raw={raw}',f'seed={seed.sum()} grown={grown.sum()}']
   for c in sorted(components,key=lambda c:-c['area'])[:4]:
    lines.append(f"m{c['mode']} a{c['area']} {c['w']}x{c['h']} row3={c['row3']}")
    lines.append(','.join(c['reject']) or 'ACCEPT')
   for i,line in enumerate(lines):cv2.putText(text,line,(4,15+i*16),cv2.FONT_HERSHEY_SIMPLEX,.39,(20,20,20),1,cv2.LINE_AA)
   panels.append(np.concatenate((thumb,sm,gm,text),axis=1))
  if bright>=450:backlit=True
  elif bright<225:backlit=False
 cv2.imwrite(str(a.out/'diagnostics.jpg'),np.concatenate(panels,axis=0))
 (a.out/'trace.json').write_text(json.dumps(trace,indent=2))
 result=dict(status='CAPTURE_BINARY_SOFTWARE_DIAGNOSIS_NOT_RTL_OR_BOARD',source_sha256=manifest['sha256'],frames=len(trace),counts=dict(counts),
             first_frame_reference=False,capture_domain=manifest['capture_domain'],input_sha256=hashlib.sha256((a.input/'groups.bin').read_bytes()).hexdigest())
 (a.out/'result.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
if __name__=='__main__':main()
