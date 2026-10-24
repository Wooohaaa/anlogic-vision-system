"""Frame ownership, fault invalidation, clear/drain and consecutive-frame recovery."""
import argparse,hashlib,json,subprocess
from pathlib import Path
import cv2
import numpy as np
from test_hand_blob_scan import ROOT,pack
from test_hand_frame_classifier import RTL
SOURCES=['host/tests/tb_hand_frame_classifier_faults.sv']+['rtl/user/'+s for s in RTL]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--scratch',type=int,choices=(0,1),default=0);a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve();hashes={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}
 m=np.zeros((90,160),np.uint8);cv2.rectangle(m,(50,44),(95,70),1,-1);cv2.rectangle(m,(69,65),(84,89),1,-1)
 mp=out/'mask.bin';mp.write_bytes(np.array(pack(m,m),dtype='>u4').tobytes());exe=out/'faults.vvp'
 z=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s','tb_hand_frame_classifier_faults',f'-Ptb_hand_frame_classifier_faults.EXTERNAL_SCRATCH={a.scratch}','-o',str(exe)]+SOURCES,cwd=ROOT,capture_output=True,text=True);(out/'compile.log').write_text(z.stdout+z.stderr)
 if z.returncode:raise RuntimeError(z.stderr)
 z=subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe),f'+MASK={mp}'],cwd=ROOT,capture_output=True,text=True,timeout=120);(out/'sim.log').write_text(z.stdout+z.stderr)
 if z.returncode or 'HAND_FRAME_CLASSIFIER_FAULTS_PASS' not in z.stdout:raise AssertionError(z.stdout+z.stderr)
 if hashes!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in hashes}:raise RuntimeError('source changed')
 (out/'result.json').write_text(json.dumps(dict(status='FRAME_CLASSIFIER_FAULT_RECOVERY_PASS',external_scratch=a.scratch,hashes=hashes),indent=2));print(z.stdout)
if __name__=='__main__':main()
