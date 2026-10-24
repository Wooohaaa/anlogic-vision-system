"""Cycle-equivalent exact-depth motion RAM; old macro uses a functional contract model."""
import argparse,hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve();sources=['host/tests/tb_motion_compact_equivalence.sv','rtl/user/ua_motion_detect.v','rtl/user/ua_motion_ref_ram.v'];records=[]
 for i,(w,h,d,roi,hold) in enumerate([(1280,720,4,0,1),(80,48,2,1,1),(80,48,1,0,0),(80,47,4,1,0)]):
  exe=out/f'motion_{i}.vvp';cmd=['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s','tb_motion_compact_equivalence','-o',str(exe)]
  for key,val in [('W',w),('H',h),('DOWNSAMPLE',d),('ROI',roi),('HOLD',hold)]:cmd.append(f'-Ptb_motion_compact_equivalence.{key}={val}')
  c=subprocess.run(cmd+sources,cwd=ROOT,capture_output=True,text=True);(out/f'compile_{i}.log').write_text(c.stdout+c.stderr)
  if c.returncode:raise RuntimeError(c.stderr)
  r=subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe)],cwd=ROOT,capture_output=True,text=True,timeout=120);(out/f'motion_{i}.log').write_text(r.stdout+r.stderr)
  if r.returncode or 'MOTION_COMPACT_EQUIVALENCE_PASS' not in r.stdout:raise AssertionError(r.stdout+r.stderr)
  records.append(dict(width=w,height=h,downsample=d,roi=roi,hold=hold));print(r.stdout.strip(),flush=True)
 report=dict(status='MOTION_COMPACT_FUNCTIONAL_EQUIVALENCE_PASS_NOT_ROUTED',records=records,
             hashes={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in sources},
             legacy_model='same-clock DP/NOREG functional contract; not encrypted vendor simulation')
 (out/'result.json').write_text(json.dumps(report,indent=2))

if __name__=='__main__':main()
