"""Research two FPGA-only classes from CCL geometry/projection features.

Labels are unchanged; point is unsupported and evaluated as rejection, not
silently relabelled as fist. Report failures, no perfect-result requirement.
"""
import argparse,csv,json,hashlib
from collections import Counter,deque,defaultdict
from pathlib import Path
from test_hand_blob_scan import ROOT

def classify(c):
 area,w,h,rows=(int(c[k]) for k in ('area','w','h','row3'))
 box=w*h
 if area>=200 and rows>=3 and rows*8>=h and h*5>=w*4 and area*100<=57*box and area*100>=30*box:
  return 3
 if area>=200 and area*2>=box and h*10>=w*9 and h<=2*w and rows*8<h:
  return 1
 # Closing often joins a tilted closed hand into one compact grown region;
 # retain that mode-specific solid-body route without accepting fragmented
 # horizontal seed texture as a hand.
 if int(c['mode'])==1 and area>=300 and area*100>=65*box and rows*8<h:
  return 1
 return 0

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--input',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 a.out.mkdir(parents=True,exist_ok=False);rows=list(csv.DictReader((a.input/'all_candidates.csv').open()));groups=defaultdict(list)
 for c in rows:groups[(c['dataset'],int(c['frame']))].append(c)
 scores=[];trace=[]
 for ds,frames,lp in [('old',870,'hand_hdmi_20261017_labels.json'),('new',818,'hand_hdmi_162050_labels_audited.json')]:
  labels=json.loads((ROOT/'host/tests'/lp).read_text());votes=deque(maxlen=5);held=miss=0
  for frame in range(frames):
   qualified=[(int(c['score']),c,raw) for c in groups[(ds,frame)] if (raw:=classify(c))]
   best=max(qualified,key=lambda v:(v[0],-int(v[1]['anchor_key']),-int(v[1]['mode']))) if qualified else None
   raw=best[2] if best else 0;votes.append(raw)
   if not raw:
    miss+=1
    if miss>=5:held=0;votes.clear()
   else:
    miss=0;v,n=Counter(votes).most_common(1)[0]
    if v and n>=(2 if not held else 3):held=v
   label=next((s['id'] for s in labels['segments'] if s['start']<=frame<=s['end']),-1)
   expected=0 if label==2 else label
   trace.append(dict(dataset=ds,frame=frame,label=label,expected=expected,id=held,raw=raw,best=best[1] if best else None))
  for label in (0,1,2,3):
   selected=[r for r in trace if r['dataset']==ds and r['label']==label]
   scores.append(dict(dataset=ds,label=label,frames=len(selected),correct=sum(r['id']==r['expected'] for r in selected),failures=[r for r in selected if r['id']!=r['expected']]))
 (a.out/'result.json').write_text(json.dumps(dict(status='BINARY_RULE_RESEARCH_NOT_RTL_OR_BOARD',scores=scores,
  input_sha256=hashlib.sha256((a.input/'all_candidates.csv').read_bytes()).hexdigest(),rule_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()),indent=2))
 (a.out/'trace.json').write_text(json.dumps(trace))
 print(json.dumps([{k:v[k] for k in ('dataset','label','correct','frames')} for v in scores],indent=2))
if __name__=='__main__':main()
