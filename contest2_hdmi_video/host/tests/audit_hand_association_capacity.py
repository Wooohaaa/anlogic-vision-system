"""Size exact seed/grown association storage from both videos; NOT RTL proof.

Count lifetime provisional IDs (never recycled) in an 8-connected raster RLE
scan. A new label is allocated iff a run touches no preceding-row run. This
differs from the number of final OpenCV labels after union operations.
"""
import argparse, hashlib, json, sys
from pathlib import Path
import cv2
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'host'))
from hand_fpga_grid_model import masks
from test_hand_label_map import pixel_allocations

def provisional(mask):
 previous=[];count=0;max_runs=0
 for row in mask:
  d=np.diff(np.pad(row.astype(np.int16),(1,1)))
  runs=list(zip(np.flatnonzero(d==1),np.flatnonzero(d==-1)-1))
  count+=sum(not any(a<=q+1 and b+1>=p for p,q in previous) for a,b in runs)
  max_runs=max(max_runs,len(runs));previous=runs
 return count,max_runs

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 if a.out.exists():raise FileExistsError(a.out)
 records=[];hashes={}
 for dataset,folder in [('old','hand_hdmi_20261017'),('new','hand_hdmi_162050')]:
  path=ROOT/'tmp'/folder/'native/groups.bin'
  hashes[str(path.relative_to(ROOT))]=hashlib.sha256(path.read_bytes()).hexdigest()
  words=np.memmap(path,dtype='>u4',mode='r').reshape(-1,180,320)
  for frame,packed in enumerate(words):
   rgb=[((packed>>s)&1023).astype(np.int32) for s in (20,10,0)]
   r,g,b=[(v[1::2,::2]+v[1::2,1::2])>>1 for v in rgb]
   seed,grown=masks(r,g,b)
   ns,sl,ss,_=cv2.connectedComponentsWithStats(seed,8)
   ng,gl,gs,_=cv2.connectedComponentsWithStats(grown,8)
   sp,sruns=provisional(seed);gp,gruns=provisional(grown)
   ties=0;reused=0;used=set();fallbacks=0
   for label in sorted(range(1,ns),key=lambda k:-int(ss[k,4]))[:16]:
    ids,counts=np.unique(gl[sl==label],return_counts=True)
    overlap=[(int(c),int(k)) for k,c in zip(ids,counts) if k]
    if overlap:
     maximum,gid=max(overlap)
     ties+=sum(c==maximum for c,k in overlap)>1
     x,y,w,h,area=map(int,gs[gid])
     if x>1 and x+w<159 and area<=2500:
      if gid in used:reused+=1
      used.add(gid)
     else:fallbacks+=1
    else:fallbacks+=1
   # Default OpenCV 8-connectivity numbers components by first 2x2 block,
   # not necessarily by first raster pixel. Verify rather than assume it.
   order=[]
   for label in range(1,ng):
    order.append(int(np.flatnonzero(gl==label)[0]))
   block_order_mismatch=0
   for label_map,nlabels in ((sl,ns),(gl,ng)):
    keys=[]
    for label in range(1,nlabels):
     yy,xx=np.nonzero(label_map==label);keys.append(int(((yy//2)*80+xx//2).min()))
    block_order_mismatch+=keys!=sorted(keys)
   records.append(dict(dataset=dataset,frame=frame,seed_final=ns-1,grown_final=ng-1,
    seed_provisional=sp,grown_provisional=gp,seed_max_row_runs=sruns,grown_max_row_runs=gruns,
    overlap_ties=ties,reused_grown=reused,seed_fallbacks=fallbacks,
    grown_label_order_not_raster=order!=sorted(order),block_order_mismatch=block_order_mismatch,
    seed_pixel_allocations=pixel_allocations(seed),grown_pixel_allocations=pixel_allocations(grown)))
 keys=('seed_final','grown_final','seed_provisional','grown_provisional','seed_max_row_runs','grown_max_row_runs','seed_pixel_allocations','grown_pixel_allocations')
 summary={k:max(records,key=lambda v:v[k]) for k in keys}
 totals={k:sum(v[k] for v in records) for k in ('overlap_ties','reused_grown','seed_fallbacks','grown_label_order_not_raster','block_order_mismatch')}
 for source in ('host/hand_fpga_grid_model.py','host/tests/audit_hand_association_capacity.py'):
  hashes[source]=hashlib.sha256((ROOT/source).read_bytes()).hexdigest()
 hashes['host/tests/test_hand_label_map.py']=hashlib.sha256((ROOT/'host/tests/test_hand_label_map.py').read_bytes()).hexdigest()
 result=dict(status='SOFTWARE_ASSOCIATION_CAPACITY_AUDIT_NOT_RTL_SIGNOFF',opencv_version=cv2.__version__,frames=len(records),maxima=summary,totals=totals,hashes=hashes,records=records)
 a.out.write_text(json.dumps(result,indent=2))
 print(json.dumps(dict(frames=len(records),maxima={k:{q:v[q] for q in ('dataset','frame',k)} for k,v in summary.items()},totals=totals),indent=2))
if __name__=='__main__':main()
