"""Two-cut widths and exact post-width rules; no temporal gesture labels."""
import argparse,hashlib,json,random,subprocess,sys
from pathlib import Path
import cv2
import numpy as np
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'host'))
from hand_fixed_classifier import width_checks,integer_hull,contour_points
from test_hand_tip_candidates import ref as candidates_reference
from test_hand_blob_scan import unpack
from test_hand_palm_distance import reference
from test_hand_wrist_median import expected as wrist_reference
from test_hand_defect_scan import expected_edges
SOURCES=['host/tests/tb_hand_tip_filter.sv']+['rtl/user/'+s for s in (
 'ua_hand_tip_filter.v','ua_hand_tip_width.v','ua_hand_integer_math.v','ua_hand_product_serial.v')]
def ref(mask,cx,cy,r,wrist,tips):
 if 0<len(tips)<3:checks,tips=width_checks(mask,2*cx,2*cy,r,wrist,tips)
 else:checks=[]
 def values(p):
  dx,dy=2*(p[0]-cx),2*(p[1]-cy);return dx*dx+dy*dy,dx*wrist[0]+dy*wrist[1]
 w2=sum(v*v for v in wrist)
 if len(tips)==2:
  a,b=sorted(tips,key=lambda p:-values(p)[0]);la,da=values(a);lb,db=values(b)
  complete=all(c['widths'][0] is not None and c['widths'][1] is not None for c in checks if tuple(c['point'])==a)
  if complete and 16*la>=25*lb and da<0 and da*da*100>=81*la*w2 and (db>=0 or db*db*400<289*lb*w2):tips=[a]
 if len(tips)==1:
  d2,dot=values(tips[0])
  if dot>=0 or dot*dot*25<16*d2*w2:tips=[]
 return 3 if len(tips)>=3 else 2 if len(tips)==1 else 1 if not tips else 0,len(tips)
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--parallel',type=int,choices=(0,1),default=0);a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve();frozen={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}
 cases=[];rng=random.Random(418105);np_rng=np.random.default_rng(418105)
 def add(m,cx,cy,r,wrist,tips,abort=0):cases.append((m,cx,cy,r,wrist,tips,ref(m,cx,cy,r,wrist,tips),abort))
 for folder in ('vectors_new','vectors_old'):
  for filename in sorted((ROOT/'tmp/hand_rtl'/folder).glob('frame_*.hex')):
   for mask in unpack([int(s,16) for s in filename.read_text().split()]):
    n,labels,stats,_=cv2.connectedComponentsWithStats(mask.astype(np.uint8),8)
    if n<=1:continue
    k=1+int(stats[1:,4].argmax());x,y,w,h,_=stats[k];m=(labels[y:y+h,x:x+w]==k).astype(np.uint8)
    _,cx,cy,r=reference(m);wx,wy,_=wrist_reference(m,cx,cy,r);points=contour_points(m);hull=integer_hull(points)
    edges=[(*e[:4],e[4]) for e in expected_edges(hull,points,r)];wrist=(wx-2*cx,wy-2*cy)
    tips=candidates_reference(hull,edges,cx,cy,r,wrist);add(m,cx,cy,r,wrist,tips)
 for i in range(180):
  w=rng.randrange(12,161);h=rng.randrange(12,91);cx=rng.randrange(w);cy=rng.randrange(h)
  m=(np_rng.random((h,w))<rng.choice((0,.1,.5,.9,1))).astype(np.uint8)
  tips=[(rng.randrange(w),rng.randrange(h)) for _ in range(rng.choice((0,1,1,2,2,3,7)))]
  tips.sort(key=lambda p:-((p[0]-cx)**2+(p[1]-cy)**2))
  add(m,cx,cy,rng.choice((0,15,16,80,160,511,2047)),(rng.randrange(-318,319),rng.randrange(-178,179)),tips)
 # Thin axial fingers, oblique rejection, thumb branch, complete/missing cuts.
 for offset in (0,8,18,30):
  for finger_width in (1,3,5,9,17,25):
   m=np.zeros((90,100),np.uint8);cv2.rectangle(m,(35,45),(65,89),1,-1)
   cv2.line(m,(50,55),(50+offset,5),1,finger_width)
   add(m,50,55,160,(0,45),[(50+offset,5)])
   cv2.line(m,(50,55),(80,35),1,3);add(m,50,55,160,(0,45),[(50+offset,5),(80,35)])
 m=np.ones((90,100),np.uint8);add(m,50,55,160,(0,45),[(50,5)],abort=1)
 vector=out/'cases.txt';lines=[]
 for m,cx,cy,r,wrist,tips,expected,abort in cases:
  lines.append(' '.join(map(str,(m.shape[1],m.shape[0],cx,cy,r,*wrist,len(tips),*expected,abort))))
  lines.append(' '.join(map(str,m.flat)));lines.extend(f'{x} {y}' for x,y in tips)
 vector.write_text('\n'.join(lines)+'\n');exe=out/'filter.vvp'
 z=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s','tb_hand_tip_filter',f'-Ptb_hand_tip_filter.PARALLEL_COMPARE={a.parallel}','-o',str(exe)]+SOURCES,cwd=ROOT,capture_output=True,text=True)
 (out/'compile.log').write_text(z.stdout+z.stderr)
 if z.returncode:raise RuntimeError(z.stderr)
 z=subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe),f'+INPUT={vector}'],cwd=ROOT,capture_output=True,text=True,timeout=120)
 (out/'sim.log').write_text(z.stdout+z.stderr)
 if z.returncode or 'HAND_TIP_FILTER_PASS' not in z.stdout:raise AssertionError(z.stdout+z.stderr)
 if frozen!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}:raise RuntimeError('source changed')
 (out/'result.json').write_text(json.dumps(dict(status='TIP_FILTER_PASS_NOT_FULL_CLASSIFIER_SIGNOFF',parallel_compare=a.parallel,tests=len(cases),hashes=frozen),indent=2));print(z.stdout)
if __name__=='__main__':main()
