"""Compare exact-depth demosaic RAM to the used generated IP's functional contract."""
import argparse, hashlib, json, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BASE='rtl/official/hdl_source/isp/demosaic_4x_2_0/'
SOURCES=['host/tests/tb_demosaic_compact.sv','rtl/user/ua_demosaic_line_ram.v',
         BASE+'line_buffer_demosaic.v', BASE+'zhenghe.v']
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',required=True,type=Path);a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve();records=[]
 frozen={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}
 for i,(w,h) in enumerate([(1280,720),(1920,1080),(640,47),(80,24)]):
  exe=out/f'demosaic_{i}.vvp'
  cmd=['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s','tb_demosaic_compact',
       '-Ptb_demosaic_compact.W='+str(w),'-Ptb_demosaic_compact.H='+str(h),'-o',str(exe)]+SOURCES
  r=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True);(out/f'compile_{i}.log').write_text(r.stdout+r.stderr)
  if r.returncode:raise RuntimeError(r.stderr)
  r=subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe)],cwd=ROOT,capture_output=True,text=True,timeout=180)
  (out/f'sim_{i}.log').write_text(r.stdout+r.stderr)
  if r.returncode or 'DEMOSAIC_COMPACT_EQUIVALENCE_PASS' not in r.stdout:raise AssertionError(r.stdout+r.stderr)
  print(r.stdout.strip(),flush=True);records.append(dict(width=w,height=h))
 if frozen!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}:
  raise RuntimeError('Source changed during simulation; reject mixed-source evidence')
 report=dict(status='DEMOSAIC_COMPACT_FUNCTIONAL_EQUIVALENCE_PASS_NOT_ROUTED',records=records,
             hashes=frozen,
             legacy_model='used same-clock synchronous RAM contract, not encrypted vendor simulation')
 (out/'result.json').write_text(json.dumps(report,indent=2))
if __name__=='__main__':main()
