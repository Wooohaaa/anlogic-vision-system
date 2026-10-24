"""Verify completed dataset prefix, or independently replay a dataset boundary.

No prior ID/background/white-balance state is injected. Replays require the
selected dataset's first vector to assert hardware clear.
"""
import argparse,hashlib,json,re,subprocess,time
from pathlib import Path
from test_hand_frame_classifier import ROOT,SOURCES
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def source_hashes(prepared):
 compile_path=prepared/'compile.log';text=compile_path.read_text(errors='replace')
 assert 'Errors: 0, Warnings: 0' in text
 hashes={}
 for name in SOURCES:
  path=ROOT/name;assert path.stat().st_mtime<=compile_path.stat().st_mtime,(name,'changed since compile')
  hashes[name]=sha(path)
 return hashes
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('mode',choices=('prefix','replay'))
 p.add_argument('--prepared',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
 p.add_argument('--first',type=int,default=0);p.add_argument('--count',type=int,required=True);a=p.parse_args()
 prepared=a.prepared.resolve();expected=json.loads((prepared/'expected.json').read_text());hashes=source_hashes(prepared)
 if a.mode=='prefix':
  assert a.first==0 and not a.out.exists();text=(prepared/'sim.log').read_text(errors='replace')
  rows=[tuple(map(int,m)) for m in re.findall(r'(?:^|\n)(?:# )?FRAME (\d+) (\d+) (\d+) (\d+)',text)]
  assert len(rows)>=a.count
  for i,(frame,id,raw,cycles) in enumerate(rows[:a.count]):assert (frame,id,raw)==(i,expected[i]['id'],expected[i]['raw'])
  selected=expected[:a.count];old=[r for r in selected if r['name'].startswith('hand_hdmi_20261017_')]
  assert len(old)==870 and [r['name'] for r in old]==[f'hand_hdmi_20261017_{i}' for i in range(870)]
  result=dict(status='OLD_VIDEO_PREFIX_RTL_VERIFIED_COMBINED_RUN_NOT_COMPLETE',frames=a.count,old_video_frames=len(old),
   simulator='modelsim',max_cycles=max(r[3] for r in rows[:a.count]),hashes=hashes,
   evidence={str((prepared/f).relative_to(ROOT)):sha(prepared/f) for f in ('compile.log','frames.txt','masks.bin','expected.json')},
   note='Every FRAME marker follows the testbench geometry/policy/vote/result assertions. The later combined run is intentionally split, not claimed fully passed.')
  a.out.write_text(json.dumps(result,indent=2));print(result['status'],a.count);return
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve();raw_lines=(prepared/'frames.txt').read_text().splitlines()
 frames=[];cursor=0
 while cursor<len(raw_lines):
  n=int(raw_lines[cursor].split()[1]);frames.append(raw_lines[cursor:cursor+n+1]);cursor+=n+1
 selected=frames[a.first:a.first+a.count];assert len(selected)==a.count and int(selected[0][0].split()[0])==1
 vector=out/'frames.txt';vector.write_text('\n'.join(line for frame in selected for line in frame)+'\n')
 binary=out/'masks.bin';original=(prepared/'masks.bin').read_bytes();binary.write_bytes(original[a.first*9720:(a.first+a.count)*9720])
 frozen={k:sha(ROOT/k) for k in SOURCES};frozen[str(Path(__file__).relative_to(ROOT))]=sha(Path(__file__))
 model=Path('C:/intelFPGA/20.1/modelsim_ase/win32aloem')
 for cmd in ([str(model/'vlib.exe'),'work'],[str(model/'vlog.exe'),'-sv','-work','work']+[str(ROOT/s) for s in SOURCES]):
  z=subprocess.run(cmd,cwd=out,capture_output=True,text=True);(out/('vlog.log' if 'vlog.exe' in cmd[0] else 'vlib.log')).write_text(z.stdout+z.stderr)
  if z.returncode:raise RuntimeError(z.stdout+z.stderr)
 run=[str(model/'vsim.exe'),'-c','-onfinish','exit','work.tb_hand_frame_classifier',f'+VECTORS={vector}',f'+MASKS={binary}',
      '-do','onerror {quit -code 1}; run -all; quit -code 0']
 began=time.monotonic()
 with (out/'sim.log').open('w') as log:
  process=subprocess.Popen(run,cwd=out,stdout=log,stderr=subprocess.STDOUT);print(f'REPLAY_RUNNING pid={process.pid} frames={a.count}',flush=True)
  code=process.wait(timeout=3600)
 text=(out/'sim.log').read_text(errors='replace')
 if code or 'HAND_FRAME_CLASSIFIER_PASS' not in text:raise AssertionError(text[-4000:])
 assert frozen=={k:sha(ROOT/k) for k in frozen}
 rows=[tuple(map(int,m)) for m in re.findall(r'(?:^|\n)(?:# )?FRAME (\d+) (\d+) (\d+) (\d+)',text)]
 assert len(rows)==a.count
 for i,(frame,id,raw,cycles) in enumerate(rows):assert (frame,id,raw)==(i,expected[a.first+i]['id'],expected[a.first+i]['raw'])
 result=dict(status='DATASET_FRAME_GEOMETRY_POLICY_VOTE_RTL_PASS_SOFTWARE_MASK_CANDIDATE_INPUT',first=a.first,frames=a.count,
  seconds=time.monotonic()-began,min_cycles=min(r[3] for r in rows),max_cycles=max(r[3] for r in rows),hashes=frozen,
  inputs={str((prepared/f).relative_to(ROOT)):sha(prepared/f) for f in ('frames.txt','masks.bin','expected.json')})
 (out/'result.json').write_text(json.dumps(result,indent=2));print(result['status'],a.count,flush=True)
if __name__=='__main__':main()
