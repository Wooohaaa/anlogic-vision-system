"""Shared queue/distance/hull RAM end-to-end geometry, not full gesture classification."""
import argparse,hashlib,json,subprocess,sys
from pathlib import Path
import cv2
import numpy as np
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'host'))
from hand_fixed_classifier import integer_hull
from test_hand_blob_scan import pack,unpack
from test_hand_palm_distance import reference
from test_hand_wrist_median import expected as wrist_reference
RTL=['ua_hand_geometry_shared.v','ua_hand_component_mask.v','ua_hand_palm_distance.v',
     'ua_hand_wrist_median.v','ua_hand_convex_hull.v','ua_hand_scratch_ram.v']
SOURCES=['host/tests/tb_hand_geometry_shared.sv']+['rtl/user/'+s for s in RTL]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--shared',type=int,choices=(0,1),default=1);a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve();frozen={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}
 exe=out/'geometry.vvp'
 def compile(exe,watchdog):
  r=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s','tb_hand_geometry_shared',f'-Ptb_hand_geometry_shared.WATCHDOG={watchdog}',f'-Ptb_hand_geometry_shared.SHARED={a.shared}','-o',str(exe)]+SOURCES,cwd=ROOT,capture_output=True,text=True)
  (out/(exe.stem+'_compile.log')).write_text(r.stdout+r.stderr)
  if r.returncode:raise RuntimeError(r.stderr)
 compile(exe,4000000);short=out/'watchdog.vvp';compile(short,200)
 scenes=[]
 ring=np.zeros((90,160),np.uint8);cv2.rectangle(ring,(20,10),(80,70),1,3);cv2.circle(ring,(50,40),7,1,-1);scenes.append(('ring',ring,ring))
 hand=np.zeros((90,160),np.uint8);cv2.rectangle(hand,(55,42),(95,72),1,-1);cv2.rectangle(hand,(65,65),(85,89),1,-1)
 for x,y in [(56,22),(66,12),(77,8),(88,20)]:cv2.rectangle(hand,(x,y),(x+5,49),1,-1)
 scenes.append(('hand',hand,hand))
 rng=np.random.default_rng(418051)
 for i in range(8):
  seed=np.zeros((90,160),np.uint8)
  for j in range(7):cv2.ellipse(seed,(int(rng.integers(160)),int(rng.integers(90))),(int(rng.integers(2,17)),int(rng.integers(2,15))),0,0,360,1,-1)
  scenes.append((f'random{i}',seed,cv2.dilate(seed,np.ones((3,3),np.uint8))))
 for folder in ('vectors_new','vectors_old'):
  for path in sorted((ROOT/'tmp/hand_rtl'/folder).glob('frame_*.hex')):scenes.append((folder+'_'+path.stem,*unpack([int(s,16) for s in path.read_text().split()])))
 records=[]
 def run(name,seed,grown,mode,k,extra=None,force_fault=False,bad_anchor=False):
  m=(seed,grown)[mode];n,labels,stats,_=cv2.connectedComponentsWithStats(m.astype(np.uint8),8)
  x,y,w,h,area=map(int,stats[k]);yy,xx=np.nonzero(labels==k);anchor_x=int(xx[yy.argmin()]);anchor_y=int(yy.min())
  selected=(labels[y:y+h,x:x+w]==k).astype(np.uint8);dist,cx,cy,r=reference(selected)
  yy,xx=np.nonzero(selected);hull=integer_hull([(int(x),int(y)) for x,y in zip(xx,yy)])
  wx,wy,lower=wrist_reference(selected,cx,cy,r)
  stem=f'{name}_{mode}_{len(records)}';mp=out/(stem+'_mask.hex');ep=out/(stem+'_expected.hex');hp=out/(stem+'_hull.hex')
  mp.write_text(''.join(f'{v:05x}\n' for v in pack(seed,grown)))
  ep.write_text(''.join(f'{int(v):04x}\n' for v in ((selected.astype(np.int32)<<11)|dist).flat))
  hp.write_text(''.join(f'{y*256+x:04x}\n' for x,y in hull))
  if bad_anchor:anchor_x=50;anchor_y=20
  params=dict(X=x,Y=y,W=w,H=h,AX=anchor_x,AY=anchor_y,MODE=mode,CX=cx,CY=cy,R=r,AREA=area,LOWER=lower,DX=wx-2*cx,DY=wy-2*cy,HC=len(hull))
  cmd=['C:/iverilog/bin/vvp.exe',str(short if force_fault else exe),f'+MASK={mp}',f'+EXPECTED={ep}',f'+HULL={hp}']+[f'+{k}={v}' for k,v in params.items()]+(extra or [])
  if force_fault or bad_anchor or area>2500:cmd.append('+FAULT=1')
  z=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True,timeout=90);(out/(stem+'.log')).write_text(z.stdout+z.stderr)
  if z.returncode or 'HAND_GEOMETRY_SHARED_PASS' not in z.stdout:raise AssertionError(stem+' '+z.stdout+z.stderr)
  records.append(dict(name=name,mode=mode,area=area,bbox=[x,y,w,h],hull_vertices=len(hull),extra=extra,fault=force_fault or bad_anchor or area>2500))
 for name,seed,grown in scenes:
  for mode,m in enumerate((seed,grown)):
   n,labels,stats,_=cv2.connectedComponentsWithStats(m.astype(np.uint8),8);eligible=[k for k in range(1,n) if int(stats[k,4])<=2500]
   if not eligible:continue
   k=max(eligible,key=lambda k:stats[k,4]);run(name,seed,grown,mode,k)
   if name=='hand' and mode==1:
    for stage in (1,2,3,4):run(name,seed,grown,mode,k,[f'+ABORT={stage}'])
    run(name,seed,grown,mode,k,force_fault=True)
   if name=='ring' and mode==1:run(name,seed,grown,mode,k,bad_anchor=True)
 full=np.ones((90,160),np.uint8);run('overflow',full,full,1,1)
 if frozen!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}:raise RuntimeError('changed tested source')
 (out/'result.json').write_text(json.dumps(dict(status='SHARED_GEOMETRY_CHAIN_PASS_NOT_GESTURE_SIGNOFF',shared_memory=a.shared,tests=len(records),hashes=frozen,records=records),indent=2));print(f'SHARED_GEOMETRY_CHAIN_PASS tests={len(records)} shared={a.shared}')
if __name__=='__main__':main()
