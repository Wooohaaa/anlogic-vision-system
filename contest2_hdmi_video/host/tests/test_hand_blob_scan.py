"""Self-check serial RTL CCL against independent OpenCV component statistics.

Tests both seed and grown fields, all components (not only selected targets),
clear during a pending read, restart without reset and bounded-capacity failure.
This is localization verification, NOT gesture-classifier qualification.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess
import cv2
import numpy as np

ROOT=Path(__file__).resolve().parents[2]


def capacity_overflow(mask):
    """Same documented storage limits, independent row-run union implementation."""
    parents={}; previous=[]
    def root(label):
        while parents[label]!=label: label=parents[label]
        return label
    for row in mask:
        edges=np.diff(np.pad(row.astype(np.int8),(1,1)))
        spans=list(zip(np.flatnonzero(edges==1),np.flatnonzero(edges==-1)-1))
        current=[]
        for left,right in spans:
            overlap={root(label) for pleft,pright,label in previous
                     if pright+1>=left and right+1>=pleft}
            if overlap:
                label=min(overlap)
                for other in overlap: parents[other]=label
            else:
                free=[v for v in range(1,16) if v not in parents]
                if not free: return True
                label=free[0];parents[label]=label
            current.append((left,right,label))
            if len(current)>16:return True
        current=[(left,right,root(label)) for left,right,label in current]
        live={label for _,_,label in current}
        parents={label:label for label in live}
        previous=current
    return False


def blobs(mask,seed):
    n,labels,stats,_=cv2.connectedComponentsWithStats(mask.astype(np.uint8),8)
    return Counter((int(stats[k,4]),int(seed[labels==k].sum()),
                    int(stats[k,0]),int(stats[k,0]+stats[k,2]-1),
                    int(stats[k,1]),int(stats[k,1]+stats[k,3]-1),
                    int(np.flatnonzero(labels[stats[k,1]]==k)[0]),int(stats[k,1])) for k in range(1,n))


def pack(seed,grown):
    pixels=seed.astype(np.uint32)|(grown.astype(np.uint32)<<2)
    result=[]
    for row in pixels:
        padded=np.pad(row,(0,2)).reshape(27,6)
        result.extend((padded << np.arange(0,18,3,dtype=np.uint32)).sum(axis=1))
    return [int(v) for v in result]


def unpack(words):
    rows=np.array(words,dtype=np.uint32).reshape(90,27)
    pixels=((rows[:,:,None] >> np.arange(0,18,3,dtype=np.uint32))&7).reshape(90,162)[:,:160]
    return (pixels&1).astype(np.uint8),((pixels>>2)&1).astype(np.uint8)


def synthetic(count):
    rng=np.random.default_rng(74129)
    z=np.zeros((90,160),np.uint8)
    yield 'empty',z,z
    one=np.ones_like(z);yield 'full',one,one
    diagonal=z.copy()
    for j in range(80):diagonal[j,j]=1
    yield 'diagonal_8connected',diagonal,diagonal
    comb=z.copy();comb[:40,4:145:10]=1;comb[40,4:145]=1
    yield 'late_bridge_15_labels',comb,comb
    reuse=z.copy();reuse[::3,3:144:10]=1
    yield 'label_reuse_420_components',reuse,reuse
    many=z.copy();many[5,2:159:8]=1
    yield 'live_label_overflow',many,many
    split=z.copy();split[:5,1:158]=1;split[5:10,1:158:8]=1
    yield 'run_overflow_one_component',split,split
    border=z.copy();border[:,0]=1;border[:,-1]=1;border[0,:]=1;border[-1,:]=1
    yield 'all_four_borders',border,border
    hand=z.copy();hand[30:65,50:105]=1
    for x,h in [(50,12),(62,5),(74,1),(86,7),(98,15)]:hand[h:40,x:x+7]=1
    yield 'five_runs_palm',hand,hand
    holes=one.copy();holes[1:89:3,1:159:3]=0
    yield 'internal_holes',holes,holes
    for i in range(count):
        grown=z.copy()
        for _ in range(int(rng.integers(1,32))):
            x=int(rng.integers(0,160));y=int(rng.integers(0,90))
            grown[y:min(y+int(rng.integers(1,30)),90),x:min(x+int(rng.integers(1,45)),160)]=1
        if i%5==0:grown[rng.random(z.shape)<.002]=1
        seed=(grown & (rng.random(z.shape)>.03)).astype(np.uint8)
        yield f'random_{i:03}',seed,grown


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--random-cases',type=int,default=100)
    args=parser.parse_args();args.out.mkdir(parents=True,exist_ok=False)
    executable=args.out.resolve()/'blob_scan.vvp'
    command=['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s','tb_hand_blob_scan',
             '-o',str(executable),'host/tests/tb_hand_blob_scan.sv','rtl/user/ua_hand_blob_scan.v']
    result=subprocess.run(command,cwd=ROOT,capture_output=True,text=True)
    (args.out/'compile.log').write_text(result.stdout+result.stderr)
    if result.returncode:raise RuntimeError(result.stderr)
    records=[]
    def check(name,seed,grown,words=None):
        path=args.out/f'{name}.hex'
        path.write_text(''.join(f'{v:05x}\n' for v in (pack(seed,grown) if words is None else words)))
        run=subprocess.run(['C:/iverilog/bin/vvp.exe',str(executable),f'+INPUT={path.resolve()}'],
                           cwd=ROOT,capture_output=True,text=True,timeout=30)
        (args.out/f'{name}.log').write_text(run.stdout+run.stderr)
        if run.returncode or 'HAND_BLOB_SCAN_COMPLETE' not in run.stdout:raise RuntimeError(name+' RTL failed')
        actual=[Counter(),Counter()];done={}
        for line in run.stdout.splitlines():
            fields=line.split()
            if fields[0]=='BLOB':actual[int(fields[1])][tuple(map(int,fields[2:]))]+=1
            if fields[0]=='DONE':done[int(fields[1])]=tuple(map(int,fields[2:]))
        for mode,mask in enumerate((seed,grown)):
            expected_overflow=capacity_overflow(mask)
            if done[mode][0]!=expected_overflow:raise AssertionError((name,mode,'overflow',done[mode],expected_overflow))
            if not expected_overflow:
                expected=blobs(mask,seed)
                if actual[mode]!=expected:
                    raise AssertionError((name,mode,'missing',expected-actual[mode],'extra',actual[mode]-expected))
            records.append(dict(name=name,mode=mode,overflow=expected_overflow,cycles=done[mode][1],
                                components=sum(actual[mode].values()),hex_sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    for name,seed,grown in synthetic(args.random_cases):check(name,seed,grown)
    for folder in ('vectors_new','vectors_old'):
        for path in sorted((ROOT/'tmp/hand_rtl'/folder).glob('frame_*.hex')):
            words=[int(v,16) for v in path.read_text().split()]
            check(folder+'_'+path.stem,*unpack(words),words=words)
    report=dict(status='CCL_LOCALIZATION_PASS_NOT_CLASSIFIER_SIGNOFF',tests=records,
                rtl_sha256=hashlib.sha256((ROOT/'rtl/user/ua_hand_blob_scan.v').read_bytes()).hexdigest(),
                completed_modes=len(records),overflow_modes=sum(r['overflow'] for r in records),
                max_cycles=max(r['cycles'] for r in records))
    (args.out/'result.json').write_text(json.dumps(report,indent=2))
    print(json.dumps({k:v for k,v in report.items() if k!='tests'}))


if __name__=='__main__':main()
