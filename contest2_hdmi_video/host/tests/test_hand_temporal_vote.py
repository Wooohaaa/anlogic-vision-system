"""All four-ID sequences through length 8, video raw traces and tie rules."""
from collections import Counter,deque
import argparse,csv,hashlib,itertools,json,random,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SOURCES=['host/tests/tb_hand_temporal_vote.sv','rtl/user/ua_hand_temporal_vote.v']
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve();hashes={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES+[str(Path(__file__).relative_to(ROOT))]}
 lines=[];votes=deque(maxlen=5);held=miss=0;rng=random.Random(418122);input_hashes={};video_frames=0
 def frame(raw,present,clear=False):
  nonlocal held,miss
  if clear:votes.clear();held=miss=0
  votes.append(raw)
  if not raw:
   miss+=1
   if miss>=5:held=0;votes.clear()
  else:
   miss=0;v,n=Counter(votes).most_common(1)[0]
   if v and n>=(2 if not held else 3):held=v
  lines.append(f'{raw} {int(present)} {int(clear)} {held} {int(present and held!=0)}')
 # Exhaustive short histories include re-entry after five misses and ties.
 for sequence in itertools.product(range(4),repeat=8):
  for i,raw in enumerate(sequence):frame(raw,bool(rng.randrange(2)),clear=i==0)
 for i in range(10000):frame(rng.randrange(4),bool(rng.randrange(2)),clear=i%113==0)
 for folder in ('old_baseline','new_baseline'):
  path=ROOT/'tmp/hand_fixed_native_20261018'/folder/'results.csv';input_hashes[str(path.relative_to(ROOT))]=hashlib.sha256(path.read_bytes()).hexdigest()
  for i,row in enumerate(csv.DictReader(path.open())):
   frame(int(row['candidate']),bool(row['best']),clear=i==0);video_frames+=1
 vector=out/'frames.txt';vector.write_text('\n'.join(lines)+'\n');exe=out/'vote.vvp'
 z=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s','tb_hand_temporal_vote','-o',str(exe)]+SOURCES,cwd=ROOT,capture_output=True,text=True);(out/'compile.log').write_text(z.stdout+z.stderr)
 if z.returncode:raise RuntimeError(z.stderr)
 z=subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe),f'+INPUT={vector}'],cwd=ROOT,capture_output=True,text=True,timeout=120);(out/'sim.log').write_text(z.stdout+z.stderr)
 if z.returncode or 'HAND_TEMPORAL_VOTE_PASS' not in z.stdout:raise AssertionError(z.stdout+z.stderr)
 if hashes!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in hashes}:raise RuntimeError('source changed')
 (out/'result.json').write_text(json.dumps(dict(status='TEMPORAL_VOTE_PASS_RAW_INPUT_NOT_VIDEO_RECOGNITION_SIGNOFF',tests=len(lines),video_frames=video_frames,hashes=hashes,input_hashes=input_hashes),indent=2));print(z.stdout)
if __name__=='__main__':main()
