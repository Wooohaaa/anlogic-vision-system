"""Deterministic software stress, not RTL equivalence or unseen-video accuracy.
No first-frame reference: reset only the hardware-equivalent vote/backlight.
"""
import argparse,hashlib,json,sys
from pathlib import Path
from collections import Counter,deque
import cv2
import numpy as np
from test_hand_blob_scan import ROOT
from prototype_hand_binary_features import metrics
from evaluate_hand_binary_rules import classify
sys.path.insert(0,str(ROOT/'host'))
from hand_fpga_grid_model import masks

def main():
 p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve();summary=[];hashes={}
 for source in (Path(__file__),ROOT/'host/tests/prototype_hand_binary_features.py',ROOT/'host/tests/evaluate_hand_binary_rules.py',ROOT/'host/hand_fpga_grid_model.py'):
  hashes[str(source.relative_to(ROOT))]=hashlib.sha256(source.read_bytes()).hexdigest()
 conditions=('original','dark_65pct','dark_40pct','low_contrast','green_shift','noise_2dn')
 for condition in conditions:
  rng=np.random.default_rng(181046)
  for ds,folder,lp in [('old','hand_hdmi_20261017','hand_hdmi_20261017_labels.json'),('new','hand_hdmi_162050','hand_hdmi_162050_labels_audited.json')]:
   source=ROOT/'tmp'/folder/'native/groups.bin';labelpath=ROOT/'host/tests'/lp
   for path in (source,labelpath):hashes[str(path.relative_to(ROOT))]=hashlib.sha256(path.read_bytes()).hexdigest()
   words=np.memmap(source,dtype='>u4',mode='r').reshape(-1,180,320)
   labels=json.loads(labelpath.read_text());votes=deque(maxlen=5);held=miss=0;backlit=False;counts={};trace=[]
   for frame,packed in enumerate(words):
    channels=[((packed>>s)&1023).astype(np.int32) for s in (20,10,0)]
    if condition.startswith('dark_'):channels=[v*(65 if condition=='dark_65pct' else 40)//100 for v in channels]
    elif condition=='low_contrast':channels=[v*65//100+96 for v in channels]
    elif condition=='green_shift':channels=[channels[0]*92//100,channels[1]*105//100,channels[2]*105//100]
    elif condition=='noise_2dn':channels=[v+rng.normal(0,8,v.shape).round().astype(np.int32) for v in channels]
    channels=[np.clip(v,0,1020) for v in channels]
    r,g,b=[(v[1::2,::2]+v[1::2,1::2])>>1 for v in channels];found=[]
    for mode,mask in enumerate(masks(r,g,b)):
     n,regions,stats,_=cv2.connectedComponentsWithStats(mask,8)
     for k in range(1,n):
      x,y,w,h,area=map(int,stats[k])
      if area<200 or area>2500 or w<12 or h<10 or x<=1 or x+w>=159 or 2*h>7*w or w>3*h or 5*h<3*w:continue
      region=regions==k;mean=int(r[region].sum())//area
      if mean<(160 if backlit else 96):continue
      data=metrics(region);data['mode']=mode;raw=classify(data)
      if raw:found.append((area*min(mean,384),-data['anchor_key'],-mode,raw))
    raw=max(found)[3] if found else 0;votes.append(raw)
    if not raw:
     miss+=1
     if miss>=5:held=0;votes.clear()
    else:
     miss=0;v,n=Counter(votes).most_common(1)[0]
     if v and n>=(2 if not held else 3):held=v
    bright=int(((r>=960)&(g>=960)&(b>=960)).sum())
    if bright>=450:backlit=True
    elif bright<225:backlit=False
    label=next((s['id'] for s in labels['segments'] if s['start']<=frame<=s['end']),-1)
    if label>=0:
     counts.setdefault(label,dict(frames=0,correct=0));counts[label]['frames']+=1;counts[label]['correct']+=int(held==(0 if label==2 else label))
    trace.append(dict(frame=frame,label=label,id=held,raw=raw))
   summary.append(dict(condition=condition,dataset=ds,labels=counts))
   (out/(condition+'_'+ds+'.json')).write_text(json.dumps(trace))
   print(condition,ds,counts,flush=True)
 for path,digest in hashes.items():
  if hashlib.sha256((ROOT/path).read_bytes()).hexdigest()!=digest:raise RuntimeError('input changed')
 (out/'result.json').write_text(json.dumps(dict(status='BINARY_SOFTWARE_CONDITION_CHARACTERIZATION_NOT_BOARD',conditions=summary,hashes=hashes),indent=2))
if __name__=='__main__':main()
