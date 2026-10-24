"""C projection vs independent OpenCV, SYNTHETIC intrinsics only. No hardware."""
import ctypes as ct
import os
import subprocess
from pathlib import Path
import cv2
import numpy as np
from aruco_pose_regression import Camera, Point, Pose, ROOT, MCU

def main():
    out = ROOT / 'tmp/aruco'
    out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, PATH='C:/msys64/ucrt64/bin;' + os.environ['PATH'])
    dll = out / 'axes.dll'
    subprocess.run(['C:/msys64/ucrt64/bin/gcc.exe', '-std=c99', '-O2', '-Wall', '-Wextra', '-Werror',
                    '-shared', str(MCU / 'aruco_app/aruco_pose.c'), '-o', str(dll)], check=True, env=env)
    os.add_dll_directory('C:/msys64/ucrt64/bin')
    lib = ct.CDLL(str(dll))
    lib.ua_aruco_pose_axes.argtypes = [ct.POINTER(Camera), ct.POINTER(Pose), ct.c_float, ct.POINTER(Point)]
    c = Camera(1,1280,720,900,910,640,360,-.12,.025,.001,-.001,0,.12,2)
    k = np.array([[c.fx,0,c.cx],[0,c.fy,c.cy],[0,0,1]],np.float64)
    d = np.array([c.k1,c.k2,c.p1,c.p2,c.k3],np.float64)
    obj = np.array([[0,0,0],[.06,0,0],[0,.06,0],[0,0,.06]],np.float64)
    rng = np.random.default_rng(37)
    def project(cam,p,length=.06):
        pts=(Point*4)(*[Point(123,456) for _ in range(4)])
        code=lib.ua_aruco_pose_axes(ct.byref(cam),ct.byref(p),length,pts)
        return code,np.array([[q.x,q.y] for q in pts])
    for i in range(120):
        r=cv2.Rodrigues(rng.uniform(-.6,.6,3))[0]@np.diag([1.,-1.,-1.])
        t=rng.uniform([-.07,-.04,.35],[.07,.04,.9])
        p=Pose();p.valid=1;p.rotation[:]=r.ravel();p.translation[:]=t
        ok,xy=project(c,p)
        ref=cv2.projectPoints(obj,cv2.Rodrigues(r)[0],t,k,d)[0].reshape(4,2)
        assert ok and np.max(np.abs(xy-ref))<.001,(i,xy,ref)
    for field,value in [('calibrated',0),('fx',0),('k1',float('nan'))]:
        bad=Camera.from_buffer_copy(c);setattr(bad,field,value)
        ok,xy=project(bad,p);assert not ok and not xy.any()
    for length in [0,-1,float('nan'),.13]:
        ok,xy=project(c,p,length);assert not ok and not xy.any()
    for mode in ['invalid','behind','offscreen','nan']:
        bad=Pose.from_buffer_copy(p)
        if mode=='invalid':bad.valid=0
        if mode=='behind':bad.translation[2]=-.5
        if mode=='offscreen':bad.translation[0]=9
        if mode=='nan':bad.rotation[0]=float('nan')
        ok,xy=project(c,bad);assert not ok and not xy.any()
    print('ARUCO_AXES_PROJECTION_PASS opencv_cases=120 invalid_clear_cases=11 SYNTHETIC_NOT_CAMERA_CALIBRATION')

if __name__=='__main__':main()
