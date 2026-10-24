"""Independent per-edge integer cross/depth/angle reference, real and synthetic contours."""
import argparse,hashlib,json,math,random,subprocess,sys
from pathlib import Path
import cv2
import numpy as np
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'host'))
from hand_fixed_classifier import integer_hull,contour_points
from test_hand_blob_scan import unpack
from test_hand_palm_distance import reference
SOURCES=['host/tests/tb_hand_defect_edge.sv','rtl/user/ua_hand_defect_edge.v','rtl/user/ua_hand_integer_math.v']
def edge_reference(a,b,path,radius):
 dx,dy=2*(b[0]-a[0]),2*(b[1]-a[1]);length=math.isqrt(dx*dx+dy*dy)
 far=None;maximum=0
 for x,y in path:
  cross=abs(dx*(2*y-2*a[1])-dy*(2*x-2*a[0]))
  if cross>maximum:maximum=cross;far=(x,y)
 qualified=False
 if far is not None and length and 160*maximum>=13*radius*length:
  fa=(2*(a[0]-far[0]),2*(a[1]-far[1]));fb=(2*(b[0]-far[0]),2*(b[1]-far[1]))
  qualified=fa[0]*fb[0]+fa[1]*fb[1]>0
 return int(qualified),int(far is not None),*(far or (0,0)),maximum,length
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve();frozen={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}
 cases=[]
 def add(a,b,path,r,invalid=0,abort=0):cases.append((a,b,path,r,invalid,abort))
 # Degenerate, both signs, exact-angle and threshold boundaries, equal maxima.
 for aa,bb,path in [((0,0),(0,0),[]),((0,0),(159,89),[]),((20,5),(60,5),[(30,45),(50,45)]),
                    ((60,5),(20,5),[(50,45),(30,45)]),((1,1),(21,1),[(11,11)]),((0,89),(159,0),[(0,0),(159,89)])]:
  for radius in (0,1,15,16,80,159,160,161,500,2047):add(aa,bb,path,radius)
 rng=random.Random(418057)
 for i in range(600):
  aa=(rng.randrange(160),rng.randrange(90));bb=(rng.randrange(160),rng.randrange(90));path=[(rng.randrange(160),rng.randrange(90)) for _ in range(rng.randrange(101))]
  add(aa,bb,path,rng.randrange(2048),abort=(1+(i%3)) if i%19==0 and path else 0)
 for folder in ('vectors_new','vectors_old'):
  for filename in sorted((ROOT/'tmp/hand_rtl'/folder).glob('frame_*.hex')):
   _,m=unpack([int(s,16) for s in filename.read_text().split()]);n,labels,stats,_=cv2.connectedComponentsWithStats(m.astype(np.uint8),8)
   if n<=1:continue
   k=1+int(stats[1:,4].argmax());x,y,w,h,_=stats[k];selected=(labels[y:y+h,x:x+w]==k).astype(np.uint8)
   _,_,_,radius=reference(selected);points=contour_points(selected);indices={p:i for i,p in enumerate(points)}
   hull=sorted(integer_hull(points),key=lambda p:indices[p])
   if len(hull)<2:continue
   for j,aa in enumerate(hull):
    bb=hull[(j+1)%len(hull)];path=[];i=(indices[aa]+1)%len(points)
    while i!=indices[bb]:path.append(points[i]);i=(i+1)%len(points)
    add(aa,bb,path,radius)
 add((160,0),(10,10),[],80,invalid=1)
 add((0,0),(159,89),[(255,0)],80,invalid=2)
 vectors=out/'edges.txt';lines=[]
 for aa,bb,path,r,invalid,abort in cases:
  expected=edge_reference(aa,bb,path,r)
  lines.append(' '.join(map(str,(*aa,*bb,r,len(path),*expected,invalid,abort))))
  lines.extend(f'{x} {y}' for x,y in path)
 vectors.write_text('\n'.join(lines)+'\n')
 exe=out/'edge.vvp';r=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s','tb_hand_defect_edge','-o',str(exe)]+SOURCES,cwd=ROOT,capture_output=True,text=True)
 (out/'compile.log').write_text(r.stdout+r.stderr)
 if r.returncode:raise RuntimeError(r.stderr)
 r=subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe),f'+INPUT={vectors}'],cwd=ROOT,capture_output=True,text=True,timeout=120)
 (out/'sim.log').write_text(r.stdout+r.stderr)
 if r.returncode or 'HAND_DEFECT_EDGE_PASS' not in r.stdout:raise AssertionError(r.stdout+r.stderr)
 if frozen!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}:raise RuntimeError('changed tested source')
 (out/'result.json').write_text(json.dumps(dict(status='DEFECT_EDGE_RTL_PASS_NOT_CLASSIFIER_SIGNOFF',tests=len(cases),qualified=sum(edge_reference(aa,bb,path,r)[0] for aa,bb,path,r,invalid,abort in cases if not invalid),hashes=frozen),indent=2));print(r.stdout)
if __name__=='__main__':main()
