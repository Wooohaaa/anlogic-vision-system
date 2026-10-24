"""Read-only analysis of cached stress failures, not new recognition evidence."""
import argparse,csv,hashlib,json
from collections import Counter
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 if a.out.exists():raise FileExistsError(a.out)
 records=[];hashes={}
 for dataset,labels_name in (('old','hand_hdmi_20261017_labels.json'),('new','hand_hdmi_162050_labels_audited.json')):
  lp=ROOT/'host/tests'/labels_name;labels=json.loads(lp.read_text());hashes[str(lp.relative_to(ROOT))]=hashlib.sha256(lp.read_bytes()).hexdigest()
  folder=ROOT/'tmp/hand_fixed_native_20261018';base_path=folder/(dataset+'_baseline')/'results.csv'
  baseline=list(csv.DictReader(base_path.open()));hashes[str(base_path.relative_to(ROOT))]=hashlib.sha256(base_path.read_bytes()).hexdigest()
  for case in ('dim90','bright110','warm5','cool5','noise4','dim90_noise4'):
   path=folder/(dataset+'_'+case)/'results.csv';rows=list(csv.DictReader(path.open()));hashes[str(path.relative_to(ROOT))]=hashlib.sha256(path.read_bytes()).hexdigest()
   failure=[];counts=Counter()
   for segment in labels['segments']:
    for frame in range(segment['start'],segment['end']+1):
     row=rows[frame]
     if int(row['id'])==segment['id']:continue
     b=baseline[frame];geometry=json.loads(row['best']) if row['best'] else None
     reason='no_accepted_candidate' if geometry is None else 'raw_mismatch' if int(row['candidate'])!=segment['id'] else 'temporal_recovery'
     counts[reason]+=1
     failure.append(dict(frame=frame,label=segment['id'],segment=segment['name'],id=int(row['id']),raw=int(row['candidate']),
      baseline_raw=int(b['candidate']),reason=reason,geometry=geometry))
   records.append(dict(dataset=dataset,case=case,failures=len(failure),categories=dict(counts),frames=failure))
 result=dict(status='CACHED_SOFTWARE_STRESS_DIAGNOSTIC_NOT_RTL_OR_CAMERA_SIGNOFF',records=records,input_hashes=hashes)
 a.out.write_text(json.dumps(result,indent=2))
 print(json.dumps([{k:r[k] for k in ('dataset','case','failures','categories')} for r in records],indent=2))
if __name__=='__main__':main()
