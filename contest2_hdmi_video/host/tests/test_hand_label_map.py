"""Real RTL seed/grown persistent label maps vs independent OpenCV regions.

No geometry or hand IDs injected. Checks all pixels, background, distinct
regions, seed preservation during grown, stalls, clear, and explicit overflow.
"""
import argparse,hashlib,json,subprocess
from pathlib import Path
import cv2
import numpy as np
from test_hand_blob_scan import ROOT,pack,unpack
SOURCES=['host/tests/tb_hand_label_map.sv','rtl/user/ua_hand_label_map.v']

def pixel_allocations(mask):
 m=mask.astype(bool);left=np.zeros_like(m);left[:,1:]=m[:,:-1]
 up=np.zeros_like(m);up[1:]=m[:-1]
 neighbors=up.copy();neighbors[:,1:]|=up[:,:-1];neighbors[:,:-1]|=up[:,1:]
 return int((m & ~left & ~neighbors).sum())

def verify(actual,mask):
 n,labels,_,_=cv2.connectedComponentsWithStats(mask.astype(np.uint8),8)
 if np.any(actual[mask==0]):raise AssertionError('nonzero background')
 roots=[]
 for label in range(1,n):
  values=np.unique(actual[labels==label])
  if len(values)!=1 or values[0]==0:raise AssertionError(('split/zero region',label,values))
  roots.append(int(values[0]))
 if len(set(roots))!=len(roots):raise AssertionError('different components aliased')

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--random-cases',type=int,default=20);a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve();hashes={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}
 exe=out/'labels.vvp';z=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s','tb_hand_label_map','-o',str(exe)]+SOURCES,cwd=ROOT,capture_output=True,text=True)
 (out/'compile.log').write_text(z.stdout+z.stderr)
 if z.returncode:raise RuntimeError(z.stderr)
 scenes=[]
 for folder in ('vectors_new','vectors_old'):
  for path in sorted((ROOT/'tmp/hand_rtl'/folder).glob('frame_*.hex')):
   scenes.append((folder+'_'+path.stem,*unpack([int(v,16) for v in path.read_text().split()])))
 empty=np.zeros((90,160),np.uint8);full=np.ones_like(empty)
 scenes.extend([('empty',empty,empty),('full',full,full)])
 diag=np.zeros_like(empty);np.fill_diagonal(diag[:90,:90],1);scenes.append(('diagonal',diag,diag))
 split=np.zeros_like(empty);split[::3,::3]=1;scenes.append(('overflow',split,split))
 bridge=empty.copy();bridge[2:30,2:5]=1;bridge[2:30,12:15]=1;bridge[29,2:15]=1;scenes.append(('late_union',bridge,bridge))
 rng=np.random.default_rng(181019)
 for i in range(a.random_cases):
  m=empty.copy()
  for _ in range(14):
   x,y=map(int,rng.integers([0,0],[160,90]));cv2.rectangle(m,(x,y),(min(159,x+int(rng.integers(1,15))),min(89,y+int(rng.integers(1,18)))),1,-1)
  scenes.append((f'random{i}',m,cv2.dilate(m,np.ones((3,3),np.uint8))))
 records=[]
 for name,seed,grown in scenes:
  mp=out/(name+'.hex');mp.write_text(''.join(f'{word:05x}\n' for word in pack(seed,grown)))
  overflow=max(pixel_allocations(seed),pixel_allocations(grown))>=128
  for abort in ([0,1,2,3] if name=='late_union' else [0]):
   dest=out/(name+f'_abort{abort}_map.hex')
   z=subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe),f'+MASK={mp}',f'+OUT={dest}',f'+FAULT={int(overflow)}',f'+ABORT={abort}'],cwd=ROOT,capture_output=True,text=True,timeout=60)
   (out/(name+f'_abort{abort}.log')).write_text(z.stdout+z.stderr)
   marker='HAND_LABEL_MAP_EXPECTED_OVERFLOW_PASS' if overflow else 'HAND_LABEL_MAP_PASS'
   if z.returncode or marker not in z.stdout:raise AssertionError((name,abort,z.stdout,z.stderr))
   if not overflow:
    labels=np.loadtxt(dest,dtype=np.uint16,converters=lambda s:int(s,16)).reshape(90,160)
    verify(labels&255,seed);verify(labels>>8,grown)
   records.append(dict(name=name,abort=abort,overflow=overflow,seed_allocations=pixel_allocations(seed),grown_allocations=pixel_allocations(grown)))
 if hashes!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}:raise RuntimeError('source changed')
 (out/'result.json').write_text(json.dumps(dict(status='PERSISTENT_LABEL_MAP_RTL_PASS_NOT_FULL_ASSOCIATION',tests=len(records),records=records,hashes=hashes),indent=2));print('PERSISTENT_LABEL_MAP_RTL_PASS',len(records))
if __name__=='__main__':main()
