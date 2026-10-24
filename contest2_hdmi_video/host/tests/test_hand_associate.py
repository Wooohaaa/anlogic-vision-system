"""Exact hardware top16/overlap/dedup/fallback vs original candidates().

Descriptors and persistent labels supplied independently, NOT full RGB RTL.
Randomly permuted root numbers ensure raster/root IDs aren't used as CV rank.
"""
import argparse,hashlib,json,subprocess,sys
from pathlib import Path
import cv2
import numpy as np
from test_hand_blob_scan import ROOT,unpack
sys.path.insert(0,str(ROOT/'host'))
from hand_fpga_grid_model import candidates
SOURCES=['host/tests/tb_hand_associate.sv','rtl/user/ua_hand_associate.v']

def descriptor(region,red):
 yy,xx=np.nonzero(region);x=int(xx.min());xm=int(xx.max());y=int(yy.min());ym=int(yy.max())
 anchor=int(np.argmin(yy*160+xx));ax=int(xx[anchor]);ay=int(yy[anchor]);area=len(xx)
 key=int(((yy//2)*80+xx//2).min());rs=int(red[region].sum())
 return (key<<84)|(rs<<60)|(area<<46)|(ax<<38)|(ay<<31)|(xm<<23)|(x<<15)|(ym<<8)|(y<<1)

def expected(seed,grown,red):
 ns,sl,ss,_=cv2.connectedComponentsWithStats(seed,8)
 _,gl,gs,_=cv2.connectedComponentsWithStats(grown,8);used=set();result=[]
 for label in sorted(range(1,ns),key=lambda k:-int(ss[k,4]))[:16]:
  region=sl==label;mode=0;ids,counts=np.unique(gl[region],return_counts=True)
  overlap=[(int(c),int(k)) for k,c in zip(ids,counts) if k]
  if overlap:
   _,gid=max(overlap);x,y,w,h,area=map(int,gs[gid])
   if x>1 and x+w<159 and area<=2500:
    if gid in used:continue
    used.add(gid);region=gl==gid;mode=1
  result.append((mode,descriptor(region,red)))
 return result

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--random-cases',type=int,default=20);p.add_argument('--build-descriptors',action='store_true');a=p.parse_args()
 sources=SOURCES if not a.build_descriptors else ['host/tests/tb_hand_descriptor_build.sv','rtl/user/ua_hand_associate.v','rtl/user/ua_hand_descriptor_build.v']
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve();hashes={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in sources}
 exe=out/'association.vvp';z=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s',('tb_hand_descriptor_build' if a.build_descriptors else 'tb_hand_associate'),'-o',str(exe)]+sources,cwd=ROOT,capture_output=True,text=True)
 (out/'compile.log').write_text(z.stdout+z.stderr)
 if z.returncode:raise RuntimeError(z.stderr)
 rng=np.random.default_rng(181020);scenes=[]
 for dataset,folder in [('old','hand_hdmi_20261017'),('new','hand_hdmi_162050')]:
  words=np.memmap(ROOT/'tmp'/folder/'native/groups.bin',dtype='>u4',mode='r').reshape(-1,180,320)
  for path in sorted((ROOT/'tmp/hand_rtl'/('vectors_'+dataset)).glob('frame_*.hex')):
   frame=int(path.stem.split('_')[-1]);pck=words[frame];red=((pck>>20)&1023).astype(np.int32);red=(red[1::2,::2]+red[1::2,1::2])>>1
   scenes.append((dataset+'_'+str(frame),*unpack([int(v,16) for v in path.read_text().split()]),red))
 empty=np.zeros((90,160),np.uint8)
 scenes.append(('empty',empty,empty,empty.astype(np.int32)))
 # Explicit equal-overlap tie, border fallback, and many seed -> same grown.
 seed=empty.copy();grown=empty.copy();seed[20:30,20:50]=1;grown[20:30,20:30]=1;grown[20:30,40:50]=1
 scenes.append(('overlap_tie',seed,grown,np.full_like(empty,200,dtype=np.int32)))
 seed=empty.copy();grown=empty.copy();seed[20:30,20:30]=1;seed[40:50,20:30]=1;grown[18:52,18:32]=1
 scenes.append(('dedup',seed,grown,np.full_like(empty,200,dtype=np.int32)))
 for i in range(a.random_cases):
  seed=empty.copy()
  for _ in range(25):
   x,y=map(int,rng.integers([0,0],[160,90]));cv2.rectangle(seed,(x,y),(min(159,x+int(rng.integers(1,9))),min(89,y+int(rng.integers(1,10)))),1,-1)
  grown=cv2.dilate(seed,np.ones((5,5),np.uint8));scenes.append((f'random{i}',seed,grown,rng.integers(0,1024,(90,160),dtype=np.int32)))
 records=[]
 for name,seed,grown,red in scenes:
  maps=[];descs=[0]*256
  for mode,mask in enumerate((seed,grown)):
   n,labels,_,_=cv2.connectedComponentsWithStats(mask,8)
   if n>128:raise RuntimeError('too many fixture components')
   roots=rng.choice(np.arange(1,128),n-1,replace=False);lookup=np.zeros(n,np.uint16);lookup[1:]=roots
   maps.append(lookup[labels])
   for k,root in enumerate(roots,1):descs[mode*128+int(root)]=descriptor(labels==k,red)
  mp=out/(name+'_map.hex');mp.write_text(''.join(f'{v:04x}\n' for v in (maps[0]|(maps[1]<<8)).ravel()))
  dp=out/(name+'_descs.hex');dp.write_text(''.join(f'{v:024x}\n' for v in descs))
  raw=[]
  for i,v in enumerate(descs):
   if (v>>46)&16383:
    raw.append(((i>>7)<<39)|(((v>>31)&127)<<32)|(((v>>38)&255)<<24)|((v>>60)&16777215))
  if len(raw)>128:raise RuntimeError('fixture raw blob overflow')
  rp=out/(name+'_raw.hex');rp.write_text(''.join(f'{v:010x}\n' for v in raw+[0]*(128-len(raw))))
  target=expected(seed,grown,red)
  for abort in ([0,1,2] if name=='dedup' and not a.build_descriptors else [0]):
   dest=out/(name+f'_abort{abort}_actual.txt');z=subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe),f'+MAP={mp}',f'+DESCS={dp}',f'+OUT={dest}',f'+ABORT={abort}',f'+RAW={rp}',f'+RAW_COUNT={len(raw)}'],cwd=ROOT,capture_output=True,text=True,timeout=90)
   (out/(name+f'_abort{abort}.log')).write_text(z.stdout+z.stderr)
   if z.returncode or 'HAND_ASSOCIATION_PASS' not in z.stdout:raise AssertionError((name,abort,z.stdout,z.stderr))
   actual=[(int(v[0]),int(v[1],16)) for line in dest.read_text().splitlines() if (v:=line.split())]
   if actual!=target:raise AssertionError((name,actual,target))
   records.append(dict(name=name,abort=abort,candidates=len(target),map_sha256=hashlib.sha256(mp.read_bytes()).hexdigest()))
 if hashes!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in sources}:raise RuntimeError('source changed')
 status='DESCRIPTOR_BUILD_ASSOCIATION_RTL_PASS_SOFTWARE_LABEL_MAP_AND_CCL_STATS' if a.build_descriptors else 'EXACT_ASSOCIATION_RTL_PASS_SOFTWARE_DESCRIPTORS_NOT_FULL_CHAIN'
 (out/'result.json').write_text(json.dumps(dict(status=status,tests=len(records),hashes=hashes,records=records),indent=2));print(status,len(records))
if __name__=='__main__':main()
