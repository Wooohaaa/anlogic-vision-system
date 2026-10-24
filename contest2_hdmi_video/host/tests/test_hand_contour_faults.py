"""Check bad anchors and bounded contour aborts; failures must be explicit."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import numpy as np
from test_hand_blob_scan import ROOT,pack

p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True)
a=p.parse_args();a.out.mkdir(parents=True,exist_ok=False)
z=np.zeros((90,160),np.uint8);one=np.ones_like(z)
records=[]
for name,mask,x,y,limit,wanted_count in (
    ('background_anchor',z,20,20,8192,0),
    ('out_of_bounds',one,255,127,8192,0),
    ('bounded_steps',one,0,0,2,2),
):
    path=a.out/f'{name}.hex';path.write_text(''.join(f'{v:05x}\n' for v in pack(mask,mask)))
    exe=a.out.resolve()/f'{name}.vvp'
    compile_result=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb_hand_contour_trace',
        f'-Ptb_hand_contour_trace.STEP_LIMIT={limit}','-o',str(exe),
        'host/tests/tb_hand_contour_trace.sv','rtl/user/ua_hand_contour_trace.v'],cwd=ROOT,capture_output=True,text=True)
    if compile_result.returncode:raise RuntimeError(compile_result.stderr)
    result=subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe),f'+INPUT={path.resolve()}',
        f'+X={x}',f'+Y={y}','+MODE=1'],cwd=ROOT,capture_output=True,text=True,timeout=10)
    (a.out/f'{name}.log').write_text(result.stdout+result.stderr)
    done=[tuple(map(int,line.split()[1:])) for line in result.stdout.splitlines() if line.startswith('DONE ')]
    if result.returncode or len(done)!=1 or done[0][:2]!=(1,wanted_count):
        raise AssertionError((name,result.stdout,result.stderr))
    records.append(dict(name=name,fault=done[0][0],points=done[0][1],cycles=done[0][2]))
report=dict(status='CONTOUR_EXPLICIT_FAULT_PASS',tests=records,
            rtl_sha256=hashlib.sha256((ROOT/'rtl/user/ua_hand_contour_trace.v').read_bytes()).hexdigest())
(a.out/'result.json').write_text(json.dumps(report,indent=2));print(report)
