"""Audit bounded hardware CCL capacity on every decoded video frame.

Mask arithmetic is the frozen raster reference, NOT a full RTL video replay.
No labels are used or changed; overflow frames are recorded rather than skipped.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from hand_fpga_grid_model import masks
from test_hand_blob_scan import capacity_overflow

ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--out',type=Path,required=True)
args=parser.parse_args();args.out.mkdir(parents=True,exist_ok=False)
results=[]
for dataset in ('hand_hdmi_20261017','hand_hdmi_162050'):
    native=ROOT/'tmp'/dataset/'native'
    manifest=json.loads((native/'manifest.json').read_text())
    packed=np.memmap(native/'groups.bin',dtype='>u4',mode='r').reshape(-1,180,320)
    overflow=[[],[]];max_runs=[0,0]
    for index,frame in enumerate(packed):
        rgb=[((frame>>s)&1023).astype(np.int32) for s in (20,10,0)]
        seed,grown=masks(*[((v[1::2,::2]+v[1::2,1::2])>>1) for v in rgb])
        for mode,mask in enumerate((seed,grown)):
            starts=np.diff(np.pad(mask.astype(np.int8),((0,0),(1,1))),axis=1)==1
            max_runs[mode]=max(max_runs[mode],int(starts.sum(axis=1).max()))
            if capacity_overflow(mask):overflow[mode].append(index)
    results.append(dict(dataset=dataset,frames=len(packed),source_sha256=manifest['sha256'],
                        max_runs_per_row=max_runs,overflow_frames=overflow))
report=dict(status='FULL_VIDEO_CAPACITY_MODEL_AUDIT_NOT_RTL_CLASSIFICATION',datasets=results,
            model_sha256=hashlib.sha256((ROOT/'host/hand_fpga_grid_model.py').read_bytes()).hexdigest(),
            rtl_sha256=hashlib.sha256((ROOT/'rtl/user/ua_hand_blob_scan.v').read_bytes()).hexdigest())
(args.out/'result.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report))
