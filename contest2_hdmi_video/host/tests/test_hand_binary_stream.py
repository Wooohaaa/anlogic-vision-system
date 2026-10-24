"""Continuous true-RGB producer, explicit dropped detection frames and votes."""
import argparse,hashlib,json,re,subprocess
from collections import deque,Counter
from pathlib import Path
from test_hand_blob_scan import ROOT
from test_hand_binary_queue import SOURCES as QUEUE_SOURCES
SOURCES=['host/tests/tb_hand_binary_stream.sv']+QUEUE_SOURCES[1:]
def main():
 p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);p.add_argument('--equivalence',action='store_true');a=p.parse_args();a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve()
 sources=SOURCES+(['host/tests/reference/v47_resource/'+v for v in ('ua_hand_binary_native.v','ua_hand_binary_shape.v','ua_hand_mask_frame.v','ua_hand_scratch_ram.v')] if a.equivalence else [])
 evidence=sources+[str(Path(__file__).relative_to(ROOT))]
 hashes={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in evidence}
 source=ROOT/'tmp/hand_hdmi_20261017/native/groups.bin';digest=hashlib.sha256(source.read_bytes()).hexdigest()
 model=Path('C:/intelFPGA/20.1/modelsim_ase/win32aloem')
 for name,args in [('vlib',['work']),('vlog',['-sv','-work','work']+(['+define+COMPARE_V47'] if a.equivalence else [])+[str(ROOT/s) for s in sources]),
  ('vsim',['-c','-onfinish','exit','work.tb_hand_binary_stream',f'+INPUT={source}','-do','onerror {quit -code 1}; run -all; quit -code 0'])]:
  z=subprocess.run([str(model/(name+'.exe'))]+args,cwd=out,capture_output=True,text=True,timeout=600)
  text=z.stdout+z.stderr;(out/(name+'.log')).write_text(text)
  if z.returncode or (name=='vsim' and 'HAND_BINARY_CONTINUOUS_RGB_PASS' not in text):raise AssertionError(text[-4000:])
 accepted=deque();votes=deque(maxlen=5);held=miss=0;records=[]
 lookup=[(1,0,64,35,44,50),(3,3,45,16,77,70),(0,0,0,0,0,0)]
 for line in text.splitlines():
  m=re.search(r'STREAM_ACCEPT class=\s*(\d+) source=\s*(\d+)',line)
  if m:accepted.append(tuple(map(int,m.groups())))
  m=re.search(r'STREAM_RESULT id=\s*(\d+) raw=\s*(\d+) box=\s*(\d+) tips=\s*(\d+) x=\s*(\d+) y=\s*(\d+) w=\s*(\d+) h=\s*(\d+)',line)
  if not m:continue
  cls,frame=accepted.popleft();raw,tips,x,y,w,h=lookup[cls];votes.append(raw)
  if raw==0:
   miss+=1
   if miss>=5:held=0;votes.clear()
  else:
   miss=0;v,n=Counter(votes).most_common(1)[0]
   if v and n>=(2 if held==0 else 3):held=v
  expected=(held,raw,int(bool(raw and held)),tips,x,y,w,h);actual=tuple(map(int,m.groups()))
  if actual!=expected:raise AssertionError((frame,actual,expected))
  records.append(dict(source=frame,expected=expected))
 if accepted or held!=0 or len(records)<12:raise AssertionError('incomplete withdrawal/stream evidence')
 if hashes!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in evidence} or digest!=hashlib.sha256(source.read_bytes()).hexdigest():raise RuntimeError('changed inputs')
 status='CONTINUOUS_BINARY_RESOURCE_CYCLE_EQUIVALENCE_PASS_NOT_ROUTED' if a.equivalence else 'CONTINUOUS_TRUE_RGB_BINARY_RTL_PASS_NOT_BOARD'
 (out/'result.json').write_text(json.dumps(dict(status=status,source_frames=96,results=records,hashes=hashes,input_sha256=digest),indent=2));print(status,len(records))
if __name__=='__main__':main()
