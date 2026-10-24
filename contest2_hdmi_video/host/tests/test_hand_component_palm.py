"""Selected component isolation -> serial palm RTL, with independent CCL masks."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import cv2
import numpy as np
from test_hand_blob_scan import ROOT,pack,unpack
from test_hand_palm_distance import reference


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True)
    p.add_argument('--random-cases',type=int,default=8);a=p.parse_args();a.out.mkdir(parents=True,exist_ok=False)
    out=a.out.resolve();exe=out/'component_palm.vvp'
    sources=['host/tests/tb_hand_component_palm.sv','rtl/user/ua_hand_component_mask.v','rtl/user/ua_hand_palm_distance.v','rtl/user/ua_hand_scratch_ram.v']
    c=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s','tb_hand_component_palm','-o',str(exe),*sources],cwd=ROOT,capture_output=True,text=True)
    (out/'compile.log').write_text(c.stdout+c.stderr)
    if c.returncode:raise RuntimeError(c.stderr)
    scenes=[]
    ring=np.zeros((90,160),np.uint8);cv2.rectangle(ring,(20,10),(80,70),1,3);cv2.circle(ring,(50,40),7,1,-1)
    scenes.append(('ring_with_unrelated_center',ring,ring))
    hand=np.zeros((90,160),np.uint8);cv2.rectangle(hand,(55,42),(95,72),1,-1);cv2.rectangle(hand,(65,65),(85,89),1,-1)
    for x,y in [(56,22),(66,12),(77,8),(88,20)]:cv2.rectangle(hand,(x,y),(x+5,49),1,-1)
    cv2.rectangle(hand,(40,49),(60,56),1,-1);scenes.append(('hand',hand,hand))
    rng=np.random.default_rng(418018)
    for i in range(a.random_cases):
        seed=np.zeros((90,160),np.uint8)
        for _ in range(7):
            cv2.ellipse(seed,(int(rng.integers(160)),int(rng.integers(90))),
                        (int(rng.integers(2,17)),int(rng.integers(2,15))),0,0,360,1,-1)
        grown=cv2.dilate(seed,np.ones((3,3),np.uint8))
        scenes.append((f'random_{i}',seed,grown))
    for folder in ('vectors_new','vectors_old'):
        for path in sorted((ROOT/'tmp/hand_rtl'/folder).glob('frame_*.hex')):
            scenes.append((folder+'_'+path.stem,*unpack([int(s,16) for s in path.read_text().split()])))
    records=[]
    def run(name,seed,grown,mode,k,variant=None,error=0,bbox=None,anchor=None):
        variant=variant or []
        mask=(seed,grown)[mode];_,labels,stats,_=cv2.connectedComponentsWithStats(mask.astype(np.uint8),8)
        x,y,w,h,area=map(int,stats[k]) if bbox is None else bbox
        if anchor is None:
            yy,xx=np.nonzero(labels==k);anchor=(int(xx[yy.argmin()]),int(yy.min()))
        selected=(labels[y:y+h,x:x+w]==k).astype(np.uint8)
        dist,cx,cy,radius=reference(selected)
        stem=f'{name}_{mode}_{k}'+''.join(variant).replace('+','_').replace('=','_')+f'_err{error}'
        packed=out/(stem+'_mask.hex');expected=out/(stem+'_expected.hex')
        packed.write_text(''.join(f'{v:05x}\n' for v in pack(seed,grown)))
        expected.write_text(''.join(f'{int(v):03x}\n' for v in ((selected.astype(np.int32)<<11)|dist).ravel()))
        cmd=['C:/iverilog/bin/vvp.exe',str(exe),f'+INPUT={packed}',f'+EXPECTED={expected}',f'+MODE={mode}',
             f'+X={x}',f'+Y={y}',f'+W={w}',f'+H={h}',f'+AX={anchor[0]}',f'+AY={anchor[1]}',
             f'+CX={cx}',f'+CY={cy}',f'+R={radius}',f'+AREA={area}',f'+ERROR={error}',*variant]
        r=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True,timeout=60)
        (out/(stem+'.log')).write_text(r.stdout+r.stderr)
        if r.returncode or 'HAND_COMPONENT_PALM_PASS' not in r.stdout:raise AssertionError((stem,r.stdout[-4000:],r.stderr))
        records.append(dict(name=name,mode=mode,area=area,bbox=[x,y,w,h],anchor=anchor,variant=variant,error=error))
    for name,seed,grown in scenes:
        for mode,mask in enumerate((seed,grown)):
            n,labels,stats,_=cv2.connectedComponentsWithStats(mask.astype(np.uint8),8)
            eligible=[k for k in range(1,n) if int(stats[k,4])<=2500]
            if not eligible:continue
            k=max(eligible,key=lambda k:stats[k,4]);run(name,seed,grown,mode,k)
            if name=='hand' and mode==1:
                run(name,seed,grown,mode,k,['+ABORT=1']);run(name,seed,grown,mode,k,['+ABORT=2'])
            if name=='ring_with_unrelated_center' and mode==1:
                run(name,seed,grown,mode,k,error=1,anchor=(50,20))
    full=np.ones((90,160),np.uint8);run('overflow',full,full,1,1,error=2)
    report=dict(status='COMPONENT_ISOLATION_PALM_RTL_PASS_NOT_GESTURE_SIGNOFF',tests=len(records),records=records,
                hashes={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in sources})
    (out/'result.json').write_text(json.dumps(report,indent=2));print(json.dumps({k:v for k,v in report.items() if k!='records'}))


if __name__=='__main__':main()
