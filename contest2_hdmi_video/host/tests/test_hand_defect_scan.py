"""Hull+ordered contour integration; exact last-occurrence and wrap behavior."""
import argparse,hashlib,json,random,subprocess,sys
from pathlib import Path
import cv2
import numpy as np
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'host'))
from hand_fixed_classifier import integer_hull,contour_points
from test_hand_blob_scan import unpack
from test_hand_palm_distance import reference
from test_hand_defect_edge import edge_reference
SOURCES=['host/tests/tb_hand_defect_scan.sv']+['rtl/user/'+s for s in (
 'ua_hand_defect_scan.v','ua_hand_defect_edge.v','ua_hand_integer_math.v','ua_hand_scratch_ram.v')]

def expected_edges(hull,points,r):
 if len(points)<3:return []
 indices={p:i for i,p in enumerate(points)}
 ordered=sorted(hull,key=lambda p:indices[p]);edges=[]
 for j,a in enumerate(ordered):
  b=ordered[(j+1)%len(ordered)];path=[];k=(indices[a]+1)%len(points)
  while k!=indices[b]:path.append(points[k]);k=(k+1)%len(points)
  edges.append((*a,*b,*edge_reference(a,b,path,r)))
 return edges

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--external',type=int,choices=(0,1),default=1);a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve();frozen={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}
 cases=[];rng=random.Random(418092)
 def add(hull,points,r,invalid=0,abort=0):
  hull=list(hull);rng.shuffle(hull)
  cases.append((hull,points,r,[] if invalid else expected_edges(hull,points,r),invalid,abort))
 masks=[]
 for count in range(1,6):
  m=np.zeros((90,160),np.uint8);cv2.rectangle(m,(50,44),(104,75),1,-1);cv2.rectangle(m,(69,70),(88,89),1,-1)
  for x in range(count):cv2.rectangle(m,(50+x*11,10+(x%3)*6),(55+x*11,49),1,-1)
  masks.append(m)
 m=np.zeros((90,160),np.uint8);cv2.rectangle(m,(10,10),(35,35),1,-1);cv2.rectangle(m,(36,36),(65,65),1,-1);masks.append(m)
 m=np.zeros((90,160),np.uint8);cv2.rectangle(m,(2,2),(30,30),1,2);masks.append(m)
 for folder in ('vectors_new','vectors_old'):
  for filename in sorted((ROOT/'tmp/hand_rtl'/folder).glob('frame_*.hex')):
   for mask in unpack([int(s,16) for s in filename.read_text().split()]):
    n,labels,stats,_=cv2.connectedComponentsWithStats(mask.astype(np.uint8),8)
    if n<=1:continue
    k=1+int(stats[1:,4].argmax());x,y,w,h,_=stats[k];masks.append((labels[y:y+h,x:x+w]==k).astype(np.uint8))
 for m in masks:
  points=contour_points(m);hull=integer_hull(points);_,_,_,r=reference(m)
  add(hull,points,r)
  # Rotation of contour start changes sorted hull start and wrap segment.
  if len(points)>8:
   cut=rng.randrange(1,len(points));rotated=points[cut:]+points[:cut];add(hull,rotated,r)
 # Explicit duplicate articulation coordinates: last occurrence must win.
 path=[(5,5),(5,6),(6,7),(5,6),(5,5),(6,5),(7,5),(7,6),(7,7),(6,7),(5,7),(5,6)]
 add(integer_hull(path),path,16)
 for points in ([],[(0,0)],[(0,0),(1,1)]):add(integer_hull(points),points,80)
 for stage in (5,9,15,18,19):
  m=masks[4];pts=contour_points(m);add(integer_hull(pts),pts,80,abort=stage)
 add([(1,1),(3,3)],[(1,1),(2,2),(2,3)],80,invalid=1)
 add([],[(1,1),(2,2),(2,3)],80,invalid=1)
 # Zero-depth full-length contour exercises the 8192-entry address boundary.
 long_path=[(0,0),(1,0),(1,1),(0,1)]*2048;add(integer_hull(long_path),long_path,80)
 vector=out/'cases.txt';lines=[]
 for hull,points,r,edges,invalid,abort in cases:
  lines.append(f'{len(hull)} {len(points)} {r} {len(edges)} {invalid} {abort}')
  lines.extend(f'{x} {y}' for x,y in hull);lines.extend(f'{x} {y}' for x,y in points)
  lines.extend(' '.join(map(str,e)) for e in edges)
 vector.write_text('\n'.join(lines)+'\n')
 exe=out/'scan.vvp';z=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s','tb_hand_defect_scan',f'-Ptb_hand_defect_scan.EXTERNAL={a.external}','-o',str(exe)]+SOURCES,cwd=ROOT,capture_output=True,text=True)
 (out/'compile.log').write_text(z.stdout+z.stderr)
 if z.returncode:raise RuntimeError(z.stderr)
 z=subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe),f'+INPUT={vector}'],cwd=ROOT,capture_output=True,text=True,timeout=240)
 (out/'sim.log').write_text(z.stdout+z.stderr)
 if z.returncode or 'HAND_DEFECT_SCAN_PASS' not in z.stdout:raise AssertionError(z.stdout+z.stderr)
 if frozen!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}:raise RuntimeError('source changed')
 result=dict(status='ORDERED_DEFECT_CHAIN_PASS_NOT_CLASSIFIER_SIGNOFF',tests=len(cases),external_memory=a.external,
             edges=sum(len(c[3]) for c in cases),hashes=frozen)
 (out/'result.json').write_text(json.dumps(result,indent=2));print(z.stdout)
if __name__=='__main__':main()
