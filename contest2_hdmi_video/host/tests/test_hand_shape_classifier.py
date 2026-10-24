"""Immutable masks -> full selected-component raw classifier vs fixed Python features.

This is not whole-video candidate selection or temporal-vote signoff.
"""
import argparse,hashlib,json,subprocess,sys
from pathlib import Path
import cv2
import numpy as np
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'host'))
from hand_fixed_classifier import features
from test_hand_blob_scan import pack,unpack
from test_hand_palm_distance import reference
RTL=['ua_hand_shape_classifier.v','ua_hand_tip_candidates.v','ua_hand_tip_filter.v','ua_hand_tip_width.v',
     'ua_hand_product_serial.v','ua_hand_defect_geometry.v','ua_hand_defect_scan.v','ua_hand_defect_edge.v',
     'ua_hand_integer_math.v','ua_hand_geometry_shared.v','ua_hand_scratch_ram.v','ua_hand_component_mask.v',
     'ua_hand_palm_distance.v','ua_hand_wrist_median.v','ua_hand_convex_hull.v','ua_hand_contour_trace.v']
SOURCES=['host/tests/tb_hand_shape_classifier.sv']+['rtl/user/'+s for s in RTL]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--parallel',type=int,choices=(0,1),default=0);p.add_argument('--scratch',type=int,choices=(0,1),default=0);a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve();frozen={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES+['host/hand_fixed_classifier.py']}
 def compile(name,watchdog):
  exe=out/(name+'.vvp');z=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s','tb_hand_shape_classifier',f'-Ptb_hand_shape_classifier.WATCHDOG={watchdog}',f'-Ptb_hand_shape_classifier.PARALLEL_COMPARE={a.parallel}',f'-Ptb_hand_shape_classifier.EXTERNAL_SCRATCH={a.scratch}','-o',str(exe)]+SOURCES,cwd=ROOT,capture_output=True,text=True)
  (out/(name+'_compile.log')).write_text(z.stdout+z.stderr)
  if z.returncode:raise RuntimeError(z.stderr)
  return exe
 exe=compile('classifier',16000000);short=compile('watchdog',200)
 scenes=[]
 for count in range(6):
  m=np.zeros((90,160),np.uint8);cv2.rectangle(m,(50,44),(95,70),1,-1);cv2.rectangle(m,(69,65),(84,89),1,-1)
  for x in range(count):cv2.rectangle(m,(50+x*9,10+(x%3)*6),(54+x*9,49),1,-1)
  scenes.append((f'fingers{count}',m,m))
 m=np.zeros((90,160),np.uint8);cv2.rectangle(m,(10,10),(25,25),1,-1);cv2.rectangle(m,(26,26),(40,40),1,-1);scenes.append(('articulation',m,m))
 m=np.zeros((90,160),np.uint8);cv2.rectangle(m,(10,10),(40,40),1,2);m[20:25,20:25]=1;scenes.append(('ring_unrelated',m,m))
 rng=np.random.default_rng(418112)
 for i in range(10):
  m=np.zeros((90,160),np.uint8)
  for j in range(5):cv2.ellipse(m,(int(rng.integers(160)),int(rng.integers(90))),(int(rng.integers(2,15)),int(rng.integers(2,15))),0,0,360,1,-1)
  scenes.append((f'random{i}',m,cv2.dilate(m,np.ones((3,3),np.uint8))))
 for folder in ('vectors_new','vectors_old'):
  for filename in sorted((ROOT/'tmp/hand_rtl'/folder).glob('frame_*.hex')):
   scenes.append((folder+'_'+filename.stem,*unpack([int(s,16) for s in filename.read_text().split()])))
 records=[]
 for name,seed,grown in scenes:
  for mode,m in enumerate((seed,grown)):
   n,labels,stats,_=cv2.connectedComponentsWithStats(m.astype(np.uint8),8)
   eligible=[k for k in range(1,n) if int(stats[k,4])<=2500]
   if not eligible:continue
   k=max(eligible,key=lambda k:int(stats[k,4]));x,y,w,h,area=map(int,stats[k]);yy,xx=np.nonzero(labels==k)
   ax=int(xx[yy.argmin()]);ay=int(yy.min());selected=(labels[y:y+h,x:x+w]==k).astype(np.uint8)
   _,cx,cy,r=reference(selected);f=features(selected);raw=f['raw'] if f else 0;tips=f['tips'] if f else 0
   stem=f'{name}_{mode}';mp=out/(stem+'_mask.hex');mp.write_text(''.join(f'{v:05x}\n' for v in pack(seed,grown)))
   for abort in ([0,1,2,3,4] if name=='fingers1' and mode==1 else [0]):
    params=dict(X=x,Y=y,W=w,H=h,AX=ax,AY=ay,MODE=mode,RAW=raw,TIPS=tips,CX=cx,CY=cy,R=r,AREA=area,ABORT=abort)
    z=subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe),f'+MASK={mp}']+[f'+{k}={v}' for k,v in params.items()],cwd=ROOT,capture_output=True,text=True,timeout=120)
    (out/(stem+f'_abort{abort}.log')).write_text(z.stdout+z.stderr)
    if z.returncode or 'HAND_SHAPE_CLASSIFIER_PASS' not in z.stdout:raise AssertionError(stem+': '+z.stdout+z.stderr)
    records.append(dict(name=name,mode=mode,abort=abort,raw=raw,tips=tips,log=z.stdout.strip()))
   if name=='fingers1' and mode==1:
    params['ABORT']=0;params['FAULT']=1
    z=subprocess.run(['C:/iverilog/bin/vvp.exe',str(short),f'+MASK={mp}']+[f'+{k}={v}' for k,v in params.items()],cwd=ROOT,capture_output=True,text=True,timeout=30)
    (out/'watchdog.log').write_text(z.stdout+z.stderr)
    if z.returncode or 'fault=1' not in z.stdout:raise AssertionError(z.stdout+z.stderr)
 if frozen!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES+['host/hand_fixed_classifier.py']}:raise RuntimeError('source changed')
 (out/'result.json').write_text(json.dumps(dict(status='SELECTED_COMPONENT_CLASSIFIER_PASS_NOT_FULL_VIDEO_SIGNOFF',parallel_compare=a.parallel,external_scratch=a.scratch,tests=len(records),hashes=frozen,records=records),indent=2));print(f'SELECTED_COMPONENT_CLASSIFIER_PASS tests={len(records)} scratch={a.scratch}')
if __name__=='__main__':main()
