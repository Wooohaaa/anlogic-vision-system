"""Every CCL component's exact native red sum, including union/retire/reuse."""
from collections import Counter
import argparse,hashlib,json,subprocess
from pathlib import Path
import cv2
import numpy as np
from test_hand_blob_scan import ROOT,pack,unpack,synthetic,capacity_overflow
SOURCES=['host/tests/tb_hand_blob_rgb.sv','rtl/user/ua_hand_blob_scan.v']
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--random-cases',type=int,default=60);a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve();hashes={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES+[str(Path(__file__).relative_to(ROOT))]}
 exe=out/'rgb.vvp';z=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s','tb_hand_blob_rgb','-o',str(exe)]+SOURCES,cwd=ROOT,capture_output=True,text=True);(out/'compile.log').write_text(z.stdout+z.stderr)
 if z.returncode:raise RuntimeError(z.stderr)
 records=[];rng=np.random.default_rng(418123)
 def run(name,seed,grown,red):
  mp=out/(name+'_mask.hex');rp=out/(name+'_red.hex')
  mp.write_text(''.join(f'{v:05x}\n' for v in pack(seed,grown)));rp.write_text(''.join(f'{v:03x}\n' for v in red.flat))
  z=subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe),f'+MASK={mp}',f'+RED={rp}',f'+CLEAR={int(bool(seed.any()))}'],cwd=ROOT,capture_output=True,text=True,timeout=60)
  (out/(name+'.log')).write_text(z.stdout+z.stderr)
  if z.returncode or 'HAND_BLOB_RGB_PASS' not in z.stdout:raise AssertionError(name+': '+z.stdout+z.stderr)
  actual=[Counter(),Counter()];done={}
  for line in z.stdout.splitlines():
   f=line.split()
   if f[0]=='BLOB':actual[int(f[1])][tuple(map(int,f[2:]))]+=1
   if f[0]=='DONE':done[int(f[1])]=tuple(map(int,f[2:]))
  for mode,mask in enumerate((seed,grown)):
   overflow=capacity_overflow(mask);assert done[mode][0]==overflow,(name,mode,'overflow')
   if not overflow:
    expected=Counter();n,labels,stats,_=cv2.connectedComponentsWithStats(mask.astype(np.uint8),8)
    for k in range(1,n):
     x,y,w,h,area=map(int,stats[k]);region=labels==k;anchor=int(np.flatnonzero(region[y])[0])
     expected[(area,int(seed[region].sum()),x,x+w-1,y,y+h-1,anchor,y,int(red[region].sum()))]+=1
    assert actual[mode]==expected,(name,mode,'missing',expected-actual[mode],'extra',actual[mode]-expected)
    assert done[mode][1]==int(mask.sum()),(name,mode,'red reads')
   records.append(dict(name=name,mode=mode,overflow=overflow,components=sum(actual[mode].values()),red_reads=done[mode][1]))
 for name,s,g in synthetic(a.random_cases):run(name,s,g,rng.integers(0,1024,(90,160),dtype=np.uint16))
 full=np.ones((90,160),np.uint8)
 for r in (0,1,96,160,1023):run(f'full_r{r}',full,full,np.full((90,160),r,np.uint16))
 for folder in ('vectors_new','vectors_old'):
  for path in sorted((ROOT/'tmp/hand_rtl'/folder).glob('frame_*.hex')):
   seed,grown=unpack([int(s,16) for s in path.read_text().split()]);run(folder+'_'+path.stem,seed,grown,rng.integers(0,1024,(90,160),dtype=np.uint16))
 if hashes!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in hashes}:raise RuntimeError('source changed')
 (out/'result.json').write_text(json.dumps(dict(status='CCL_RED_SUM_PASS_NOT_FULL_CLASSIFIER_SIGNOFF',tests=len(records),hashes=hashes,records=records),indent=2));print(f'CCL_RED_SUM_PASS tests={len(records)}')
if __name__=='__main__':main()
