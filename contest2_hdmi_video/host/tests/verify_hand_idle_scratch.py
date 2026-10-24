"""Verify current-source idle scratch regressions and micro synthesis receipts."""
import argparse,hashlib,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 if a.out.exists():raise FileExistsError(a.out)
 hashes={};tests={}
 for name,folder,status in [
  ('shape','classifier_idle_scratch','SELECTED_COMPONENT_CLASSIFIER_PASS_NOT_FULL_VIDEO_SIGNOFF'),
  ('frame_faults','frame_idle_scratch_enabled','FRAME_CLASSIFIER_FAULT_RECOVERY_PASS'),
  ('frame_default_modelsim','frame_idle_scratch_default_modelsim','FRAME_GEOMETRY_POLICY_VOTE_RTL_PASS_SOFTWARE_MASK_CANDIDATE_INPUT'),
  ('actual_rgb_red_ccL','chain_actual_rgb_shared_red','SELECTED_VIDEO_RGB_SHARED_SCRATCH_RED_CCL_PASS_NOT_CLASSIFIER')]:
  path=ROOT/'tmp/hand_rtl'/folder/'result.json';receipt=json.loads(path.read_text())
  if receipt['status']!=status:raise RuntimeError((name,receipt['status']))
  for source,expected in receipt['hashes'].items():
   if sha(ROOT/source)!=expected:raise RuntimeError('stale input '+source)
   hashes[source]=expected
  if name in ('shape','frame_faults') and receipt['external_scratch']!=1:raise RuntimeError('disabled scratch test')
  tests[name]=dict(path=str(path.relative_to(ROOT)),sha256=sha(path),status=status)
 resources={}
 for variant,suffix,marker in [
  ('disabled','baseline_gate','HAND_SHAPE_CLASSIFIER_IDLE_SCRATCH_BASELINE_MICRO_SYNTH_COMPLETE'),
  ('enabled','gate','HAND_SHAPE_CLASSIFIER_IDLE_SCRATCH_MICRO_SYNTH_COMPLETE')]:
  stem='shape_classifier_idle_scratch_'+suffix
  area=ROOT/'tmp/hand_rtl'/(stem+'.area');log=area.with_suffix('.log')
  report=area.read_text();text=log.read_text()
  if marker not in text:raise RuntimeError('missing final synthesis marker')
  if re.search(r'ERROR:|unknown module|is a black box',text,re.I):raise RuntimeError('synthesis errors')
  for source in list(hashes)+['host/tests/hand_shape_classifier_micro.v']:
   if (ROOT/source).suffix=='.v' and (ROOT/source).stat().st_mtime>log.stat().st_mtime:raise RuntimeError('source newer than synthesis '+source)
  resources[variant]={key:int(re.search(pattern,report).group(1)) for key,pattern in
   [('slice',r'#slice\*\s+(\d+)'),('eram',r'#eram\s+(\d+)'),('dsp',r'#dsp\s+(\d+)')]}
  resources[variant].update(area_sha256=sha(area),log_sha256=sha(log))
 if resources['enabled']['eram']!=resources['disabled']['eram']:raise RuntimeError('additional frame RAM')
 for source in ['host/tests/hand_shape_classifier_micro.v','tools/measure_hand_shape_classifier_scratch.tcl','tools/measure_hand_shape_classifier_scratch_baseline.tcl']:
  hashes[source]=sha(ROOT/source)
 result=dict(status='IDLE_SCRATCH_REUSE_VERIFIED_NOT_RGB_CHAIN_OR_BOARD_SIGNOFF',tests=tests,
  resources=resources,additional_slice=resources['enabled']['slice']-resources['disabled']['slice'],hashes=hashes)
 a.out.write_text(json.dumps(result,indent=2));print(json.dumps(dict(status=result['status'],resources=resources,additional_slice=result['additional_slice']),indent=2))
if __name__=='__main__':main()
