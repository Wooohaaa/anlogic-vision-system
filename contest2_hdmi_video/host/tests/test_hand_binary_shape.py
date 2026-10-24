"""Exact selected component + two-class shape rules, true RTL, not full video."""
import argparse,hashlib,json,subprocess
from pathlib import Path
import cv2
import numpy as np
from test_hand_blob_scan import ROOT,pack,unpack
from prototype_hand_binary_features import metrics
from evaluate_hand_binary_rules import classify
RTL=['ua_hand_binary_shape.v','ua_hand_component_mask.v','ua_hand_scratch_ram.v','ua_hand_product_serial.v']
SOURCES=['host/tests/tb_hand_binary_shape.sv']+['rtl/user/'+s for s in RTL]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve();hashes={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}
 def compile(name,maximum):
  exe=out/(name+'.vvp');z=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s','tb_hand_binary_shape',f'-Ptb_hand_binary_shape.MAX_CYCLES={maximum}','-o',str(exe)]+SOURCES,cwd=ROOT,capture_output=True,text=True);(out/(name+'_compile.log')).write_text(z.stdout+z.stderr)
  if z.returncode:raise RuntimeError(z.stderr)
  return exe
 exe=compile('binary',4000000);watchdog=compile('watchdog',200)
 scenes=[]
 for count in range(6):
  m=np.zeros((90,160),np.uint8);cv2.rectangle(m,(50,44),(95,70),1,-1);cv2.rectangle(m,(69,65),(84,89),1,-1)
  for k in range(count):cv2.rectangle(m,(50+k*9,10+(k%3)*6),(54+k*9,49),1,-1)
  scenes.append((f'fingers{count}',m,m))
 rng=np.random.default_rng(181101)
 for i in range(10):
  m=np.zeros((90,160),np.uint8)
  for _ in range(8):cv2.ellipse(m,tuple(map(int,rng.integers([0,0],[160,90]))),tuple(map(int,rng.integers(2,14,2))),0,0,360,1,-1)
  scenes.append((f'random{i}',m,cv2.dilate(m,np.ones((3,3),np.uint8))))
 for folder in ('vectors_old','vectors_new'):
  for path in sorted((ROOT/'tmp/hand_rtl'/folder).glob('frame_*.hex')):scenes.append((folder+'_'+path.stem,*unpack([int(v,16) for v in path.read_text().split()])))
 records=[]
 for name,seed,grown in scenes:
  for mode,mask in enumerate((seed,grown)):
   n,labels,stats,_=cv2.connectedComponentsWithStats(mask,8);eligible=[k for k in range(1,n) if int(stats[k,4])<=2500]
   if not eligible:continue
   k=max(eligible,key=lambda k:int(stats[k,4]));region=labels==k;data=metrics(region);data['mode']=mode;raw=classify(data)
   yy,xx=np.nonzero(region);first=int(yy.argmin());mp=out/(name+f'_{mode}.hex');mp.write_text(''.join(f'{v:05x}\n' for v in pack(seed,grown)))
   params=dict(X=data['x'],Y=data['y'],W=data['w'],H=data['h'],AX=int(xx[first]),AY=int(yy[first]),MODE=mode,AREA=data['area'],ROWS=data['row3'],RAW=raw)
   aborts=[0,1,2,3] if name=='fingers3' and mode==1 else [0]
   for abort in aborts:
    z=subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe),f'+MASK={mp}',f'+ABORT={abort}']+[f'+{k}={v}' for k,v in params.items()],cwd=ROOT,capture_output=True,text=True,timeout=60)
    (out/(name+f'_{mode}_abort{abort}.log')).write_text(z.stdout+z.stderr)
    if z.returncode or 'HAND_BINARY_SHAPE_PASS' not in z.stdout:raise AssertionError((name,mode,abort,z.stdout,z.stderr))
    records.append(dict(name=name,mode=mode,abort=abort,raw=raw,rows3=data['row3']))
   if name=='fingers3' and mode==1:
    z=subprocess.run(['C:/iverilog/bin/vvp.exe',str(watchdog),f'+MASK={mp}','+FAULT=1']+[f'+{k}={v}' for k,v in params.items()],cwd=ROOT,capture_output=True,text=True,timeout=30)
    (out/'watchdog.log').write_text(z.stdout+z.stderr)
    if z.returncode or 'fault=1' not in z.stdout:raise AssertionError(z.stdout)
 if hashes!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}:raise RuntimeError('source changed')
 (out/'result.json').write_text(json.dumps(dict(status='BINARY_COMPONENT_SHAPE_RTL_PASS_NOT_FULL_VIDEO',tests=len(records),records=records,hashes=hashes),indent=2));print('BINARY_COMPONENT_SHAPE_RTL_PASS',len(records))
if __name__=='__main__':main()
