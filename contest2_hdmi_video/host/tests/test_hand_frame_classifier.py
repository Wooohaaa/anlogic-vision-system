"""All actual geometry/policy/vote in RTL; software masks and candidate association.

Do not label this as RGB->full-system RTL or a board test. Candidate list,
red sums and final masks are supplied by independent image reference here.
"""
from collections import Counter,deque
import argparse,csv,hashlib,json,re,subprocess,sys,time
from pathlib import Path
import cv2
import numpy as np
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'host'))
from hand_fixed_classifier import features
from hand_fpga_grid_model import masks,candidates
from test_hand_blob_scan import pack
from test_hand_frame_policy import winner
from test_hand_shape_classifier import RTL as SHAPE_RTL
RTL=SHAPE_RTL+['ua_hand_frame_classifier.v','ua_hand_frame_policy.v','ua_hand_temporal_vote.v']
SOURCES=['host/tests/tb_hand_frame_classifier.sv']+['rtl/user/'+s for s in RTL]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);p.add_argument('--video',action='store_true');p.add_argument('--limit',type=int,default=0)
 p.add_argument('--simulator',choices=('iverilog','modelsim'),default='modelsim');a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve();frozen={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES+[
  str(Path(__file__).relative_to(ROOT)),'host/hand_fixed_classifier.py','host/hand_fpga_grid_model.py','host/tests/test_hand_frame_policy.py']}
 frames=[];input_hashes={};datasets=[]
 def add(name,seed,grown,r,g,b,regions,clear=False):
  frame_jobs=[];policy_rows=[]
  _,grown_labels,_,_=cv2.connectedComponentsWithStats(grown.astype(np.uint8),8)
  for region,x,y,w,h,area in regions:
   yy,xx=np.nonzero(region);ay=int(yy.min());ax=int(xx[yy.argmin()]);gid=int(grown_labels[ay,ax])
   mode=int(gid!=0 and np.array_equal(region,grown_labels==gid));red_sum=int(r[region].sum())
   f=features(region[y:y+h,x:x+w].astype(np.uint8)) if 0<area<=2500 else None
   # All cheap-rejected candidates may still be fed: RTL must filter them.
   frame_jobs.append((mode,x,y,w,h,ax,ay,area,red_sum))
   if f:policy_rows.append((x,y,w,h,*f['center'],area,red_sum,f['radius_q4'],f['raw'],f['tips']))
  bright=int(((r>=960)&(g>=960)&(b>=960)).sum())
  frames.append(dict(name=name,seed=seed,grown=grown,jobs=frame_jobs,rows=policy_rows,bright=bright,clear=clear))
 for gesture,count in ((1,0),(2,1),(3,3),(0,-1)):
  for frame in range(7):
   m=np.zeros((90,160),np.uint8)
   if count>=0:
    cv2.rectangle(m,(50,44),(95,70),1,-1);cv2.rectangle(m,(69,65),(84,89),1,-1)
    for k in range(count):cv2.rectangle(m,(50+k*9,10+(k%3)*6),(54+k*9,49),1,-1)
   n,labels,stats,_=cv2.connectedComponentsWithStats(m,8);regions=[]
   for k in range(1,n):
    x,y,w,h,area=map(int,stats[k]);regions.append((labels==k,x,y,w,h,area))
   r=np.full((90,160),160,np.int32);add(f'synthetic_{gesture}_{frame}',m,m,r,r//2,r//4,regions,clear=not frames)
 if a.video:
  for folder in ('hand_hdmi_20261017','hand_hdmi_162050'):
   path=ROOT/'tmp'/folder/'native/groups.bin';input_hashes[str(path.relative_to(ROOT))]=hashlib.sha256(path.read_bytes()).hexdigest()
   words=np.memmap(path,dtype='>u4',mode='r').reshape(-1,180,320);start=len(frames)
   for frame,packed in enumerate(words):
    if a.limit and frame>=a.limit:break
    rgb=[((packed>>s)&1023).astype(np.int32) for s in (20,10,0)]
    r,g,b=[(v[1::2,::2]+v[1::2,1::2])>>1 for v in rgb];seed,grown=masks(r,g,b)
    # The 16-entry reference list is not replaced by largest-blob selection.
    add(f'{folder}_{frame}',seed,grown,r,g,b,candidates(r,g,b),clear=frame==0)
    if frame%200==0:print(f'classifier vectors {folder} frame={frame}',flush=True)
   datasets.append(dict(name=folder,first=start,frames=len(frames)-start))
 vector=out/'frames.txt';binary=out/'masks.bin';lines=[];backlit=False;votes=deque(maxlen=5);held=miss=0;expected=[]
 with binary.open('wb') as stream:
  for frame in frames:
   if frame['clear']:backlit=False;votes.clear();held=miss=0
   best=winner(frame['rows'],backlit);raw=best[1][9] if best else 0;votes.append(raw)
   if not raw:
    miss+=1
    if miss>=5:held=0;votes.clear()
   else:
    miss=0;v,n=Counter(votes).most_common(1)[0]
    if v and n>=(2 if not held else 3):held=v
   if frame['bright']>=450:backlit=True
   elif frame['bright']<225:backlit=False
   if best:
    _,c,mean=best;x,y,w,h,_,_,_,_,radius,_,tips=c
   else:x=y=w=h=radius=mean=tips=0
   box=int(best is not None and held!=0)
   lines.append(' '.join(map(str,(int(frame['clear']),len(frame['jobs']),frame['bright'],held,raw,box,tips,x,y,w,h,radius,mean))))
   lines.extend(' '.join(map(str,c)) for c in frame['jobs']);expected.append(dict(name=frame['name'],id=held,raw=raw))
   stream.write(np.array(pack(frame['seed'],frame['grown']),dtype='>u4').tobytes())
 vector.write_text('\n'.join(lines)+'\n');(out/'expected.json').write_text(json.dumps(expected))
 for dataset in datasets:
  old=dataset['name']=='hand_hdmi_20261017';cache=ROOT/'tmp/hand_fixed_native_20261018'/('old_baseline' if old else 'new_baseline')
  cache_result=json.loads((cache/'result.json').read_text())
  assert cache_result['algorithm_sha256']==frozen['host/hand_fixed_classifier.py'],'stale cached baseline'
  cp=cache/'results.csv';cached=list(csv.DictReader(cp.open()));input_hashes[str(cp.relative_to(ROOT))]=hashlib.sha256(cp.read_bytes()).hexdigest()
  actual=expected[dataset['first']:dataset['first']+dataset['frames']]
  assert [(r['id'],r['raw']) for r in actual]==[(int(r['id']),int(r['candidate'])) for r in cached[:len(actual)]],dataset['name']+' reference drift'
  lp=ROOT/'host/tests'/('hand_hdmi_20261017_labels.json' if old else 'hand_hdmi_162050_labels_audited.json')
  labels=json.loads(lp.read_text());input_hashes[str(lp.relative_to(ROOT))]=hashlib.sha256(lp.read_bytes()).hexdigest()
  scored=correct=0
  for segment in labels['segments']:
   for index in range(segment['start'],min(segment['end']+1,len(actual))):
    scored+=1;correct+=actual[index]['id']==segment['id']
  dataset.update(scored_frames=scored,reference_correct=correct)
 if a.simulator=='iverilog':
  exe=out/'frame.vvp';cmd=['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s','tb_hand_frame_classifier','-o',str(exe)]+SOURCES
  z=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True);(out/'compile.log').write_text(z.stdout+z.stderr)
  if z.returncode:raise RuntimeError(z.stderr)
  run=['C:/iverilog/bin/vvp.exe',str(exe),f'+VECTORS={vector}',f'+MASKS={binary}'];run_cwd=ROOT
 else:
  model=Path('C:/intelFPGA/20.1/modelsim_ase/win32aloem')
  z=subprocess.run([str(model/'vlib.exe'),'work'],cwd=out,capture_output=True,text=True)
  if z.returncode:raise RuntimeError(z.stdout+z.stderr)
  z=subprocess.run([str(model/'vlog.exe'),'-sv','-work','work']+[str(ROOT/s) for s in SOURCES],cwd=out,capture_output=True,text=True);(out/'compile.log').write_text(z.stdout+z.stderr)
  if z.returncode:raise RuntimeError(z.stdout+z.stderr)
  run=[str(model/'vsim.exe'),'-c','-onfinish','exit','work.tb_hand_frame_classifier',f'+VECTORS={vector}',f'+MASKS={binary}',
       '-do','onerror {quit -code 1}; run -all; quit -code 0'];run_cwd=out
 begin=time.monotonic()
 with (out/'sim.log').open('w') as log:
  process=subprocess.Popen(run,cwd=run_cwd,stdout=log,stderr=subprocess.STDOUT)
  print(f'frame RTL running pid={process.pid} frames={len(frames)} simulator={a.simulator}',flush=True)
  try:code=process.wait(timeout=1800)
  except subprocess.TimeoutExpired:
   process.terminate();process.wait();raise
 text=(out/'sim.log').read_text(errors='replace')
 if code or 'HAND_FRAME_CLASSIFIER_PASS' not in text:raise AssertionError(text[-4000:])
 if frozen!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in frozen}:raise RuntimeError('tested source changed')
 cycles=[int(v) for v in re.findall(r'(?:^|\n)(?:# )?FRAME \d+ \d+ \d+ (\d+)',text)]
 assert len(cycles)==len(frames)
 (out/'result.json').write_text(json.dumps(dict(status='FRAME_GEOMETRY_POLICY_VOTE_RTL_PASS_SOFTWARE_MASK_CANDIDATE_INPUT',
  frames=len(frames),datasets=datasets,simulator=a.simulator,seconds=time.monotonic()-begin,min_cycles=min(cycles),max_cycles=max(cycles),
  hashes=frozen,input_hashes=input_hashes),indent=2));print(f'FRAME_GEOMETRY_POLICY_VOTE_RTL_PASS frames={len(frames)}',flush=True)
if __name__=='__main__':main()
