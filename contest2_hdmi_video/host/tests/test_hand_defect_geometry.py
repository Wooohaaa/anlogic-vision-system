"""Real mask reads through shared geometry and ordered defects, no injected geometry."""
import argparse,hashlib,json,subprocess,sys
from pathlib import Path
import cv2
import numpy as np
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'host'))
from hand_fixed_classifier import integer_hull,contour_points
from test_hand_blob_scan import pack,unpack
from test_hand_palm_distance import reference
from test_hand_wrist_median import expected as wrist_reference
from test_hand_defect_scan import expected_edges
RTL=['ua_hand_defect_geometry.v','ua_hand_defect_scan.v','ua_hand_defect_edge.v','ua_hand_integer_math.v',
     'ua_hand_geometry_shared.v','ua_hand_scratch_ram.v','ua_hand_component_mask.v','ua_hand_palm_distance.v',
     'ua_hand_wrist_median.v','ua_hand_convex_hull.v','ua_hand_contour_trace.v']
SOURCES=['host/tests/tb_hand_defect_geometry.sv']+['rtl/user/'+s for s in RTL]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);out=a.out.resolve();frozen={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}
 exe=out/'chain.vvp';z=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-Wall','-s','tb_hand_defect_geometry','-o',str(exe)]+SOURCES,cwd=ROOT,capture_output=True,text=True)
 (out/'compile.log').write_text(z.stdout+z.stderr)
 if z.returncode:raise RuntimeError(z.stderr)
 scenes=[]
 for count in range(1,6):
  m=np.zeros((90,160),np.uint8);cv2.rectangle(m,(50,44),(95,70),1,-1);cv2.rectangle(m,(69,65),(84,89),1,-1)
  for x in range(count):cv2.rectangle(m,(50+x*9,10+(x%3)*6),(54+x*9,49),1,-1)
  scenes.append((f'fingers{count}',m,m))
 m=np.zeros((90,160),np.uint8);cv2.rectangle(m,(10,10),(25,25),1,-1);cv2.rectangle(m,(26,26),(40,40),1,-1);scenes.append(('articulation',m,m))
 m=np.zeros((90,160),np.uint8);cv2.rectangle(m,(10,10),(40,40),1,2);m[20:25,20:25]=1;scenes.append(('ring_unrelated',m,m))
 for folder in ('vectors_new','vectors_old'):
  for filename in sorted((ROOT/'tmp/hand_rtl'/folder).glob('frame_*.hex')):
   scenes.append((folder+'_'+filename.stem,*unpack([int(s,16) for s in filename.read_text().split()])))
 records=[]
 for name,seed,grown in scenes:
  for mode,m in enumerate((seed,grown)):
   n,labels,stats,_=cv2.connectedComponentsWithStats(m.astype(np.uint8),8)
   eligible=[k for k in range(1,n) if int(stats[k,4])<=2500]
   if not eligible:continue
   k=max(eligible,key=lambda k:int(stats[k,4]));x,y,w,h,area=map(int,stats[k]);yy,xx=np.nonzero(labels==k)
   ax=int(xx[yy.argmin()]);ay=int(yy.min());selected=(labels[y:y+h,x:x+w]==k).astype(np.uint8)
   _,cx,cy,r=reference(selected);wx,wy,_=wrist_reference(selected,cx,cy,r)
   points=contour_points(selected);edges=expected_edges(integer_hull(points),points,r)
   stem=f'{name}_{mode}';mp=out/(stem+'_mask.hex');ep=out/(stem+'_expected.txt');bp=out/(stem+'_bitmap.hex')
   mp.write_text(''.join(f'{v:05x}\n' for v in pack(seed,grown)));bp.write_text(''.join(f'{v:x}\n' for v in selected.flat))
   ep.write_text(' '.join(map(str,(x,y,w,h,ax,ay,mode,cx,cy,r,area,wx-2*cx,wy-2*cy,len(edges))))+'\n'+
                 ''.join(' '.join(map(str,e))+'\n' for e in edges))
   for abort in ([0,1,2,3] if name=='fingers3' and mode==1 else [0]):
    z=subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe),f'+MASK={mp}',f'+EXPECTED={ep}',f'+BITMAP={bp}',f'+ABORT={abort}'],cwd=ROOT,capture_output=True,text=True,timeout=120)
    (out/(stem+f'_abort{abort}.log')).write_text(z.stdout+z.stderr)
    if z.returncode or 'HAND_DEFECT_GEOMETRY_PASS' not in z.stdout:raise AssertionError(stem+': '+z.stdout+z.stderr)
    records.append(dict(name=name,mode=mode,abort=abort,edges=len(edges),area=area,log=z.stdout.strip()))
 if frozen!={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in SOURCES}:raise RuntimeError('source changed')
 (out/'result.json').write_text(json.dumps(dict(status='SHARED_DEFECT_GEOMETRY_CHAIN_PASS_NOT_CLASSIFIER_SIGNOFF',tests=len(records),hashes=frozen,records=records),indent=2));print(f'SHARED_DEFECT_GEOMETRY_CHAIN_PASS tests={len(records)}')
if __name__=='__main__':main()
