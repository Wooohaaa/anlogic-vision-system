"""Differential v29/v30 production C testing, no board access.

The frozen v29 sources are independently compiled. Detector/pose outputs must
be identical, not merely fit within relaxed accuracy gates.
"""
import ctypes as ct
import hashlib
import json
import os
from pathlib import Path
import subprocess
import cv2
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
MCU=ROOT.parent/'mcu_tracking'
BASE=ROOT/'tmp/v29_baseline_before_mcu_optimization'
TMP=ROOT/'tmp/v30_differential'
TMP.mkdir(parents=True,exist_ok=True)

class Camera(ct.Structure):
    _fields_=[(n,ct.c_uint) for n in ('calibrated','width','height')]+[
        (n,ct.c_float) for n in ('fx','fy','cx','cy','k1','k2','p1','p2','k3','side_m','max_rms_px')]
class Pose(ct.Structure):
    _fields_=[('valid',ct.c_uint),('iterations',ct.c_uint),('rotation',ct.c_float*9),
             ('translation',ct.c_float*3),('quaternion',ct.c_float*4),('rms_px',ct.c_float)]

env=dict(os.environ)
env['PATH']='C:/msys64/ucrt64/bin;'+env['PATH']
os.add_dll_directory('C:/msys64/ucrt64/bin')
libraries=[]
inputs=[Path(__file__),MCU/'tests/aruco_detect_host.c',MCU/'tests/aruco_pose_host.c']
for label,source in [('v29',BASE),('v30',MCU/'aruco_app')]:
    # Build the SAME host bridges against each version's own public headers.
    sources=[source/name for name in ('aruco_decode.c','aruco_detect.c','aruco_refine.c','aruco_pose.c')]
    path=TMP/f'{label}.dll'
    subprocess.run(['C:/msys64/ucrt64/bin/gcc.exe','-std=c99','-O2','-Wall','-Wextra','-Werror',
                    '-shared','-I',str(source),str(MCU/'tests/aruco_detect_host.c'),
                    str(MCU/'tests/aruco_pose_host.c'),*[str(s) for s in sources],'-o',str(path)],
                   check=True,env=env)
    lib=ct.CDLL(str(path))
    lib.ua_test_detect.argtypes=[ct.POINTER(ct.c_ubyte),ct.c_uint,ct.c_uint,
                                 ct.POINTER(ct.c_float),ct.POINTER(ct.c_uint)]
    lib.ua_test_image_pose.argtypes=[ct.POINTER(ct.c_ubyte),ct.POINTER(Camera),ct.POINTER(Pose),
                                     ct.POINTER(ct.c_float),ct.POINTER(ct.c_int)]
    lib.ua_test_workspace_size.restype=ct.c_uint
    libraries.append(lib)
    inputs+=sources+[source/name for name in ('aruco_detect.h','aruco_decode.h','aruco_refine.h',
                                               'aruco_pose.h','aruco_dictionary.h')]
camera=Camera(1,1280,720,900,900,640,360,0,0,0,0,0,.08,4)

def run(lib,image):
    p=image.ctypes.data_as(ct.POINTER(ct.c_ubyte))
    corners=(ct.c_float*8)();steps=ct.c_uint();pose=Pose();status=ct.c_int()
    marker_id=lib.ua_test_detect(p,160,90,corners,ct.byref(steps))
    plain=(marker_id,bytes(corners),steps.value)
    pose_id=lib.ua_test_image_pose(p,ct.byref(camera),ct.byref(pose),corners,ct.byref(status))
    return plain,(pose_id,status.value,bytes(corners),bytes(pose))

rng=np.random.default_rng(20261016)
dictionary=cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50)
cases=[]
for marker_id in range(50):
    for rotation in range(4):
        image=np.full((90,160),230,np.float32)
        marker=np.rot90(cv2.aruco.generateImageMarker(dictionary,marker_id,48),rotation)
        image[21:69,56:104]=18+marker.astype(np.float32)*(212/255)
        if rotation%2:image=18+(image-18)*(62/212)
        image+=rng.normal(0,2,image.shape)
        cases.append((f'id{marker_id}_rot{rotation}',np.ascontiguousarray(np.clip(image,0,255),dtype=np.uint8)))
for index in range(40):
    image=rng.integers(0,256,(90,160),np.uint8) if index%2 else np.full((90,160),index*6,np.uint8)
    cases.append((f'negative{index}',image))
for folder in (ROOT/'tmp/aruco/validation',ROOT/'tmp/aruco_pose'):
    for path in sorted(folder.glob('*_input.hex')):
        image=np.loadtxt(path,dtype=np.uint8,converters=lambda s:int(s,16)).reshape(90,160)
        cases.append((path.name,np.ascontiguousarray(image)))
        inputs.append(path)

digest=hashlib.sha256()
for name,image in cases:
    old,new=run(libraries[0],image),run(libraries[1],image)
    assert old==new,name
    digest.update(name.encode());digest.update(image.tobytes());digest.update(repr(old).encode())
old_size=libraries[0].ua_test_workspace_size();new_size=libraries[1].ua_test_workspace_size()
assert old_size-new_size==512,(old_size,new_size)
report=dict(status='V30_V29_DIFFERENTIAL_IDENTICAL_NOT_BOARD_SIGNOFF',cases=len(cases),
            checks=['detected_id','raw_corners_bit_exact','step_count','pose_status',
                    'pose_rotation_translation_quaternion_bit_exact','repeat_begin_clears_reused_histogram'],
            workspace_host_before=old_size,workspace_host_after=new_size,workspace_saved_bytes=old_size-new_size,
            fixture_output_digest=digest.hexdigest(),
            input_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs})
(TMP/'validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('ARUCO_MEMORY_DIFFERENTIAL_PASS cases=',len(cases),' workspace_saved=',old_size-new_size)
