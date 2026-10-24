"""Finalized candidate metadata -> RTL winner, including exact red floor mean.

Optional all-video vectors use software geometry as input: policy signoff ONLY.
"""
import argparse,hashlib,json,random,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'host'))
SOURCES=['host/tests/tb_hand_frame_policy.sv','rtl/user/ua_hand_frame_policy.v',
         'rtl/user/ua_hand_product_serial.v','rtl/user/ua_hand_integer_math.v']
def winner(candidates,backlit):
 found=[]
 for c in candidates:
  x,y,w,h,cx,cy,area,redsum,radius,raw,tips=c
  if area<50 or area>2500 or w<12 or h<10 or x<=1 or x+w>=159 or y+h>90 or cx>=w or cy>=h or h>3.5*w or w>3*h or 5*h<3*w or radius<80:continue
  mean=redsum//area
  if mean<(160 if backlit else 96):continue
  if h*100<w*85 and not(raw==1 and area*100>=60*w*h and radius>=4*min(w,h)):continue
  found.append((area*min(mean*100,38400),c,mean))
 return max(found,key=lambda c:c[0]) if found else None
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--video',action='store_true');a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve();frozen={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES+[str(Path(__file__).relative_to(ROOT))]}
 rng=random.Random(418121);frames=[];video_hashes={}
 def add(candidates,bright=0,abort=0):frames.append((candidates,bright,abort))
 base=(20,10,40,60,20,30,800,800*96,160,1,0)
 def change(**kw):
  c=list(base)
  for k,v in kw.items():c[dict(x=0,y=1,w=2,h=3,cx=4,cy=5,area=6,redsum=7,radius=8,raw=9,tips=10)[k]]=v
  return tuple(c)
 for mean in (0,95,96,97,159,160,161,383,384,385,1023):
  for remainder in (0,799):add([change(redsum=800*mean+remainder if mean<1023 else 800*mean)])
 for bright in (449,450,225,224,0):add([change(redsum=800*159)],bright)
 for kw in ({'x':1},{'x':119},{'w':11},{'h':9},{'area':49},{'area':2501},{'radius':79},{'cx':40},{'cy':60},
            {'w':20,'h':71},{'w':61,'h':20},{'w':50,'h':29},
            {'w':40,'h':30,'area':720,'redsum':720*160,'radius':119},
            {'w':40,'h':30,'area':720,'redsum':720*160,'radius':120},
            {'w':40,'h':30,'area':719,'redsum':719*160,'radius':120},
            {'w':40,'h':30,'area':720,'redsum':720*160,'radius':120,'raw':2}):add([change(**kw)])
 # Keep first equal-scoring candidate, including raw zero. Floor mean matters.
 add([change(raw=0,redsum=800*100),change(raw=3,redsum=800*100)])
 add([change(redsum=800*100+799),change(x=30,redsum=800*101)])
 for stage in (3,5,7):add([base],abort=stage)
 for i in range(600):
  candidates=[]
  for j in range(rng.randrange(25)):
   x=rng.randrange(160);y=rng.randrange(90);w=rng.randrange(1,161);h=rng.randrange(1,91);area=rng.randrange(1,3501)
   candidates.append((x,y,w,h,rng.randrange(w),rng.randrange(h),area,area*rng.randrange(1024)+rng.randrange(area),rng.randrange(2048),rng.randrange(4),rng.randrange(8)))
  add(candidates,rng.choice((0,224,225,449,450,1000)))
 if a.video:
  import numpy as np
  from hand_fpga_grid_model import candidates as get_candidates
  from hand_fixed_classifier import features
  for folder in ('hand_hdmi_20261017','hand_hdmi_162050'):
   path=ROOT/'tmp'/folder/'native/groups.bin';video_hashes[str(path.relative_to(ROOT))]=hashlib.sha256(path.read_bytes()).hexdigest()
   words=np.memmap(path,dtype='>u4',mode='r').reshape(-1,180,320)
   # A new video starts with the same neutral exposure-hysteresis state.
   add([],0)
   for frame,packed in enumerate(words):
    rgb=[((packed>>s)&1023).astype(np.int32) for s in (20,10,0)]
    r,g,b=[(v[1::2,::2]+v[1::2,1::2])>>1 for v in rgb];rows=[]
    for region,x,y,w,h,area in get_candidates(r,g,b):
     if area<50 or area>2500 or w<12 or h<10 or x<=1 or x+w>=159 or h>3.5*w or w>3*h or 5*h<3*w:continue
     f=features(region[y:y+h,x:x+w].astype(np.uint8))
     if f is None:continue
     rows.append((x,y,w,h,*f['center'],area,int(r[region].sum()),f['radius_q4'],f['raw'],f['tips']))
    add(rows,int(((r>=960)&(g>=960)&(b>=960)).sum()))
    if frame%200==0:print(f'policy vectors {folder} frame={frame}',flush=True)
 vector=out/'frames.txt';lines=[];backlit=False
 for candidates,bright,abort in frames:
  if abort:backlit=False
  best=winner(candidates,backlit)
  if bright>=450:backlit=True
  elif bright<225:backlit=False
  if best:
   score,c,mean=best;x,y,w,h,cx,cy,area,_,radius,raw,tips=c
   expected=(1,raw,tips,x,y,w,h,cx,cy,area,radius,mean,score)
  else:expected=(0,)*13
  lines.append(' '.join(map(str,(len(candidates),bright,*expected,int(backlit),abort))))
  lines.extend(' '.join(map(str,c)) for c in candidates)
 vector.write_text('\n'.join(lines)+'\n');exe=out/'policy.vvp'
 z=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s','tb_hand_frame_policy','-o',str(exe)]+SOURCES,cwd=ROOT,capture_output=True,text=True)
 (out/'compile.log').write_text(z.stdout+z.stderr)
 if z.returncode:raise RuntimeError(z.stderr)
 z=subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe),f'+INPUT={vector}'],cwd=ROOT,capture_output=True,text=True,timeout=120)
 (out/'sim.log').write_text(z.stdout+z.stderr)
 if z.returncode or 'HAND_FRAME_POLICY_PASS' not in z.stdout:raise AssertionError(z.stdout+z.stderr)
 if frozen!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in frozen}:raise RuntimeError('source changed')
 (out/'result.json').write_text(json.dumps(dict(status='FRAME_POLICY_PASS_SOFTWARE_GEOMETRY_INPUT_NOT_FULL_VIDEO_RTL',tests=len(frames),video_metadata=a.video,hashes=frozen,input_hashes=video_hashes),indent=2));print(z.stdout)
if __name__=='__main__':main()
