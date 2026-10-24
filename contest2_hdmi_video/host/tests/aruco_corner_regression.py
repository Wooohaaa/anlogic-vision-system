"""Paired v30/v31 test using immutable baseline C and independent projections.
No per-scene calibration/fudge factors. Runtime/RTL co-sim is a separate test.
"""
import ctypes as ct
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import cv2
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
MCU=ROOT.parent/'mcu_tracking'
BASE=ROOT/'tmp/v30_baseline_before_corner_fix/mcu_tracking/aruco_app'
TMP=ROOT/'tmp/aruco_corner'
OUT=ROOT/'deliverables/aruco_corner_improvement'
TMP.mkdir(parents=True,exist_ok=True);OUT.mkdir(parents=True,exist_ok=True)
spec=importlib.util.spec_from_file_location('pose_types',ROOT/'host/tests/aruco_pose_regression.py')
types=importlib.util.module_from_spec(spec);spec.loader.exec_module(types)
env=dict(os.environ);env['PATH']='C:/msys64/ucrt64/bin;'+env['PATH']
os.add_dll_directory('C:/msys64/ucrt64/bin')
libraries=[];inputs=[Path(__file__),MCU/'tests/aruco_pose_host.c',MCU/'tests/aruco_detect_host.c']
for name,source in [('v30',BASE),('v31',MCU/'aruco_app')]:
    files=[source/f for f in ('aruco_detect.c','aruco_decode.c','aruco_refine.c','aruco_pose.c')]
    path=TMP/f'{name}_quality.dll'
    subprocess.run(['C:/msys64/ucrt64/bin/gcc.exe','-shared','-O2','-Wall','-Wextra','-Werror',
                    '-I',str(source),str(MCU/'tests/aruco_pose_host.c'),str(MCU/'tests/aruco_detect_host.c'),
                    *[str(p) for p in files],'-o',str(path)],check=True,env=env)
    lib=ct.CDLL(str(path))
    lib.ua_test_image_pose.argtypes=[ct.POINTER(ct.c_ubyte),ct.POINTER(types.Camera),ct.POINTER(types.Pose),
                                    ct.POINTER(ct.c_float),ct.POINTER(ct.c_int)]
    lib.ua_test_detect.argtypes=[ct.POINTER(ct.c_ubyte),ct.c_uint,ct.c_uint,ct.POINTER(ct.c_float),ct.POINTER(ct.c_uint)]
    libraries.append(lib);inputs+=files+list(source.glob('*.h'))
camera=types.Camera(1,1280,720,900,900,640,360,0,0,0,0,0,.08,4)
K=np.array([[900.,0,640],[0,900.,360],[0,0,1.]])
obj=np.array([[-.04,.04,0],[.04,.04,0],[.04,-.04,0],[-.04,-.04,0]])

def evaluate(lib,image):
    p=image.ctypes.data_as(ct.POINTER(ct.c_ubyte));pose=types.Pose();corners=(ct.c_float*8)();status=ct.c_int();steps=ct.c_uint()
    marker=lib.ua_test_detect(p,160,90,corners,ct.byref(steps));detection=(marker,bytes(corners),steps.value)
    pose_id=lib.ua_test_image_pose(p,ct.byref(camera),ct.byref(pose),corners,ct.byref(status))
    assert marker==pose_id
    return detection,pose,status.value

metadata=json.loads((ROOT/'tmp/aruco_live_cosim/scenes.json').read_text())
gray=np.loadtxt(ROOT/'tmp/aruco_live_cosim/expected_gray.hex',dtype=np.uint8,converters=lambda s:int(s,16)).reshape(-1,90,160)
cases=[dict(name=s['name'],image=np.ascontiguousarray(image),truth=np.array(s['truth_xyz_m']),
            expected=s['expected_id'],group='joint_fixture') for s,image in zip(metadata,gray)]
rng=np.random.default_rng(20261017)
dictionary=cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50)
for index in range(96):
    # Half axis-aligned translations/scales, half tilted and rotated.
    angles=np.zeros(3) if index<48 else rng.uniform([-.55,-.55,-.8],[.55,.55,.8])
    rotation=cv2.Rodrigues(angles)[0] @ np.diag([1.,-1.,-1.])
    translation=rng.uniform([-.025,-.015,.20],[.025,.015,.36])
    q=cv2.projectPoints(obj,cv2.Rodrigues(rotation)[0],translation,K,None)[0].reshape(4,2)
    marker_id=(7,23,49)[index%3]
    marker=cv2.aruco.generateImageMarker(dictionary,marker_id,240)
    matrix=cv2.getPerspectiveTransform(np.float32([[-.5,-.5],[239.5,-.5],[239.5,239.5],[-.5,239.5]]),q.astype(np.float32))
    frame=cv2.warpPerspective(marker,matrix,(1280,720),flags=cv2.INTER_LINEAR,borderValue=255)
    frame=18+np.minimum(frame,210).astype(np.float32)*(212/255)
    if index%3==1:frame=18+(frame-18)*(62/212)
    image=frame[::8,::8]+rng.normal(0,1.5,(90,160))
    cases.append(dict(name=f'holdout_{index:02d}',image=np.ascontiguousarray(np.clip(image,0,255),dtype=np.uint8),
                      truth=translation,expected=marker_id,group='holdout'))

rows=[];old_errors=[];new_errors=[];changed=0
for case in cases:
    (before,old,_),(after,new,_)=[evaluate(lib,case['image']) for lib in libraries]
    assert before==after,case['name']  # ID, corners, scan work remain identical.
    assert not old.valid or new.valid,case['name']
    if old.valid and new.valid:
        old_error=float(np.linalg.norm(np.array(old.translation)-case['truth'])*1000)
        new_error=float(np.linalg.norm(np.array(new.translation)-case['truth'])*1000)
        old_errors.append(old_error);new_errors.append(new_error)
        updated=not np.array_equal(np.array(old.translation),np.array(new.translation))
        changed+=updated
    else:old_error=new_error=None;updated=False
    rows.append(dict(name=case['name'],group=case['group'],expected_id=case['expected'],id=after[0],
                     old_valid=bool(old.valid),new_valid=bool(new.valid),
                     old_z_mm=old.translation[2]*1000 if old.valid else None,
                     new_z_mm=new.translation[2]*1000 if new.valid else None,
                     truth_z_mm=case['truth'][2]*1000,old_position_error_mm=old_error,new_position_error_mm=new_error,
                     changed=bool(updated),new_rms_px=new.rms_px))
assert rows[0]['new_position_error_mm']<2 and rows[2]['new_position_error_mm']<2
assert np.mean(new_errors)<np.mean(old_errors),(np.mean(old_errors),np.mean(new_errors))
# Averages alone cannot conceal a large new failure in the validation set.
regressions=[r for r in rows if r['old_position_error_mm'] is not None and r['new_position_error_mm']>r['old_position_error_mm']+2]
assert not regressions,regressions
report=dict(status='V31_PAIRED_CORNER_IMPROVEMENT_PASS_SYNTHETIC_ONLY',cases=len(rows),seed=20261017,
            id_corners_steps_identical=True,previous_valid_pose_losses=0,changed_poses=changed,
            paired_valid_cases=len(old_errors),old_mean_position_error_mm=float(np.mean(old_errors)),
            new_mean_position_error_mm=float(np.mean(new_errors)),old_max_position_error_mm=max(old_errors),
            new_max_position_error_mm=max(new_errors),regressions_over_2mm=len(regressions),results=rows,
            input_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in
                           inputs+[ROOT/'tmp/aruco_live_cosim/scenes.json',ROOT/'tmp/aruco_live_cosim/expected_gray.hex']})
(OUT/'validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
# Comparison uses exact old/new C results; it is not an image-generation guess.
canvas=np.full((550,1200,3),245,np.uint8)
cv2.putText(canvas,'Same input / same calibration / old vs new C pose',(28,40),cv2.FONT_HERSHEY_SIMPLEX,.8,(25,25,25),2,cv2.LINE_AA)
for i,row in enumerate(rows[1:8]):
    y=94+i*58
    text=f"{row['name']:<16} truth {row['truth_z_mm']:6.1f}  v30 {row['old_z_mm']:6.1f}  v31 {row['new_z_mm']:6.1f} mm"
    cv2.putText(canvas,text,(28,y),cv2.FONT_HERSHEY_SIMPLEX,.63,(20,20,20),1,cv2.LINE_AA)
cv2.putText(canvas,f"Paired mean error: {np.mean(old_errors):.2f} -> {np.mean(new_errors):.2f} mm; {len(rows)} synthetic cases",
            (28,525),cv2.FONT_HERSHEY_SIMPLEX,.62,(30,90,25),1,cv2.LINE_AA)
cv2.imwrite(str(OUT/'v30_v31_comparison.png'),canvas)
print('ARUCO_CORNER_PAIRED_PASS',len(rows),'cases;',changed,'pose changes; mean error mm',np.mean(old_errors),'->',np.mean(new_errors))
