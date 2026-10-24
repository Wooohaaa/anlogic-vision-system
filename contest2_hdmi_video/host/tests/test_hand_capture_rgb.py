"""Actual RGB samples through all FPGA gesture stages; no injected masks,
descriptors, association, geometry or temporal state. Selected-frame replay,
two repetitions/frame to verify stable vote from a hardware reset.
"""
import argparse,hashlib,json,re,subprocess,sys,time
from collections import Counter,deque
from pathlib import Path
import numpy as np
from test_hand_frame_classifier import RTL as FRAME_RTL
from test_hand_frame_policy import winner
from test_hand_blob_scan import ROOT
sys.path.insert(0,str(ROOT/'host'))
from hand_fpga_grid_model import masks,candidates
from hand_fixed_classifier import features
from prototype_hand_binary_features import metrics
from evaluate_hand_binary_rules import classify as binary_classify
RTL=list(dict.fromkeys(FRAME_RTL+['ua_hand_native_classifier.v','ua_hand_mask_frame.v','ua_hand_blob_scan.v',
 'ua_hand_label_map.v','ua_hand_descriptor_build.v','ua_hand_associate.v']))
SOURCES=['host/tests/tb_hand_native_classifier.sv']+['rtl/user/'+s for s in RTL]

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--input',type=Path,required=True);p.add_argument('--frames',default='0,210,240,390');p.add_argument('--out',type=Path,required=True);p.add_argument('--limit',type=int,default=0);p.add_argument('--binary',action='store_true');a=p.parse_args()
 sources=SOURCES if not a.binary else ['host/tests/tb_hand_capture_rgb.sv']+['rtl/user/'+s for s in (
  'ua_hand_binary_native.v','ua_hand_binary_shape.v','ua_hand_mask_frame.v','ua_hand_blob_scan.v','ua_hand_scratch_ram.v',
  'ua_hand_component_mask.v','ua_hand_product_serial.v','ua_hand_integer_math.v','ua_hand_temporal_vote.v')]
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve()
 evidence=sources+[str(Path(__file__).relative_to(ROOT)), 'host/hand_fpga_grid_model.py',
  'host/tests/prototype_hand_binary_features.py','host/tests/evaluate_hand_binary_rules.py']
 hashes={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in evidence}
 model=Path('C:/intelFPGA/20.1/modelsim_ase/win32aloem')
 z=subprocess.run([str(model/'vlib.exe'),'work'],cwd=out,capture_output=True,text=True)
 if z.returncode:raise RuntimeError(z.stdout+z.stderr)
 z=subprocess.run([str(model/'vlog.exe'),'-sv','-work','work']+(['+define+HAND_BINARY'] if a.binary else [])+[str(ROOT/s) for s in sources],cwd=out,capture_output=True,text=True);(out/'compile.log').write_text(z.stdout+z.stderr)
 if z.returncode:raise RuntimeError(z.stdout+z.stderr)
 records=[];inputs={};begin=time.monotonic()
 for dataset,folder in [('capture','unused')]:
  path=(a.input/'groups.bin').resolve();inputs[str(path.relative_to(ROOT))]=hashlib.sha256(path.read_bytes()).hexdigest()
  words=np.memmap(path,dtype='>u4',mode='r').reshape(-1,180,320)
  paths=[Path(f'frame_{int(v)}.hex') for v in a.frames.split(',')]
  if a.limit:paths=paths[:a.limit]
  for fixture in paths:
   frame=int(fixture.stem.split('_')[-1]);packed=words[frame]
   channels=[((packed>>shift)&1023).astype(np.int32) for shift in (20,10,0)]
   r,g,b=[(v[1::2,::2]+v[1::2,1::2])>>1 for v in channels];rows=[];binary_rows=[]
   if a.binary:
    import cv2
    for mode,mask in enumerate(masks(r,g,b)):
     n,labels,stats,_=cv2.connectedComponentsWithStats(mask,8)
     for k in range(1,n):
      x,y,w,h,area=map(int,stats[k])
      if area<200 or area>2500 or w<12 or h<10 or x<=1 or x+w>=159 or h>3.5*w or w>3*h or 5*h<3*w:continue
      region=labels==k;data=metrics(region);data['mode']=mode;raw=binary_classify(data)
      if raw:
       yy,xx=np.nonzero(region);key=int((yy*256+xx).min());mean=int(r[region].sum())//area
       binary_rows.append(dict(raw=raw,x=x,y=y,w=w,h=h,mean=mean,score=area*min(mean,384),key=key,mode=mode))
   else:
    for region,x,y,w,h,area in candidates(r,g,b):
     f=features(region[y:y+h,x:x+w].astype(np.uint8)) if 0<area<=2500 else None
     if f:rows.append((x,y,w,h,*f['center'],area,int(r[region].sum()),f['radius_q4'],f['raw'],f['tips']))
   bright=int(((r>=960)&(g>=960)&(b>=960)).sum());backlit=False;votes=deque(maxlen=5);held=miss=0;expected=[]
   for _ in range(2):
    if a.binary:
     eligible=[c for c in binary_rows if c['mean']>=(160 if backlit else 96)]
     best=max(eligible,key=lambda c:(c['score'],-c['key'],-c['mode'])) if eligible else None
     raw=best['raw'] if best else 0
    else:best=winner(rows,backlit);raw=best[1][9] if best else 0
    votes.append(raw)
    if not raw:
     miss+=1
     if miss>=5:held=0;votes.clear()
    else:
     miss=0;v,n=Counter(votes).most_common(1)[0]
     if v and n>=(2 if not held else 3):held=v
    if bright>=450:backlit=True
    elif bright<225:backlit=False
    if best and a.binary:x,y,w,h=(best[k] for k in ('x','y','w','h'));tips=3 if raw==3 else 0
    elif best:_,c,mean=best;x,y,w,h,_,_,_,_,radius,_,tips=c
    else:x=y=w=h=tips=0
    expected.append((held,raw,int(best is not None and held!=0),tips,x,y,w,h))
   exp=out/f'{dataset}_{frame}_expected.txt';exp.write_text(''.join(' '.join(map(str,row))+'\n' for row in expected))
   run=[str(model/'vsim.exe'),'-c','-onfinish','exit','work.tb_hand_capture_rgb',f'+INPUT={path}',f'+EXPECTED={exp}',f'+FRAME={frame}',
    '-do','onerror {quit -code 1}; run -all; quit -code 0']
   z=subprocess.run(run,cwd=out,capture_output=True,text=True,timeout=600);text=z.stdout+z.stderr;(out/f'{dataset}_{frame}.log').write_text(text)
   if z.returncode or 'HAND_NATIVE_RGB_CLASSIFIER_PASS' not in text:raise AssertionError((dataset,frame,text[-3500:]))
   cycles=[int(v) for v in re.findall(r'NATIVE_FRAME_PASS.*?cycles=\s*(\d+)',text)]
   if len(cycles)!=2:raise AssertionError('missing completed RGB frame')
   records.append(dict(dataset=dataset,frame=frame,cycles=cycles,expected=expected));print(f'NATIVE_RGB_PASS {dataset} frame={frame} cycles={cycles}',flush=True)
 if hashes!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in evidence}:raise RuntimeError('source changed during test')
 status='CAPTURE_RGB_BINARY_RTL_MATCHES_MODEL_NOT_BOARD_SIGNOFF' if a.binary else 'SELECTED_REAL_RGB_FULL_GESTURE_RTL_PASS_NOT_BOARD_SIGNOFF'
 (out/'result.json').write_text(json.dumps(dict(status=status,tests=len(records),frames=2*len(records),seconds=time.monotonic()-begin,records=records,hashes=hashes,input_hashes=inputs),indent=2));print(status,2*len(records))
if __name__=='__main__':main()
