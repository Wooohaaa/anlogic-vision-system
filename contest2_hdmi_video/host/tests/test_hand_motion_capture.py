"""Native motion-adapter timing plus actual capture RGB and deployed hand RTL."""
import argparse,subprocess,json,hashlib
from pathlib import Path
from test_hand_blob_scan import ROOT
from test_hand_binary_queue import SOURCES as QUEUE
def main():
 p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);p.add_argument('--preroll',type=int,default=0);a=p.parse_args();a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve()
 sources=['host/tests/tb_hand_motion_capture.sv','rtl/user/ua_motion_detect.v','rtl/user/ua_motion_ref_ram.v']+QUEUE[1:]
 path=ROOT/'tmp/hand_hdmi_20261019_131143/native/groups.bin'
 hashes={str(s):hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in sources}
 model=Path('C:/intelFPGA/20.1/modelsim_ase/win32aloem')
 for tool,args in [('vlib',['work']),('vlog',['-sv','-work','work']+[str(ROOT/s) for s in sources]),('vsim',['-c','-onfinish','exit','work.tb_hand_motion_capture',f'+INPUT={path}',f'+PREROLL={a.preroll}','-do','onerror {quit -code 1}; run -all; quit -code 0'])]:
  z=subprocess.run([str(model/(tool+'.exe'))]+args,cwd=out,capture_output=True,text=True,timeout=600);text=z.stdout+z.stderr;(out/(tool+'.log')).write_text(text)
  if z.returncode or (tool=='vsim' and 'HAND_MOTION_CAPTURE_INTEGRATION_PASS' not in text):raise RuntimeError(text[-4500:])
 if hashes!={str(s):hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in sources}:raise RuntimeError('Inputs changed')
 (out/'result.json').write_text(json.dumps(dict(status='MOTION_CAPTURE_RGB_HAND_RTL_INTEGRATION_PASS_NOT_BOARD',preroll=a.preroll,hashes=hashes,input_sha256=hashlib.sha256(path.read_bytes()).hexdigest()),indent=2))
 print('MOTION_CAPTURE_RGB_HAND_RTL_INTEGRATION_PASS_NOT_BOARD')
if __name__=='__main__':main()
