"""Audit same-source parallel/serial classifier A/B, never whole-project signoff."""
import argparse,hashlib,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True)
 p.add_argument('--serial-folder',default='shape_classifier_serial_final');p.add_argument('--parallel-folder',default='shape_classifier_parallel_final');a=p.parse_args()
 if a.out.exists():raise FileExistsError(a.out)
 records=[];hashes={};areas=[];receipts=[]
 for parallel,folder,prefix,marker in (
  (0,a.serial_folder,'shape_classifier','HAND_SHAPE_CLASSIFIER_MICRO_SYNTH_COMPLETE'),
  (1,a.parallel_folder,'shape_classifier_parallel','HAND_SHAPE_CLASSIFIER_PARALLEL_MICRO_SYNTH_COMPLETE')):
  rp=ROOT/'tmp/hand_rtl'/folder/'result.json';receipt=json.loads(rp.read_text())
  assert receipt['status']=='SELECTED_COMPONENT_CLASSIFIER_PASS_NOT_FULL_VIDEO_SIGNOFF'
  assert receipt['parallel_compare']==parallel
  for name,digest in receipt['hashes'].items():
   assert sha(ROOT/name)==digest,(name,'stale tested source')
   if name in hashes:assert hashes[name]==digest
   hashes[name]=digest
  report=ROOT/'tmp/hand_rtl'/f'{prefix}_gate.area';log=report.with_suffix('.log')
  assert marker in log.read_text(errors='replace')
  assert not re.search(r'\bERROR\b',log.read_text(errors='replace'))
  text=report.read_text();assert 'PH1P35MDG324' in text
  area={key:int(re.search(r'^#'+pattern+r'\s+(\d+)',text,re.M)[1]) for key,pattern in
        (('slice',r'slice\*'),('eram','eram'),('dsp','dsp'),('ff','reg'),('io','IO'))}
  inputs=list(receipt['hashes'])+['host/tests/hand_shape_classifier_micro.v',
           'tools/measure_hand_shape_classifier_parallel.tcl' if parallel else 'tools/measure_hand_shape_classifier.tcl']
  # Testbench/model are not synthesized, so only RTL/include/Tcl timestamps gate freshness.
  for name in inputs:
   path=ROOT/name
   if path.suffix=='.v' or path.suffix=='.tcl':assert report.stat().st_mtime>=path.stat().st_mtime,(name,'stale synthesis')
  hashes.update({name:sha(ROOT/name) for name in inputs})
  areas.append(area);records.append(receipt['records']);receipts.append(str(rp.relative_to(ROOT)))
  hashes[str(report.relative_to(ROOT))]=sha(report);hashes[str(log.relative_to(ROOT))]=sha(log)
 def key(r):return tuple(r[k] for k in ('name','mode','abort','raw','tips'))
 assert [key(r) for r in records[0]]==[key(r) for r in records[1]]
 assert areas[0]['slice']<areas[1]['slice'] and areas[0]['eram']<=areas[1]['eram'] and areas[0]['dsp']<=areas[1]['dsp']
 assert areas[0]['io']==areas[1]['io']
 deltas=[]
 for serial,parallel in zip(*records):
  sc=int(re.search(r'cycles=(\d+)',serial['log'])[1]);pc=int(re.search(r'cycles=(\d+)',parallel['log'])[1])
  deltas.append(sc-pc)
 result=dict(status='CLASSIFIER_SERIAL_RESOURCE_AB_VERIFIED_NOT_WHOLE_PROJECT',tests_each=len(records[0]),
  serial=areas[0],parallel_reference=areas[1],slice_saved=areas[1]['slice']-areas[0]['slice'],
  cycle_delta_serial_minus_parallel=[min(deltas),max(deltas)],receipts=receipts,hashes=hashes,
  remaining=['RGB candidate confidence and candidate selection','seed/grown fallback and temporal voting',
             'both full-video RTL regressions and perturbations','production integration and whole-project resource closure',
             'final routed timing, bitgen and SRAM programming'])
 a.out.write_text(json.dumps(result,indent=2));print(json.dumps({k:v for k,v in result.items() if k not in ('hashes','remaining','receipts')}))
if __name__=='__main__':main()
