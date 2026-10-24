"""Frozen integer reference replay; baseline and optional sensitivity cases.

These two videos are development data. Passing their stable labels is not
RTL equivalence or independent board/scene validation.
"""
import argparse,json,sys
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'host'))
from hand_fixed_classifier import classify_video,width_checks,file_sha256


def check_probe_units():
    vertical=np.zeros((100,100),np.uint8);vertical[45:86,40:61]=1;vertical[10:46,48:53]=1
    checks,accepted=width_checks(vertical,100,120,160,(0,40),[(50,10)])
    if accepted!=[(50,10)] or checks[0]['widths']!=[5,5]:raise AssertionError(('vertical Q8',checks))
    horizontal=np.zeros((100,100),np.uint8);horizontal[40:61,25:56]=1;horizontal[48:53,55:91]=1
    checks,accepted=width_checks(horizontal,80,100,160,(-40,0),[(90,50)])
    if accepted!=[(90,50)] or checks[0]['widths']!=[5,5]:raise AssertionError(('horizontal Q8',checks))


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True)
    p.add_argument('--stress',action='store_true');a=p.parse_args();a.out.mkdir(parents=True,exist_ok=False)
    check_probe_units();model=ROOT/'host/hand_fixed_classifier.py';frozen=file_sha256(model)
    cases=[('baseline',(100,100,100),0)]
    if a.stress:cases += [('dim90',(90,90,90),0),('bright110',(110,110,110),0),
        ('warm5',(105,100,95),0),('cool5',(95,100,105),0),('noise4',(100,100,100),4),
        ('dim90_noise4',(90,90,90),4)]
    records=[];inputs={}
    for ds,directory,labelname in [('old','hand_hdmi_20261017','hand_hdmi_20261017_labels.json'),
                                   ('new','hand_hdmi_162050','hand_hdmi_162050_labels_audited.json')]:
        inp=ROOT/'tmp'/directory/'native';label=ROOT/'host/tests'/labelname
        inputs[ds]={str(path.relative_to(ROOT)):file_sha256(path) for path in (inp/'groups.bin',inp/'manifest.json',label)}
        for case,gains,noise in cases:
            if file_sha256(model)!=frozen:raise RuntimeError('model changed during regression')
            result=classify_video(inp,label,a.out/f'{ds}_{case}',gains=gains,noise=noise,geometry_scale=1)
            record=dict(dataset=ds,case=case,correct=result['correct'],scored_frames=result['scored_frames'],
                        pass_all=result['correct']==result['scored_frames'],
                        failures=[s for s in result['segments'] if s['correct']!=s['frames']])
            records.append(record);print(json.dumps(record),flush=True)
    baseline=all(r['pass_all'] for r in records if r['case']=='baseline')
    stress=all(r['pass_all'] for r in records if r['case']!='baseline') if a.stress else None
    report=dict(status='INTEGER_REFERENCE_BASELINE_PASS_STRESS_PENDING' if baseline and stress is not True else
                     'INTEGER_REFERENCE_REPLAY_PASS_NOT_RTL' if baseline else 'INTEGER_REFERENCE_BASELINE_FAIL',
                baseline_pass=baseline,stress_pass=stress,model_sha256=frozen,geometry_scale=1,
                input_hashes=inputs,records=records,labels_edited=False,rtl_equivalence=False,board_verified=False,
                warning='Development videos and synthetic sum-domain sensitivity tests; not a physical sensor/noise model.')
    (a.out/'result.json').write_text(json.dumps(report,indent=2))
    return 0 if baseline and (not a.stress or stress) else 2


if __name__=='__main__':sys.exit(main())
