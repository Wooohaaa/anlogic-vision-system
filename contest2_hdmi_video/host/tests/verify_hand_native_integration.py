"""Audit the actual RGB RTL result AND failed full-project packing.

Successful behavioral evidence must never turn an over-capacity design into
a programming receipt. Production source selector must be restored to old=1.
"""
import argparse,hashlib,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def read_log(path):
 data=path.read_bytes()
 return data.decode('utf-16' if data[:2] in (b'\xff\xfe',b'\xfe\xff') else 'utf-8',errors='replace')
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 if a.out.exists():raise FileExistsError(a.out)
 tests={};source_hashes={}
 for folder,expected in [
  ('native_full_rgb_selected14','SELECTED_REAL_RGB_FULL_GESTURE_RTL_PASS_NOT_BOARD_SIGNOFF'),
  ('persistent_label_map_initial','PERSISTENT_LABEL_MAP_RTL_PASS_NOT_FULL_ASSOCIATION'),
  ('descriptor_build_association_initial','DESCRIPTOR_BUILD_ASSOCIATION_RTL_PASS_SOFTWARE_LABEL_MAP_AND_CCL_STATS'),
  ('association_query_port_compat','EXACT_ASSOCIATION_RTL_PASS_SOFTWARE_DESCRIPTORS_NOT_FULL_CHAIN'),
  ('classifier_dsp_product','SELECTED_COMPONENT_CLASSIFIER_PASS_NOT_FULL_VIDEO_SIGNOFF'),
  ('frame_faults_dsp_product','FRAME_CLASSIFIER_FAULT_RECOVERY_PASS'),
  ('product42_21_compact','PRODUCT_SERIAL_PASS'),('product42_21_dsp','PRODUCT_SERIAL_PASS'),('product42_21_reference','PRODUCT_SERIAL_PASS')]:
  path=ROOT/'tmp/hand_rtl'/folder/'result.json';receipt=json.loads(path.read_text())
  if receipt['status']!=expected:raise RuntimeError('wrong test receipt '+folder)
  for source,h in receipt['hashes'].items():
   if sha(ROOT/source)!=h:raise RuntimeError('stale regression source '+source)
   source_hashes[source]=h
  for source,h in receipt.get('input_hashes',{}).items():
   if sha(ROOT/source)!=h:raise RuntimeError('changed RGB samples '+source)
  tests[folder]=dict(receipt_sha256=sha(path),status=expected,tests=receipt.get('tests'),frames=receipt.get('frames'))
 native=ROOT/'tmp/hand_rtl/native_full_rgb_selected14';compile_log=(native/'compile.log').read_text()
 if 'Errors: 0, Warnings: 0' not in compile_log:raise RuntimeError('native compile errors/warnings')
 for log in native.glob('*.log'):
  if log.name=='compile.log':continue
  t=log.read_text()
  if 'HAND_NATIVE_RGB_CLASSIFIER_PASS' not in t or 'Errors: 0, Warnings: 0' not in t:raise RuntimeError('incomplete native test '+log.name)
 gate=ROOT/'tmp/native_hand_full_gate_v2.area';placed=ROOT/'tmp/native_hand_capacity_failed_place.area'
 placement_log=ROOT/'tmp/native_hand_capacity_place_retry.log';text=placement_log.read_text()
 if 'PHY-9053 ERROR' not in text or '26524' not in text or 'NATIVE_HAND_PLACEMENT_FAILED' not in text:raise RuntimeError('missing genuine capacity failure')
 gate_log=read_log(ROOT/'tmp/native_hand_full_gate_v2.log')
 if 'HDMI_NATIVE_HAND_GATE_FLOW_COMPLETE' not in gate_log or 'isp_top_user(ENABLE_HAND=2,' not in gate_log or 'elaborate module ua_hand_native_classifier' not in gate_log:raise RuntimeError('wrong synthesized hand variant')
 frozen=json.loads((ROOT/'tmp/native_hand_full_gate_v2_source_hashes.json').read_text())
 for source,h in frozen.items():
  path=Path(source)
  if str(path).lower().startswith(str(ROOT/'rtl').lower()) or path.name in ('build.py','area_hdmi_native_hand.tcl'):
   if sha(path)!=h.lower():raise RuntimeError('maintained synthesis source drift '+source)
 top=ROOT/'rtl/user/design_top_user.v';generated=ROOT/'prj/user_source/hdl_source/design_top_user.v'
 if top.read_text(encoding='utf-8').count('.ENABLE_HAND(1),')!=1 or sha(top)!=sha(generated):raise RuntimeError('normal production selector not restored')
 compiled=top.read_text(encoding='utf-8').replace('.ENABLE_HAND(1),','.ENABLE_HAND(2),')
 compiled_hash=hashlib.sha256(compiled.encode()).hexdigest()
 if compiled_hash!=frozen[str(generated)].lower():raise RuntimeError('native source translation mismatch')
 resources={k:int(re.search(r'^#'+k+r'\s+(\d+)',placed.read_text(),re.M).group(1)) for k in ('slice','eram','dsp')}
 result=dict(status='REAL_RGB_RTL_PASS_FULL_PROJECT_PACKING_FAILED_NOT_PROGRAMMABLE',tests=tests,
  resources=resources,limits=dict(slice=21216,eram=108,dsp=40),slice_excess=resources['slice']-21216,
  artifact_hashes={str(path.relative_to(ROOT)):sha(path) for path in (gate,placed,placement_log,ROOT/'tmp/native_hand_full_gate_v2_snapshot.db')},
  source_hashes=source_hashes,production_selector_restored=True,placement_pass=False,routing_pass=False,bit_generated=False,programmed=False,flash_written=False)
 a.out.write_text(json.dumps(result,indent=2));print(json.dumps({k:result[k] for k in ('status','resources','slice_excess','production_selector_restored','programmed')},indent=2))
if __name__=='__main__':main()
