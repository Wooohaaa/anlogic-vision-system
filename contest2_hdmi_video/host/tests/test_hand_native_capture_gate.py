"""Whole-frame external capture admission and existing double-bank compatibility."""
import argparse,hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve();records=[];hashes={}
 for tb,marker,extra in (
  ('tb_hand_native_capture_gate','HAND_NATIVE_CAPTURE_GATE_PASS',[]),
  ('tb_hand_mask_ownership','HAND_MASK_OWNERSHIP_CCL_PASS',['rtl/user/ua_hand_blob_scan.v'])):
  sources=['host/tests/'+tb+'.sv','rtl/user/ua_hand_mask_frame.v']+extra
  for s in sources:hashes[s]=hashlib.sha256((ROOT/s).read_bytes()).hexdigest()
  exe=out/(tb+'.vvp');z=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s',tb,'-o',str(exe)]+sources,cwd=ROOT,capture_output=True,text=True)
  (out/(tb+'_compile.log')).write_text(z.stdout+z.stderr)
  if z.returncode:raise RuntimeError(z.stderr)
  z=subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe)],cwd=ROOT,capture_output=True,text=True,timeout=30)
  (out/(tb+'.log')).write_text(z.stdout+z.stderr)
  if z.returncode or marker not in z.stdout:raise AssertionError(z.stdout+z.stderr)
  records.append(tb);print(z.stdout)
 if hashes!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in hashes}:raise RuntimeError('source changed')
 (out/'result.json').write_text(json.dumps(dict(status='NATIVE_CAPTURE_ADMISSION_AND_LEGACY_OWNERSHIP_PASS',tests=records,hashes=hashes),indent=2))
if __name__=='__main__':main()
