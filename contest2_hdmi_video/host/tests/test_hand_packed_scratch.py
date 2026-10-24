"""Exhaustive addresses, lifetime reuse and alternating one-cycle RAM reads."""
import argparse,hashlib,json,subprocess,re
from pathlib import Path
from test_hand_blob_scan import ROOT
def main():
 p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);a=p.parse_args();a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve()
 sources=['rtl/user/ua_hand_scratch_ram.v','host/tests/tb_hand_packed_scratch.sv']
 hashes={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in sources}
 exe=out/'ram.vvp'
 for name,cmd in [('compile',['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb_hand_packed_scratch','-o',str(exe)]+sources),('sim',['C:/iverilog/bin/vvp.exe',str(exe)])]:
  r=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True,timeout=120);text=r.stdout+r.stderr;(out/(name+'.log')).write_text(text)
  if r.returncode or (name=='sim' and 'PACKED_SCRATCH_ONE_CYCLE_PASS' not in text):raise AssertionError(text[-3000:])
 if hashes!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in sources}:raise RuntimeError('RAM changed during test')
 checks=int(re.search(r'checks=\s*(\d+)',text)[1])
 (out/'result.json').write_text(json.dumps(dict(status='PACKED_SCRATCH_ONE_CYCLE_RTL_PASS_NOT_ROUTED',checks=checks,hashes=hashes),indent=2));print('PACKED_SCRATCH_ONE_CYCLE_RTL_PASS',checks)
if __name__=='__main__':main()
