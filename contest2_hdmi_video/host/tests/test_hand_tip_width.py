"""RTL two-cut Q8 probes versus independent fixed software finger-width tests."""
import argparse,hashlib,json,subprocess,sys
from pathlib import Path
import cv2
import numpy as np
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'host'))
from hand_fixed_classifier import width_checks,integer_hull
from test_hand_blob_scan import unpack
from test_hand_palm_distance import reference
SOURCES=['host/tests/tb_hand_tip_width.sv','rtl/user/ua_hand_tip_width.v','rtl/user/ua_hand_integer_math.v']
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',required=True,type=Path);a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve();frozen={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}
 exe=out/'width.vvp';z=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s','tb_hand_tip_width','-o',str(exe)]+SOURCES,cwd=ROOT,capture_output=True,text=True)
 (out/'compile.log').write_text(z.stdout+z.stderr)
 if z.returncode:raise RuntimeError(z.stderr)
 cases=[];rng=np.random.default_rng(418061)
 def add(name,m,c,t,r):cases.append((name,m,c,t,int(r)))
 for filled in (0,1):
  m=np.full((90,160),filled,np.uint8)
  for c,t in [((0,0),(159,89)),((159,89),(0,0)),((80,80),(80,10)),((20,45),(150,45)),((80,45),(80,45))]:
   for r in (0,15,16,80,111,2047):add(f'full{filled}',m,c,t,r)
 tie=np.zeros((90,160),np.uint8);tie[:,57:59]=1;tie[:,62:65]=1
 add('negative_pivot_tie',tie,(60,80),(60,10),80)
 for i in range(80):
  h=int(rng.integers(5,91));w=int(rng.integers(5,161));m=(rng.random((h,w))<rng.uniform(.1,.9)).astype(np.uint8)
  c=(int(rng.integers(w)),int(rng.integers(h)));t=(int(rng.integers(w)),int(rng.integers(h)))
  add(f'random{i}',m,c,t,rng.integers(16,2048))
 for folder in ('vectors_new','vectors_old'):
  for path in sorted((ROOT/'tmp/hand_rtl'/folder).glob('frame_*.hex')):
   _,m=unpack([int(s,16) for s in path.read_text().split()]);n,labels,stats,_=cv2.connectedComponentsWithStats(m,8)
   if n<=1:continue
   k=1+int(stats[1:,4].argmax());x,y,w,h,_=stats[k];selected=(labels[y:y+h,x:x+w]==k).astype(np.uint8)
   _,cx,cy,r=reference(selected);yy,xx=np.nonzero(selected);hull=integer_hull([(int(x),int(y)) for x,y in zip(xx,yy)])
   for point in hull:add(folder+'_'+path.stem,selected,(cx,cy),point,r)
 records=[]
 for i,(name,m,c,t,r) in enumerate(cases):
  h,w=m.shape;mp=out/f'mask_{i}.bin';mp.write_text('\n'.join(map(str,m.flat))+'\n')
  checks,_=width_checks(m,2*c[0],2*c[1],r,(0,1),[t])
  widths=checks[0]['widths'] if checks else [None,None];valid=sum((v is not None)<<j for j,v in enumerate(widths));wa,wb=[v or 0 for v in widths]
  narrow=int(bool(checks) and checks[0]['accepted'])
  params=dict(W=w,H=h,CX=c[0],CY=c[1],TX=t[0],TY=t[1],R=r,VALID=valid,WA=wa,WB=wb,NARROW=narrow)
  modes=[[]]
  if name=='negative_pivot_tie':modes += [[f'+ABORT={s}'] for s in (1,2,3)]
  for mode in modes:
   cmd=['C:/iverilog/bin/vvp.exe',str(exe),f'+INPUT={mp}']+[f'+{k}={v}' for k,v in params.items()]+mode
   z=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True,timeout=15);(out/f'case_{i}_{len(records)}.log').write_text(z.stdout+z.stderr)
   if z.returncode or 'HAND_TIP_WIDTH_PASS' not in z.stdout:raise AssertionError(f'case {i} {name} {c} {t} R={r} {mode}: '+z.stdout+z.stderr)
   records.append(dict(name=name,center=c,tip=t,radius_q4=r,widths=widths,mode=mode))
 # Invalid coordinate must report fault, not probe out of bounds.
 cmd=['C:/iverilog/bin/vvp.exe',str(exe),f'+INPUT={mp}',f'+W={w}',f'+H={h}','+CX=255','+CY=0','+TX=0','+TY=0','+R=80','+VALID=0','+WA=0','+WB=0','+NARROW=0','+FAULT=1']
 z=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True,timeout=15);(out/'invalid.log').write_text(z.stdout+z.stderr)
 if z.returncode or 'HAND_TIP_WIDTH_PASS' not in z.stdout:raise AssertionError(z.stdout+z.stderr)
 if frozen!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}:raise RuntimeError('changed tested source')
 (out/'result.json').write_text(json.dumps(dict(status='TIP_WIDTH_RTL_PASS_NOT_CLASSIFIER_SIGNOFF',tests=len(records)+1,hashes=frozen,records=records),indent=2));print(f'TIP_WIDTH_RTL_PASS tests={len(records)+1}')
if __name__=='__main__':main()
