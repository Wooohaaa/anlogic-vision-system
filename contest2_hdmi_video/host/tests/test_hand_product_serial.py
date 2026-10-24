"""Full-width unsigned shift/add products, busy start and cancellation."""
import argparse,hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SOURCES=['host/tests/tb_hand_product_serial.sv','rtl/user/ua_hand_product_serial.v']
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--a-bits',type=int,default=32);p.add_argument('--b-bits',type=int,default=32);p.add_argument('--dsp',type=int,choices=(0,1),default=0);p.add_argument('--compact',type=int,choices=(0,1),default=1);a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve();frozen={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}
 exe=out/'product.vvp';z=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s','tb_hand_product_serial',f'-Ptb_hand_product_serial.A_BITS={a.a_bits}',f'-Ptb_hand_product_serial.B_BITS={a.b_bits}',f'-Ptb_hand_product_serial.HARD_MULTIPLY={a.dsp}',f'-Ptb_hand_product_serial.COMPACT={a.compact}','-o',str(exe)]+SOURCES,cwd=ROOT,capture_output=True,text=True)
 (out/'compile.log').write_text(z.stdout+z.stderr)
 if z.returncode:raise RuntimeError(z.stderr)
 z=subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe)],cwd=ROOT,capture_output=True,text=True,timeout=30);(out/'sim.log').write_text(z.stdout+z.stderr)
 if z.returncode or 'HAND_PRODUCT_SERIAL_PASS' not in z.stdout:raise AssertionError(z.stdout+z.stderr)
 if frozen!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}:raise RuntimeError('source changed')
 (out/'result.json').write_text(json.dumps(dict(status='PRODUCT_SERIAL_PASS',a_bits=a.a_bits,b_bits=a.b_bits,dsp=a.dsp,compact=a.compact,tests=2048,hashes=frozen),indent=2));print(z.stdout)
if __name__=='__main__':main()
