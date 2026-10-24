"""Exact fingertip gates/fallback/ranking/dedup BEFORE width/axial filtering."""
import argparse,hashlib,json,math,random,subprocess,sys
from pathlib import Path
import cv2
import numpy as np
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'host'))
from hand_fixed_classifier import integer_hull,contour_points
from test_hand_blob_scan import unpack
from test_hand_palm_distance import reference
from test_hand_wrist_median import expected as wrist_reference
from test_hand_defect_scan import expected_edges
SOURCES=['host/tests/tb_hand_tip_candidates.sv']+['rtl/user/'+s for s in (
 'ua_hand_tip_candidates.v','ua_hand_integer_math.v','ua_hand_scratch_ram.v')]
def ref(hull,edges,cx,cy,r,wrist):
 length=math.isqrt(sum(v*v for v in wrist));vertices=[]
 def values(p):
  dx,dy=2*(p[0]-cx),2*(p[1]-cy);return dx*dx+dy*dy,dx*wrist[0]+dy*wrist[1]
 def add(p):
  d2,dot=values(p)
  if 64*d2>=4*r*r and dot<0 and -16*dot>r*length:vertices.append((d2,p))
 for ax,ay,bx,by,q in edges:
  if q:add((ax,ay));add((bx,by))
 if not vertices:
  upper=[(values(p)[0],p) for p in hull if values(p)[1]*80<r*length]
  if upper:
   d2,p=max(upper)
   if 100*d2>=9*r*r:add(p)
 tips=[]
 for _,p in sorted(vertices,key=lambda z:(-z[0],z[1])):
  if all(25600*(4*(p[0]-q[0])**2+4*(p[1]-q[1])**2)>169*r*r for q in tips):tips.append(p)
 return tips[:7]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--external',type=int,choices=(0,1),default=1);a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve();frozen={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}
 rng=random.Random(418098);cases=[]
 def add(hull,edges,cx,cy,r,wrist,abort=0):cases.append((hull,edges,cx,cy,r,wrist,ref(hull,edges,cx,cy,r,wrist),abort))
 for folder in ('vectors_new','vectors_old'):
  for filename in sorted((ROOT/'tmp/hand_rtl'/folder).glob('frame_*.hex')):
   for mask in unpack([int(s,16) for s in filename.read_text().split()]):
    n,labels,stats,_=cv2.connectedComponentsWithStats(mask.astype(np.uint8),8)
    if n<=1:continue
    k=1+int(stats[1:,4].argmax());x,y,w,h,_=stats[k];m=(labels[y:y+h,x:x+w]==k).astype(np.uint8)
    _,cx,cy,r=reference(m);wx,wy,_=wrist_reference(m,cx,cy,r);points=contour_points(m);hull=integer_hull(points)
    edges=[(*e[:4],e[4]) for e in expected_edges(hull,points,r)]
    add(hull,edges,cx,cy,r,(wx-2*cx,wy-2*cy))
 for i in range(220):
  cx=rng.randrange(160);cy=rng.randrange(90);r=rng.choice((0,15,16,79,80,160,511,1023,2047))
  wrist=(rng.randrange(-318,319),rng.randrange(-178,179));hull=[(rng.randrange(160),rng.randrange(90)) for _ in range(rng.randrange(25))]
  edges=[(rng.randrange(160),rng.randrange(90),rng.randrange(160),rng.randrange(90),rng.randrange(2)) for _ in range(rng.randrange(30))]
  add(hull,edges,cx,cy,r,wrist)
 # Duplicates, equal-distance lexicographic sort, opposite fallback tie rule,
 # seven-tip saturation, zero wrist and deterministic restart while sorting.
 hull=[(x,0) for x in range(0,160,8)]
 edges=[(*p,*p,1) for p in hull]
 for radius in (0,80,160,511,2047):
  add(hull,edges,80,80,radius,(0,20));add(hull,[],80,80,radius,(0,20))
 add(hull,edges,80,80,80,(0,0))
 add(hull,edges,80,80,80,(0,20),abort=15)
 add(hull,edges,80,80,80,(0,20),abort=22)
 vector=out/'cases.txt';lines=[]
 for hull,edges,cx,cy,r,wrist,tips,abort in cases:
  lines.append(' '.join(map(str,(cx,cy,r,*wrist,len(hull),len(edges),len(tips),abort))))
  lines.extend(f'{x} {y}' for x,y in hull);lines.extend(' '.join(map(str,e)) for e in edges);lines.extend(f'{x} {y}' for x,y in tips)
 vector.write_text('\n'.join(lines)+'\n');exe=out/'tips.vvp'
 z=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s','tb_hand_tip_candidates',f'-Ptb_hand_tip_candidates.EXTERNAL={a.external}','-o',str(exe)]+SOURCES,cwd=ROOT,capture_output=True,text=True)
 (out/'compile.log').write_text(z.stdout+z.stderr)
 if z.returncode:raise RuntimeError(z.stderr)
 z=subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe),f'+INPUT={vector}'],cwd=ROOT,capture_output=True,text=True,timeout=120)
 (out/'sim.log').write_text(z.stdout+z.stderr)
 if z.returncode or 'HAND_TIP_CANDIDATES_PASS' not in z.stdout:raise AssertionError(z.stdout+z.stderr)
 if frozen!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}:raise RuntimeError('source changed')
 (out/'result.json').write_text(json.dumps(dict(status='TIP_CANDIDATES_PASS_NOT_WIDTH_CLASSIFIER_SIGNOFF',tests=len(cases),external_memory=a.external,hashes=frozen),indent=2));print(z.stdout)
if __name__=='__main__':main()
