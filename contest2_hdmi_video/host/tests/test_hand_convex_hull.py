"""Exact all-foreground-point monotone-chain reference versus RTL column hull."""
import argparse,hashlib,json,subprocess,sys
from pathlib import Path
import cv2
import numpy as np
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'host'))
from hand_fixed_classifier import integer_hull
from test_hand_blob_scan import unpack
SOURCES=['host/tests/tb_hand_convex_hull.sv','rtl/user/ua_hand_convex_hull.v','rtl/user/ua_hand_scratch_ram.v']
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--external',type=int,choices=(0,1),default=0);a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve();frozen={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}
 exe=out/'hull.vvp';r=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s','tb_hand_convex_hull','-Ptb_hand_convex_hull.EXTERNAL='+str(a.external),'-o',str(exe)]+SOURCES,cwd=ROOT,capture_output=True,text=True)
 (out/'compile.log').write_text(r.stdout+r.stderr)
 if r.returncode:raise RuntimeError(r.stderr)
 cases=[];rng=np.random.default_rng(418037)
 for h,w in [(1,1),(1,160),(90,1),(90,160),(89,159),(3,7)]:
  cases.extend([np.zeros((h,w),np.uint8),np.ones((h,w),np.uint8)])
 for i in range(70):
  h=int(rng.integers(5,91));w=int(rng.integers(5,161));m=np.zeros((h,w),np.uint8)
  if i%3==0:m=(rng.random((h,w))<rng.uniform(.02,.7)).astype(np.uint8)
  elif i%3==1:
   for j in range(5):cv2.ellipse(m,(int(rng.integers(w)),int(rng.integers(h))),(int(rng.integers(1,max(w//3,2))),int(rng.integers(1,max(h//3,2)))),int(rng.integers(180)),0,360,1,-1)
  else:
   yy,xx=np.indices((h,w));m=((xx-2*yy)%17<2).astype(np.uint8)
  cases.append(m)
 for folder in ('vectors_new','vectors_old'):
  for path in sorted((ROOT/'tmp/hand_rtl'/folder).glob('frame_*.hex')):
   _,m=unpack([int(s,16) for s in path.read_text().split()]);n,labels,stats,_=cv2.connectedComponentsWithStats(m,8)
   if n>1:
    label=1+int(stats[1:,4].argmax());x,y,w,h,_=stats[label];cases.append((labels[y:y+h,x:x+w]==label).astype(np.uint8))
 records=[]
 for i,m in enumerate(cases):
  path=out/f'mask_{i}.bin';path.write_text('\n'.join(map(str,m.flat))+'\n');h,w=m.shape
  yy,xx=np.nonzero(m);hull=integer_hull([(int(x),int(y)) for x,y in zip(xx,yy)])
  ep=out/f'hull_{i}.hex';ep.write_text('\n'.join(f'{y*256+x:04x}' for x,y in hull)+'\n')
  cmd=['C:/iverilog/bin/vvp.exe',str(exe),f'+INPUT={path}',f'+EXPECTED={ep}',f'+W={w}',f'+H={h}',f'+COUNT={len(hull)}']
  modes=[[]]
  if i==7:modes.extend([['+ABORT=1'],['+ABORT=2'],['+ABORT=3'],['+FAULT=1'],['+FAULT=2']])
  for mode in modes:
   r=subprocess.run(cmd+mode,cwd=ROOT,capture_output=True,text=True,timeout=20);(out/f'case_{i}_{len(records)}.log').write_text(r.stdout+r.stderr)
   if r.returncode or 'HAND_CONVEX_HULL_PASS' not in r.stdout:raise AssertionError(f'case {i} {mode}: '+r.stdout+r.stderr)
   records.append(dict(case=i,shape=[w,h],vertices=len(hull),mode=mode))
 if frozen!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}:raise RuntimeError('changed tested sources')
 (out/'result.json').write_text(json.dumps(dict(status='HAND_CONVEX_HULL_RTL_PASS_NOT_INTEGRATED',tests=len(records),hashes=frozen,records=records),indent=2))
 print(f'HAND_CONVEX_HULL_RTL_PASS tests={len(records)}')
if __name__=='__main__':main()
