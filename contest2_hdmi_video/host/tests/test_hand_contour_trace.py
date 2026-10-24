"""Check exact external boundary pixel multiplicities against OpenCV, no labels.

Clock count includes random memory latency. This does NOT test classification.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess
import cv2
import numpy as np
from test_hand_blob_scan import ROOT,pack,unpack,synthetic


def same_boundary_walk(actual,expected):
    """Same cyclic traversal, allowing orientation reversal, not arbitrary order."""
    if len(actual)!=len(expected) or not actual:return False
    for sequence in (expected,list(reversed(expected))):
        for i,point in enumerate(sequence):
            if point==actual[0] and actual==sequence[i:]+sequence[:i]:return True
    return False


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True)
    p.add_argument('--random-cases',type=int,default=60);p.add_argument('--exact-opencv',action='store_true');a=p.parse_args()
    a.out.mkdir(parents=True,exist_ok=False);exe=a.out.resolve()/'contour.vvp'
    compiled=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s','tb_hand_contour_trace',
        f'-Ptb_hand_contour_trace.OPENCV_ORDER={int(a.exact_opencv)}',
        '-o',str(exe),'host/tests/tb_hand_contour_trace.sv','rtl/user/ua_hand_contour_trace.v'],
        cwd=ROOT,capture_output=True,text=True)
    (a.out/'compile.log').write_text(compiled.stdout+compiled.stderr)
    if compiled.returncode:raise RuntimeError(compiled.stderr)
    records=[]
    def run(name,seed,grown,words=None):
        path=a.out/f'{name}.hex'
        path.write_text(''.join(f'{v:05x}\n' for v in (pack(seed,grown) if words is None else words)))
        for mode,mask in enumerate((seed,grown)):
            n,labels,stats,_=cv2.connectedComponentsWithStats(mask.astype(np.uint8),8)
            if n<=1:continue
            # Largest and smallest exercise long contours and isolated pixels.
            for which,k in enumerate(dict.fromkeys([1+int(stats[1:,4].argmax()),1+int(stats[1:,4].argmin())])):
                region=(labels==k).astype(np.uint8)
                y=int(stats[k,1]);x=int(np.flatnonzero(region[y])[0])
                contours,_=cv2.findContours(region,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_NONE)
                expected_points=list(map(tuple,contours[0][:,0,:].tolist()))
                expected=Counter(expected_points)
                result=subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe),f'+INPUT={path.resolve()}',
                    f'+X={x}',f'+Y={y}',f'+MODE={mode}'],cwd=ROOT,capture_output=True,text=True,timeout=30)
                (a.out/f'{name}_{mode}_{which}.log').write_text(result.stdout+result.stderr)
                if result.returncode or 'HAND_CONTOUR_TRACE_COMPLETE' not in result.stdout:
                    raise RuntimeError((name,mode,which,result.stdout,result.stderr))
                actual=Counter();actual_points=[];done=None
                for line in result.stdout.splitlines():
                    f=line.split()
                    if f[0]=='V':
                        point=tuple(map(int,f[1:]));actual[point]+=1;actual_points.append(point)
                    if f[0]=='DONE':done=tuple(map(int,f[1:]))
                ordered_ok=actual_points==expected_points if a.exact_opencv else same_boundary_walk(actual_points,expected_points)
                if not done or done[0] or actual!=expected or done[1]!=sum(expected.values()) or not ordered_ok:
                    raise AssertionError((name,mode,which,done,'missing',expected-actual,'extra',actual-expected))
                records.append(dict(name=name,mode=mode,component=k,points=done[1],cycles=done[2]))
    for name,s,g in synthetic(a.random_cases):run(name,s,g)
    for folder in ('vectors_new','vectors_old'):
        for path in sorted((ROOT/'tmp/hand_rtl'/folder).glob('frame_*.hex')):
            words=[int(v,16) for v in path.read_text().split()]
            run(folder+'_'+path.stem,*unpack(words),words=words)
    report=dict(status='CONTOUR_BOUNDARY_PASS_NOT_CLASSIFIER_SIGNOFF',exact_opencv_order=a.exact_opencv,tests=records,
                rtl_sha256=hashlib.sha256((ROOT/'rtl/user/ua_hand_contour_trace.v').read_bytes()).hexdigest(),
                completed=len(records),max_points=max(r['points'] for r in records),
                max_cycles=max(r['cycles'] for r in records))
    (a.out/'result.json').write_text(json.dumps(report,indent=2))
    print(json.dumps({k:v for k,v in report.items() if k!='tests'}))


if __name__=='__main__':main()
