"""Cycle-exact finite-history single-bank versus unchanged legacy ping-pong."""
import argparse,hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SOURCES=['host/tests/tb_photo_compact.sv','rtl/user/ua_photo_finish_96.v']
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--simulator',choices=['iverilog','modelsim'],default='modelsim');a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve();frozen={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES};records=[]
 modelbin=Path('C:/intelFPGA/20.1/modelsim_ase/win32aloem')
 if a.simulator=='modelsim':
  r=subprocess.run([str(modelbin/'vlib.exe'),'work'],cwd=out,capture_output=True,text=True)
  if r.returncode:raise RuntimeError(r.stdout+r.stderr)
  r=subprocess.run([str(modelbin/'vlog.exe'),'-sv','-work','work']+[str(ROOT/s) for s in SOURCES],cwd=out,capture_output=True,text=True)
  (out/'vlog.log').write_text(r.stdout+r.stderr)
  if r.returncode:raise RuntimeError(r.stdout+r.stderr)
 for i,(w,h,bits,five,recursive,tone) in enumerate([(1280,720,9,1,0,1),(80,41,8,1,0,1),(76,47,9,0,0,1),(12,17,8,1,0,0),(80,39,8,0,1,1)]):
  exe=out/f'photo_{i}.vvp';cmd=['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s','tb_photo_compact','-o',str(exe)]
  params=dict(W=w,H=h,BITS=bits,FIVE=five,RECURSIVE=recursive,TONE=tone)
  cmd += [f'-Ptb_photo_compact.{k}={v}' for k,v in params.items()]+SOURCES
  if a.simulator=='iverilog':
   r=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True);(out/f'compile_{i}.log').write_text(r.stdout+r.stderr)
   if r.returncode:raise RuntimeError(r.stderr)
   run_cmd=['C:/iverilog/bin/vvp.exe',str(exe)];run_cwd=ROOT
  else:
   run_cmd=[str(modelbin/'vsim.exe'),'-c','-onfinish','exit','work.tb_photo_compact']+[f'-g{k}={v}' for k,v in params.items()]+['-do','onerror {quit -code 1}; run -all; quit -code 0']
   run_cwd=out
  # Preserve incremental output, including on timeout or user interruption.
  with (out/f'sim_{i}.log').open('w') as log:
   r=subprocess.run(run_cmd,cwd=run_cwd,stdout=log,stderr=subprocess.STDOUT,text=True,timeout=1800)
  text=(out/f'sim_{i}.log').read_text()
  if r.returncode or 'PHOTO_COMPACT_EQUIVALENCE_PASS' not in text:raise AssertionError(text)
  print(text.strip(),flush=True);records.append(params)
 if frozen!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}:raise RuntimeError('changed tested sources')
 (out/'result.json').write_text(json.dumps(dict(status='PHOTO_COMPACT_FUNCTIONAL_EQUIVALENCE_PASS_NOT_ROUTED',simulator=a.simulator,records=records,hashes=frozen),indent=2))
if __name__=='__main__':main()
