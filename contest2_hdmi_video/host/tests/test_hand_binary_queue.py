"""Controller queue stress only; image evidence is the separate RGB test."""
import hashlib,json,subprocess,argparse
from pathlib import Path
from test_hand_blob_scan import ROOT
SOURCES=['host/tests/tb_hand_binary_queue.sv']+['rtl/user/'+v for v in (
 'ua_hand_binary_native.v','ua_hand_binary_shape.v','ua_hand_mask_frame.v',
 'ua_hand_blob_scan.v','ua_hand_scratch_ram.v','ua_hand_component_mask.v',
 'ua_hand_product_serial.v','ua_hand_integer_math.v','ua_hand_temporal_vote.v')]
def main():
 p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve()
 hashes={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}
 model=Path('C:/intelFPGA/20.1/modelsim_ase/win32aloem')
 for name,args in [('vlib',['work']),('vlog',['-sv','-work','work']+[str(ROOT/s) for s in SOURCES]),
  ('vsim',['-c','-onfinish','exit','work.tb_hand_binary_queue','-do','onerror {quit -code 1}; run -all; quit -code 0'])]:
  z=subprocess.run([str(model/(name+'.exe'))]+args,cwd=out,capture_output=True,text=True,timeout=120)
  text=z.stdout+z.stderr;(out/(name+'.log')).write_text(text)
  if z.returncode or (name=='vsim' and 'HAND_BINARY_QUEUE_BOUNDARY_PASS' not in text):raise AssertionError(text[-4000:])
 if hashes!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}:raise RuntimeError('inputs changed')
 (out/'result.json').write_text(json.dumps(dict(status='BINARY_QUEUE_PROTOCOL_RTL_PASS_NOT_VIDEO',hashes=hashes),indent=2))
 print('BINARY_QUEUE_PROTOCOL_RTL_PASS_NOT_VIDEO')
if __name__=='__main__':main()
