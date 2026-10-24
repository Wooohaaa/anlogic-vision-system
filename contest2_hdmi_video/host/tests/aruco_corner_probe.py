"""Diagnostic only: expose both production corner/pose candidates."""
import ctypes as ct
import importlib.util
import os
from pathlib import Path
import subprocess
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
MCU=ROOT.parent/'mcu_tracking'
spec=importlib.util.spec_from_file_location('pose_types',ROOT/'host/tests/aruco_pose_regression.py')
types=importlib.util.module_from_spec(spec);spec.loader.exec_module(types)
env=dict(os.environ);env['PATH']='C:/msys64/ucrt64/bin;'+env['PATH']
out=ROOT/'tmp/aruco_corner';out.mkdir(parents=True,exist_ok=True)
subprocess.run(['C:/msys64/ucrt64/bin/gcc.exe','-shared','-O2','-Wall','-Wextra','-Werror','-I',str(MCU/'aruco_app'),
                str(MCU/'tests/aruco_corner_host.c'),*[str(MCU/'aruco_app'/f) for f in
                ('aruco_detect.c','aruco_decode.c','aruco_refine.c','aruco_pose.c')],'-o',str(out/'probe.dll')],check=True,env=env)
os.add_dll_directory('C:/msys64/ucrt64/bin')
lib=ct.CDLL(str(out/'probe.dll'))
lib.ua_test_corner_candidates.argtypes=[ct.POINTER(ct.c_ubyte),ct.POINTER(types.Camera),ct.POINTER(ct.c_float),ct.POINTER(types.Pose),ct.POINTER(ct.c_uint)]
camera=types.Camera(1,1280,720,900,900,640,360,0,0,0,0,0,.08,4)
frames=np.loadtxt(ROOT/'tmp/aruco_live_cosim/expected_gray.hex',dtype=np.uint8,converters=lambda s:int(s,16)).reshape(-1,90,160)
for i,image in enumerate(frames):
    points=(ct.c_float*16)();poses=(types.Pose*2)();refined=ct.c_uint()
    marker=lib.ua_test_corner_candidates(image.ctypes.data_as(ct.POINTER(ct.c_ubyte)),ct.byref(camera),points,poses,ct.byref(refined))
    print(i,'id',marker,'refined',refined.value,'raw_z/rms',poses[0].translation[2],poses[0].rms_px,
          'ref_z/rms',poses[1].translation[2],poses[1].rms_px)
    if i==0:print('corners',list(points))
