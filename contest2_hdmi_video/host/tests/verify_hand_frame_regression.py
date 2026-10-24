"""Audit split-dataset frame RTL, component red stats and current resources.

Never upgrades software-mask/association input to full RGB integration or a bit.
"""
import argparse,hashlib,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def check_receipt(path,status):
 r=json.loads(path.read_text());assert r['status']==status,(path,r.get('status'))
 for name,digest in r.get('hashes',{}).items():assert sha(ROOT/name)==digest,(name,'stale evidence')
 return r
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 if a.out.exists():raise FileExistsError(a.out)
 root=ROOT/'tmp/hand_rtl';old_path=root/'old_video_prefix_verified.json';new_path=root/'new_video_independent_replay/result.json'
 old=check_receipt(old_path,'OLD_VIDEO_PREFIX_RTL_VERIFIED_COMBINED_RUN_NOT_COMPLETE')
 new=check_receipt(new_path,'DATASET_FRAME_GEOMETRY_POLICY_VOTE_RTL_PASS_SOFTWARE_MASK_CANDIDATE_INPUT')
 assert old['old_video_frames']==870 and old['frames']==898 and new['first']==898 and new['frames']==818
 for name,digest in old['hashes'].items():assert new['hashes'][name]==digest
 for name,digest in old['evidence'].items():assert sha(ROOT/name)==digest,(name,'changed vector evidence')
 for name,digest in new['inputs'].items():assert sha(ROOT/name)==digest
 unit_statuses=[('frame_classifier_faults_real_probe/result.json','FRAME_CLASSIFIER_FAULT_RECOVERY_PASS'),
  ('frame_policy_both_videos/result.json','FRAME_POLICY_PASS_SOFTWARE_GEOMETRY_INPUT_NOT_FULL_VIDEO_RTL'),
  ('temporal_vote_initial/result.json','TEMPORAL_VOTE_PASS_RAW_INPUT_NOT_VIDEO_RECOGNITION_SIGNOFF'),
  ('ccl_red_sum_address_shift/result.json','CCL_RED_SUM_PASS_NOT_FULL_CLASSIFIER_SIGNOFF'),
  ('native_capture_gate/result.json','NATIVE_CAPTURE_ADMISSION_AND_LEGACY_OWNERSHIP_PASS'),
  ('chain_native_red_tap/result.json','SELECTED_VIDEO_RGB_MASK_CCL_CONTOUR_RTL_PASS_NOT_CLASSIFIER')]
 for name,status in unit_statuses:check_receipt(root/name,status)
 expected=json.loads((root/'frame_classifier_both_videos_decl_fixed/expected.json').read_text())
 scores=[]
 for name,first,count,label in (('old',28,870,'hand_hdmi_20261017_labels.json'),('new',898,818,'hand_hdmi_162050_labels_audited.json')):
  labels=json.loads((ROOT/'host/tests'/label).read_text());pred=expected[first:first+count];correct=total=0
  for segment in labels['segments']:
   for frame in range(segment['start'],segment['end']+1):
    total+=1;correct+=pred[frame]['id']==segment['id']
  scores.append(dict(dataset=name,frames=count,scored_frames=total,correct=correct))
 resources={}
 for prefix,marker in (('frame_classifier','HAND_FRAME_CLASSIFIER_MICRO_SYNTH_COMPLETE'),('frame_policy','HAND_FRAME_POLICY_MICRO_SYNTH_COMPLETE'),
                       ('temporal_vote','HAND_TEMPORAL_VOTE_MICRO_SYNTH_COMPLETE'),('blob_rgb','HAND_BLOB_RGB_MICRO_SYNTH_COMPLETE')):
  report=root/(prefix+'_gate.area');log=root/(prefix+'_gate.log')
  if prefix=='blob_rgb':log=root/'blob_rgb_shift_gate.log'
  assert marker in log.read_text(errors='replace')
  text=report.read_text();assert 'PH1P35MDG324' in text
  resources[prefix]={key:int(re.search(r'^#'+pattern+r'\s+(\d+)',text,re.M)[1]) for key,pattern in (('slice',r'slice\*?'),('eram','eram'),('dsp','dsp'))}
 result=dict(status='BOTH_VIDEO_FRAME_CLASSIFIER_RTL_PASS_SOFTWARE_MASK_ASSOCIATION_INPUT_NOT_BOARD_SIGNOFF',video_frames=1688,
   synthetic_frames=28,scores=scores,resources=resources,
   receipts=[str(p.relative_to(ROOT)) for p in (old_path,new_path)]+[str((root/name).relative_to(ROOT)) for name,_ in unit_statuses],
   hashes=old['hashes'],remaining=['RTL RGB/red scratch capture','exact seed/grown association controller',
    'resource-first shared datapath and whole-project placement/routing','dark/backlight perturbation failures','bitgen and SRAM programming'])
 a.out.write_text(json.dumps(result,indent=2));print(json.dumps({k:v for k,v in result.items() if k not in ('hashes','receipts')}))
if __name__=='__main__':main()
