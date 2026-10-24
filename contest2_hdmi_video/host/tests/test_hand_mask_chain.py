"""Actual RGB-group -> mask -> CCL -> external contour RTL selected-frame test.

Video capture samples, not software-rendered masks, drive the RTL frontend.
Every resulting packed mask word and component are checked. The largest grown
component is traced solely for wiring verification; this is NOT hand selection.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess
import cv2
import numpy as np
from test_hand_blob_scan import ROOT,unpack,blobs
from test_hand_contour_trace import same_boundary_walk

p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True)
p.add_argument('--shared-red',action='store_true',help='Capture native R into actual classifier scratch and read it for CCL')
a=p.parse_args();a.out.mkdir(parents=True,exist_ok=False);exe=a.out.resolve()/'chain.vvp'
sources=['host/tests/tb_hand_mask_frame.sv','rtl/user/ua_hand_mask_frame.v',
         'rtl/user/ua_hand_blob_scan.v','rtl/user/ua_hand_contour_trace.v']
if a.shared_red:
    from test_hand_shape_classifier import RTL
    sources=list(dict.fromkeys(sources+['rtl/user/'+name for name in RTL]))
frozen={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in sources}
compiled=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-DHAND_CHAIN',
                        *(['-DHAND_SHARED_RED'] if a.shared_red else []),
                        '-s','tb_hand_mask_frame','-o',str(exe),*sources],cwd=ROOT,capture_output=True,text=True)
(a.out/'compile.log').write_text(compiled.stdout+compiled.stderr)
if compiled.returncode:raise RuntimeError(compiled.stderr)
records=[]
for dataset in ('new','old'):
    groups=ROOT/'tmp'/('hand_hdmi_162050' if dataset=='new' else 'hand_hdmi_20261017')/'native/groups.bin'
    manifest=json.loads((ROOT/'tmp/hand_rtl'/f'vectors_{dataset}/manifest.json').read_text())
    for item in manifest['frames']:
        frame=item['frame'];expected_path=Path(item['path'])
        if hashlib.sha256(expected_path.read_bytes()).hexdigest()!=item['sha256']:raise RuntimeError('oracle changed')
        result=subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe),f'+input={groups}',
            f'+expected={expected_path}',f'+frame={frame}'],cwd=ROOT,capture_output=True,text=True,timeout=90)
        (a.out/f'{dataset}_{frame}.log').write_text(result.stdout+result.stderr)
        if result.returncode or 'HAND_MASK_CCL_CONTOUR_CHAIN_COMPLETE_NOT_CLASSIFIER' not in result.stdout:
            raise RuntimeError((dataset,frame,result.stdout[-2000:],result.stderr))
        seed,grown=unpack([int(v,16) for v in expected_path.read_text().split()])
        actual_blobs=Counter();vertices=Counter();vertex_points=[];chosen=None;actual_red=Counter()
        for line in result.stdout.splitlines():
            f=line.split()
            if f[0]=='CHAIN_BLOB':actual_blobs[tuple(map(int,f[1:]))]+=1
            if f[0]=='CHAIN_RED':actual_red[tuple(map(int,f[1:]))]+=1
            if f[0]=='CHAIN_VERTEX':
                point=tuple(map(int,f[1:]));vertices[point]+=1;vertex_points.append(point)
            if f[0]=='CHAIN_SELECTED':chosen=tuple(map(int,f[1:]))
        if actual_blobs!=blobs(grown,seed):raise AssertionError((dataset,frame,'component mismatch'))
        if a.shared_red:
            packed=np.memmap(groups,dtype='>u4',mode='r').reshape(-1,180,320)[frame]
            red=((packed>>20)&1023).astype(np.int32)
            red=(red[1::2,::2]+red[1::2,1::2])>>1
            n,labels,stats,_=cv2.connectedComponentsWithStats(grown,8);expected_red=Counter()
            for k in range(1,n):
                region=labels==k;yy,xx=np.nonzero(region);first=int(yy.argmin())
                expected_red[(int(stats[k,4]),int(xx[first]),int(yy[first]),int(red[region].sum()))]+=1
            if actual_red!=expected_red:raise AssertionError((dataset,frame,'shared scratch red sum',expected_red-actual_red,actual_red-expected_red))
        if chosen:
            area,x,y=chosen
            n,labels,stats,_=cv2.connectedComponentsWithStats(grown,8)
            k=int(labels[y,x])
            if k==0 or area!=int(stats[k,4]) or area!=int(stats[1:,4].max()):raise AssertionError('wrong trace anchor')
            contours,_=cv2.findContours((labels==k).astype(np.uint8),cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_NONE)
            expected_points=list(map(tuple,contours[0][:,0,:].tolist()));expected=Counter(expected_points)
            if vertices!=expected or not same_boundary_walk(vertex_points,expected_points):
                raise AssertionError((dataset,frame,'boundary mismatch',expected-vertices,vertices-expected))
        elif vertices:raise AssertionError('vertices without component')
        records.append(dict(dataset=dataset,frame=frame,components=sum(actual_blobs.values()),
                            points=sum(vertices.values()),groups_sha256=manifest['groups_sha256']))
if frozen!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in sources}:raise RuntimeError('source changed during regression')
report=dict(status=('SELECTED_VIDEO_RGB_SHARED_SCRATCH_RED_CCL_PASS_NOT_CLASSIFIER' if a.shared_red else 'SELECTED_VIDEO_RGB_MASK_CCL_CONTOUR_RTL_PASS_NOT_CLASSIFIER'),tests=records,
            hashes=frozen)
(a.out/'result.json').write_text(json.dumps(report,indent=2));print(report['status'],len(records))
