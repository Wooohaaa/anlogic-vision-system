"""Independent OpenCV oracle for estimated-K display axes; no board access."""
import ctypes as ct
import json
import os
from pathlib import Path
import subprocess
import cv2
import numpy as np
from aruco_pose_regression import Point, ROOT, MCU


def main():
    out = ROOT / 'tmp/aruco'
    out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, PATH='C:/msys64/ucrt64/bin;' + os.environ['PATH'])
    dll = out / 'estimated_axes_v39.dll'
    subprocess.run(['C:/msys64/ucrt64/bin/gcc.exe', '-std=c99', '-O2', '-Wall', '-Wextra', '-Werror',
                    '-shared', str(MCU / 'aruco_app/aruco_pose.c'), '-o', str(dll)], check=True, env=env)
    os.add_dll_directory('C:/msys64/ucrt64/bin')
    lib = ct.CDLL(str(dll))
    fn = lib.ua_aruco_axes_estimated
    fn.argtypes = [ct.POINTER(Point), ct.c_uint, ct.c_uint, ct.c_float, ct.POINTER(Point)]
    obj = np.array([[-.06,.06,0],[.06,.06,0],[.06,-.06,0],[-.06,-.06,0]], np.float64)
    axes = np.array([[0,0,0],[.06,0,0],[0,.06,0],[0,0,.06]], np.float64)
    K = np.array([[640.,0,639.5],[0,640.,359.5],[0,0,1.]])
    front = np.diag([1.,-1.,-1.])

    def call(corners, focal=640., width=1280, height=720):
        p = (Point * 4)(*[Point(*v) for v in corners])
        q = (Point * 4)(*[Point(123,456) for _ in range(4)])
        ok = fn(p, width, height, focal, q)
        return ok, np.array([[v.x,v.y] for v in q])

    def project(points, R, t):
        return cv2.projectPoints(points, cv2.Rodrigues(R)[0], t, K, None)[0].reshape(-1,2)

    def clip_z(q):
        q = q.copy()
        step = q[3]-q[0]
        factors = [1.]
        for dim, bound in [(0,1279.),(1,719.)]:
            if q[3,dim] < 0:
                factors.append(-q[0,dim]/step[dim])
            elif q[3,dim] > bound:
                factors.append((bound-q[0,dim])/step[dim])
        q[3] = q[0] + min(factors)*step
        return q

    rng = np.random.default_rng(39)
    count, worst, clipped = 0, 0., 0
    for _ in range(500):
        R = cv2.Rodrigues(rng.uniform([-.8,-.8,-3.14],[.8,.8,3.14]))[0] @ front
        t = rng.uniform([-.18,-.10,.23],[.18,.10,.85])
        corners = project(obj,R,t)
        if np.any(corners < 0) or np.any(corners > [1279,719]):
            continue
        truth = project(axes,R,t)
        expected = clip_z(truth)
        ok, got = call(corners)
        error = float(np.max(np.abs(got-expected)))
        assert ok and error < .1, (corners,got,expected,error)
        worst = max(worst,error)
        clipped += int(not np.allclose(truth,expected))
        count += 1
    assert count > 300

    # Opposite tilt must reverse projected normal; roll within the same plane
    # must NOT spuriously rotate the plane normal along with X/Y.
    normals = []
    for angle in [-.55,.55]:
        R = cv2.Rodrigues(np.array([0.,angle,0.]))[0] @ front
        corners = project(obj,R,np.array([0.,0.,.4]))
        ok,q = call(corners)
        assert ok
        normals.append(q[3]-q[0])
    assert normals[0][0]*normals[1][0] < -100
    tilt = cv2.Rodrigues(np.array([.35,-.45,0.]))[0] @ front
    reference = None
    for roll in [0,np.pi/2,np.pi,3*np.pi/2]:
        R = tilt @ cv2.Rodrigues(np.array([0.,0.,roll]))[0]
        ok,q = call(project(obj,R,np.array([.02,-.01,.45])))
        assert ok
        if reference is None:
            reference = q[3]-q[0]
        assert np.max(np.abs(q[3]-q[0]-reference)) < .03
    centered = project(obj,front,np.array([0.,0.,.4]))
    ok,q = call(centered)
    assert ok and np.linalg.norm(q[3]-q[0]) < .01, q

    invalid = [centered[[0,3,2,1]], np.zeros((4,2)), centered.copy(), centered.copy()]
    invalid[2][0,0] = np.nan
    invalid[3][0,0] = -1
    rejects = 0
    for corners in invalid:
        ok,q = call(corners)
        assert not ok and not q.any()
        rejects += 1
    for focal in [0,-1,float('nan'),float('inf')]:
        ok,q = call(centered,focal)
        assert not ok and not q.any()
        rejects += 1
    for w,h in [(0,720),(1280,0),(1,720),(1280,20000)]:
        ok,q = call(centered,width=w,height=h)
        assert not ok and not q.any()
        rejects += 1

    # Synthetic diagnostic contact sheet, not an altered camera screenshot.
    sheet = np.full((810,1200,3),245,np.uint8)
    views = [(-.55,0,0),(.55,0,0),(0,-.55,0),(0,.55,0),(.35,-.45,0),(.35,-.45,1.57)]
    for idx,(rx,ry,rz) in enumerate(views):
        R = cv2.Rodrigues(np.array([rx,ry,0.]))[0] @ front @ cv2.Rodrigues(np.array([0.,0.,rz]))[0]
        corners = project(obj,R,np.array([0.,0.,.32]))
        ok,q = call(corners)
        assert ok
        base = np.array([(idx%3)*400,(idx//3)*380+50])
        convert = lambda p: tuple(np.rint(np.array(p)*.3 + base).astype(int))
        cv2.polylines(sheet,[np.array([convert(p) for p in corners])],True,(40,40,40),2,cv2.LINE_AA)
        for j,color in enumerate([(0,0,255),(0,170,0),(255,0,0)],1):
            cv2.line(sheet,convert(q[0]),convert(q[j]),color,2,cv2.LINE_AA)
        cv2.putText(sheet,f'tilt {rx:+.2f},{ry:+.2f} roll {rz:.2f}',tuple(base+[8,300]),cv2.FONT_HERSHEY_SIMPLEX,.46,(30,30,30),1,cv2.LINE_AA)
    cv2.putText(sheet,'v39 SYNTHETIC: estimated centered K, f=640px; NOT camera calibration',(12,25),cv2.FONT_HERSHEY_SIMPLEX,.65,(30,30,30),1,cv2.LINE_AA)
    dest = ROOT/'deliverables/aruco_axes_v39'
    dest.mkdir(parents=True,exist_ok=True)
    cv2.imwrite(str(dest/'normal_sweep.png'),sheet)
    summary = dict(status='ESTIMATED_AXES_OPENCV_PASS',opencv_cases=count,max_error_px=worst,
                   viewport_clipped=clipped,invalid_cases=rejects,opposite_tilt=True,
                   in_plane_roll_normal_invariant=True,centered_frontal_zero_z=True,
                   calibrated=False,nominal_focal_px=640)
    (out/'v39_estimated_axes_result.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    print('ARUCO_ESTIMATED_AXES_PASS '+json.dumps(summary))


if __name__ == '__main__':
    main()
