"""Independent numpy median versus native-grid wrist RTL, not a gesture signoff."""
import argparse, hashlib, json, subprocess, sys
from pathlib import Path
import cv2
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'host'))
from test_hand_blob_scan import unpack
from test_hand_palm_distance import reference
SOURCES=['host/tests/tb_hand_wrist_median.sv','rtl/user/ua_hand_wrist_median.v']
def expected(mask,cx,cy,r):
 yy,xx=np.nonzero(mask)
 keep=(160*yy>=160*cy+3*r)&(5*yy>=4*mask.shape[0])
 xx=xx[keep];yy=yy[keep]
 if len(xx):return int(2*np.median(xx)),int(2*np.median(yy)),len(xx)
 return 2*cx,2*(cy+r//16),0
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve();frozen={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}
 exe=out/'wrist.vvp';r=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s','tb_hand_wrist_median','-o',str(exe)]+SOURCES,cwd=ROOT,capture_output=True,text=True)
 (out/'compile.log').write_text(r.stdout+r.stderr)
 if r.returncode:raise RuntimeError(r.stderr)
 rng=np.random.default_rng(418029);cases=[]
 for h,w in [(1,1),(3,7),(90,160),(89,159),(47,1),(1,19)]:
  for filled in (0,1):
   m=np.full((h,w),filled,np.uint8)
   for cx,cy,radius in [(0,0,0),(w-1,h-1,2047),(w//2,h//3,80)]:cases.append((m,cx,cy,radius))
 for _ in range(64):
  h=int(rng.integers(5,91));w=int(rng.integers(5,161));m=(rng.random((h,w))<rng.uniform(.1,.9)).astype(np.uint8)
  cases.append((m,int(rng.integers(w)),int(rng.integers(h)),int(rng.integers(2048))))
 for folder in ('vectors_new','vectors_old'):
  for path in sorted((ROOT/'tmp/hand_rtl'/folder).glob('frame_*.hex')):
   _,mask=unpack([int(s,16) for s in path.read_text().split()]);count,labels,stats,_=cv2.connectedComponentsWithStats(mask,8)
   if count<=1:continue
   label=1+int(stats[1:,4].argmax());x,y,w,h,_=stats[label];m=(labels[y:y+h,x:x+w]==label).astype(np.uint8)
   _,cx,cy,radius=reference(m);cases.append((m,cx,cy,radius))
 records=[]
 for i,(m,cx,cy,radius) in enumerate(cases):
  path=out/f'mask_{i}.bin';path.write_text('\n'.join(map(str,m.flat))+'\n');h,w=m.shape
  ex,ey,n=expected(m,cx,cy,radius)
  cmd=['C:/iverilog/bin/vvp.exe',str(exe),f'+INPUT={path}',f'+W={w}',f'+H={h}',f'+CX={cx}',f'+CY={cy}',f'+R={radius}',f'+EX={ex}',f'+EY={ey}',f'+COUNT={n}']
  modes=[[]]
  if i==0:modes.append(['+ABORT=1'])
  if i==6:modes.extend([['+FAULT=1'],['+FAULT=2']])
  if n>0 and w>8 and h>8 and not any(r.get('abort')==3 for r in records):modes.extend([['+ABORT=2'],['+ABORT=3']])
  for mode in modes:
   r=subprocess.run(cmd+mode,cwd=ROOT,capture_output=True,text=True,timeout=15);(out/f'case_{i}_{len(records)}.log').write_text(r.stdout+r.stderr)
   marker='WRIST_EXPECTED_FAULT_PASS' if mode and 'FAULT' in mode[0] else 'WRIST_MEDIAN_PASS'
   if r.returncode or marker not in r.stdout:raise AssertionError(f'case {i} mode {mode}: '+r.stdout+r.stderr)
   records.append(dict(case=i,shape=[w,h],count=n,mode=mode,abort=int(mode[0].split('=')[1]) if mode and 'ABORT' in mode[0] else 0))
 if frozen!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}:raise RuntimeError('changed sources')
 (out/'result.json').write_text(json.dumps(dict(status='WRIST_MEDIAN_RTL_PASS_NOT_INTEGRATED',tests=len(records),hashes=frozen,records=records),indent=2))
 print(f'WRIST_MEDIAN_RTL_PASS tests={len(records)}')
if __name__=='__main__':main()
