"""Independent partial-stage receipt. NEVER authorizes bitstream programming."""
import argparse
import hashlib
import json
from pathlib import Path
import re
from test_hand_blob_scan import ROOT


def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def load(relative,status):
    path=ROOT/relative;data=json.loads(path.read_text())
    if data['status']!=status:raise RuntimeError(f'bad status: {path}')
    return data


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True)
    a=p.parse_args()
    if a.out.exists():raise FileExistsError(a.out)
    ccl=load('tmp/hand_rtl/ccl_shared_port/result.json','CCL_LOCALIZATION_PASS_NOT_CLASSIFIER_SIGNOFF')
    contour=load('tmp/hand_rtl/contour_ordered/result.json','CONTOUR_BOUNDARY_PASS_NOT_CLASSIFIER_SIGNOFF')
    faults=load('tmp/hand_rtl/contour_faults/result.json','CONTOUR_EXPLICIT_FAULT_PASS')
    chain=load('tmp/hand_rtl/chain_ordered/result.json','SELECTED_VIDEO_RGB_MASK_CCL_CONTOUR_RTL_PASS_NOT_CLASSIFIER')
    for result,source in ((ccl,'ua_hand_blob_scan.v'),(contour,'ua_hand_contour_trace.v'),(faults,'ua_hand_contour_trace.v')):
        if result['rtl_sha256']!=digest(ROOT/'rtl/user'/source):raise RuntimeError(f'RTL changed: {source}')
    for name,wanted in chain['hashes'].items():
        if digest(ROOT/name)!=wanted:raise RuntimeError(f'Chain input changed: {name}')
    if 'HAND_MASK_OWNERSHIP_CCL_PASS ' not in (ROOT/'tmp/hand_rtl/mask_ownership.log').read_text():
        raise RuntimeError('ownership tests missing')
    resources={}
    for name,tag in [('mask','MASK'),('blob','BLOB'),('contour','CONTOUR')]:
        log=ROOT/f'tmp/hand_rtl/{name}_synthesis.log'
        if f'HAND_{tag}_MICRO_SYNTH_COMPLETE' not in log.read_text():raise RuntimeError(f'synthesis incomplete: {name}')
        area=ROOT/f'tmp/hand_rtl/{name}_gate.area';text=area.read_text()
        resources[name]={key:int(re.search(r'^#'+key+r'\*?\s+(\d+)',text,re.M)[1])
                         for key in ('slice','lut','reg','eram','dsp')}
    source_names=['rtl/user/ua_hand_mask_frame.v','rtl/user/ua_hand_blob_scan.v','rtl/user/ua_hand_contour_trace.v']
    evidence=['tmp/hand_rtl/ccl_shared_port/result.json','tmp/hand_rtl/contour_ordered/result.json',
              'tmp/hand_rtl/contour_faults/result.json','tmp/hand_rtl/chain_ordered/result.json',
              'tmp/hand_rtl/mask_ownership.log']
    report=dict(status='FRONTEND_CCL_CONTOUR_VERIFIED_CLASSIFIER_PENDING_NOT_PROGRAMMABLE',
                programmed=False,flash_written=False,production_integrated=False,classification_verified=False,
                full_project_routed=False,ccl_modes=ccl['completed_modes'],contour_cases=contour['completed'],
                selected_rgb_frames=len(chain['tests']),micro_gate_resources=resources,
                sources={name:digest(ROOT/name) for name in source_names},
                evidence={name:digest(ROOT/name) for name in evidence})
    a.out.write_text(json.dumps(report,indent=2));print(report['status'])


if __name__=='__main__':main()
