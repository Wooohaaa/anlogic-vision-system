"""Exact native-grid chamfer/palm RTL comparison, including captured masks.

This validates the palm arithmetic core, not candidate selection or gestures.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import cv2
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'host'))
from hand_fixed_classifier import distance_q4
from test_hand_blob_scan import unpack


def reference(mask):
    dist=distance_q4(mask)
    h,w=mask.shape
    search=dist.copy();search[int(h*.82):]=0
    y,x=np.unravel_index(int(search.argmax()),search.shape)
    radius=int(search[y,x])
    envelope=search.max(axis=1).astype(np.int64)
    smooth=np.convolve(envelope,np.ones(5,dtype=np.int64),mode='full')[2:2+h]
    for row in range(2,h-2):
        if 4*int(smooth[row])>=13*radius and smooth[row]>=smooth[row-1] and smooth[row]>smooth[row+1]:
            y=row;x=int(search[row].argmax());radius=int(search[row,x]);break
    return dist,int(x),int(y),radius


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out',type=Path,required=True)
    p.add_argument('--random-cases',type=int,default=24)
    p.add_argument('--external',type=int,choices=(0,1),default=0)
    a=p.parse_args();a.out.mkdir(parents=True,exist_ok=False)
    out=a.out.resolve();exe=out/'palm.vvp'
    sources=['host/tests/tb_hand_palm_distance.sv','rtl/user/ua_hand_palm_distance.v','rtl/user/ua_hand_scratch_ram.v']
    c=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s','tb_hand_palm_distance',
        '-Ptb_hand_palm_distance.EXTERNAL='+str(a.external),'-o',str(exe),*sources],cwd=ROOT,capture_output=True,text=True)
    (out/'compile.log').write_text(c.stdout+c.stderr)
    if c.returncode:raise RuntimeError(c.stderr)
    # Independent exhaustive check of the shared constant quotient expression.
    values=np.arange(65536,dtype=np.int64);numerator=2*values+62
    estimate=(numerator*524)>>16
    actual=estimate+((estimate+1)*125<=numerator)
    if not np.array_equal(actual,(16*values+500)//1000):raise AssertionError('quantizer')
    cases=[];rng=np.random.default_rng(418017)
    for h,w in [(1,1),(1,17),(13,1),(3,7),(7,5),(90,160),(89,159)]:
        cases.extend([(f'zero_{w}_{h}',np.zeros((h,w),np.uint8)),
                      (f'full_{w}_{h}',np.ones((h,w),np.uint8))])
    for i in range(a.random_cases):
        h=int(rng.integers(5,91));w=int(rng.integers(5,161))
        mask=np.zeros((h,w),np.uint8)
        for _ in range(int(rng.integers(1,8))):
            x=int(rng.integers(w));y=int(rng.integers(h))
            axes=(int(rng.integers(1,max(2,w//3))),int(rng.integers(1,max(2,h//3))))
            cv2.ellipse(mask,(x,y),axes,float(rng.integers(180)),0,360,1,-1)
        if i%3==0:mask[rng.random(mask.shape)<.1]=0
        cases.append((f'random_{i}',mask))
    for folder in ('vectors_new','vectors_old'):
        for path in sorted((ROOT/'tmp/hand_rtl'/folder).glob('frame_*.hex')):
            _,grown=unpack([int(s,16) for s in path.read_text().split()])
            n,labels,stats,_=cv2.connectedComponentsWithStats(grown.astype(np.uint8),8)
            if n>1:
                k=1+int(stats[1:,4].argmax());x,y,w,h,_=map(int,stats[k])
                cases.append((folder+'_'+path.stem,(labels[y:y+h,x:x+w]==k).astype(np.uint8)))
    records=[]
    for index,(name,mask) in enumerate(cases):
        dist,x,y,radius=reference(mask);h,w=mask.shape;path=out/(name+'.hex')
        path.write_text(''.join(f'{int(v):03x}\n' for v in ((mask.astype(np.int32)<<11)|dist).ravel()))
        variants=[[]]
        if name=='full_160_90':variants+=[['+BAD_LAST=1'],['+BAD_LAST=2'],['+ABORT=1'],['+ABORT=2'],['+ZERO_REUSE=1']]
        for variant in variants:
            cmd=['C:/iverilog/bin/vvp.exe',str(exe),f'+INPUT={path}',f'+W={w}',f'+H={h}',
                 f'+CX={x}',f'+CY={y}',f'+R={radius}',*variant]
            result=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True,timeout=60)
            suffix=''.join(variant).replace('+','_').replace('=','_')
            (out/(name+suffix+'.log')).write_text(result.stdout+result.stderr)
            if result.returncode or 'HAND_PALM_DISTANCE_PASS' not in result.stdout:
                raise AssertionError((name,variant,result.stdout[-4000:],result.stderr))
            records.append(dict(name=name,width=w,height=h,variant=variant,pixels=w*h,
                                center=[x,y],radius_q4=radius))
    report=dict(status='PALM_DISTANCE_RTL_EXACT_PASS_NOT_GESTURE_SIGNOFF',tests=len(records),
                pixel_cases=sum(c['pixels'] for c in records),records=records,
                hashes={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in sources},
                quantizer_exhaustive_values=65536)
    (out/'result.json').write_text(json.dumps(report,indent=2))
    print(json.dumps({k:v for k,v in report.items() if k!='records'}))


if __name__=='__main__':main()
