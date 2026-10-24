"""Audit paired geometry regression, measured resource delta and source freshness."""
import argparse,hashlib,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 if a.out.exists():raise FileExistsError(a.out)
 base=ROOT/'tmp/hand_rtl';folders=[base/'geometry_shared_watchdog_fixed',base/'geometry_private_reference']
 reports=[json.loads((f/'result.json').read_text()) for f in folders]
 for report in reports:
  assert report['status']=='SHARED_GEOMETRY_CHAIN_PASS_NOT_GESTURE_SIGNOFF'
  for source,expected in report['hashes'].items():assert sha(ROOT/source)==expected,source
 assert [r['shared_memory'] for r in reports]==[1,0]
 assert reports[0]['records']==reports[1]['records']
 assert reports[0]['hashes']==reports[1]['hashes']
 timelines=[]
 for folder in folders:
  t={}
  for log in folder.glob('*.log'):
   m=re.search(r'HAND_GEOMETRY_SHARED_PASS cycles=(\d+) vertices=(\d+) fault=(\d+)',log.read_text())
   if m:t[log.name]=tuple(map(int,m.groups()))
  timelines.append(t)
 assert timelines[0]==timelines[1] and len(timelines[0])==reports[0]['tests'],'latency/results differ'
 usages=[];artifacts={}
 for kind in ('shared','private'):
  area=base/f'geometry_{kind}_gate.area';log=base/f'geometry_{kind}_gate.log'
  assert f'HAND_GEOMETRY_{kind.upper()}_MICRO_SYNTH_COMPLETE' in log.read_text()
  assert not re.search(r'\bERROR\b',log.read_text())
  text=area.read_text();usage={}
  for resource in ('slice','eram','dsp','reg'):
   m=re.search(r'(?m)^#'+resource+r'\*?\s+(\d+)',text);assert m,resource;usage[resource]=int(m.group(1))
  usages.append(usage)
  for f in (area,log):artifacts[str(f.relative_to(ROOT))]=sha(f)
  # The measured translation unit and tested core inputs predate the report.
  for source in list(reports[0]['hashes'])+[str(Path('host/tests/hand_geometry_micro.v'))]:
   if source.endswith('.v'):assert (ROOT/source).stat().st_mtime<=area.stat().st_mtime,source
 shared,private=usages
 assert shared['eram']<=private['eram']-4
 assert shared['dsp']==private['dsp']
 result=dict(status='GEOMETRY_MEMORY_REUSE_VERIFIED_NOT_WHOLE_PROJECT',tests=reports[0]['tests'],
  identical_tested_latency=True,shared=shared,private=private,
  delta={k:shared[k]-private[k] for k in shared},
  source_hashes=reports[0]['hashes'],artifact_hashes=artifacts,
  caveat='Micro Optimize Gate, no board IO constraints or routed timing; not a gesture classifier qualification')
 a.out.parent.mkdir(parents=True,exist_ok=True);a.out.write_text(json.dumps(result,indent=2))
 print(json.dumps({k:v for k,v in result.items() if k not in ('source_hashes','artifact_hashes')}))
if __name__=='__main__':main()
