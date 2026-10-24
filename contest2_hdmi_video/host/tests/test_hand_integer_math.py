"""Exhaustive 16-bit radicands plus 32-bit edge/random sqrt and divide."""
import argparse,hashlib,json,math,random,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SOURCES=['host/tests/tb_hand_integer_math.sv','rtl/user/ua_hand_integer_math.v']
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve();frozen={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}
 rows=[]
 def add_sqrt(x):
  q=math.isqrt(x);rows.append((1,x,0,q,x-q*q,0))
 def add_div(x,y):
  q,r=divmod(x,y) if y else (0,0);rows.append((0,x,y,q,r,int(y==0)))
 for x in range(65536):add_sqrt(x)
 for root in range(256,65536,131):
  for d in (-1,0,1):
   x=root*root+d
   if 0<=x<=0xffffffff:add_sqrt(x)
 for x in [0,1,2,3,0x7fffffff,0x80000000,0xfffffffe,0xffffffff]:
  add_sqrt(x)
  for y in [0,1,2,3,7,0xffff,0x10000,0x7fffffff,0x80000000,0xffffffff]:add_div(x,y)
 rng=random.Random(418041)
 for _ in range(2000):
  x=rng.getrandbits(32);add_sqrt(x);add_div(x,rng.getrandbits(32));add_div(x,rng.randrange(1,65536))
 vectors=out/'vectors.txt';vectors.write_text('\n'.join(f'{op} {x:08x} {y:08x} {q:08x} {r:08x} {fault}' for op,x,y,q,r,fault in rows)+'\n')
 exe=out/'math.vvp';r=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s','tb_hand_integer_math','-o',str(exe)]+SOURCES,cwd=ROOT,capture_output=True,text=True)
 (out/'compile.log').write_text(r.stdout+r.stderr)
 if r.returncode:raise RuntimeError(r.stderr)
 r=subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe),f'+INPUT={vectors}'],cwd=ROOT,capture_output=True,text=True,timeout=120)
 (out/'sim.log').write_text(r.stdout+r.stderr)
 if r.returncode or 'HAND_INTEGER_MATH_PASS' not in r.stdout:raise AssertionError(r.stdout+r.stderr)
 if frozen!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}:raise RuntimeError('changed tested source')
 (out/'result.json').write_text(json.dumps(dict(status='HAND_INTEGER_MATH_RTL_PASS_NOT_INTEGRATED',tests=len(rows),hashes=frozen),indent=2));print(r.stdout)
if __name__=='__main__':main()
