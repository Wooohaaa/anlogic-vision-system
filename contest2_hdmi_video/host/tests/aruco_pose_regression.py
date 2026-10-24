"""Test deployed C planar pose against independent OpenCV projection/IPPE.

All intrinsics here are SYNTHETIC, not calibration for the physical camera.
No board, UART, USB, or servo access.
"""
import ctypes as ct
import json
import hashlib
import os
from pathlib import Path
import subprocess
import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
MCU = ROOT.parent / 'mcu_tracking'
OUT = ROOT / 'deliverables/aruco_pose_simulation'
TMP = ROOT / 'tmp/aruco_pose'

class Camera(ct.Structure):
    _fields_ = [(n, ct.c_uint) for n in ('calibrated', 'width', 'height')] + [
        (n, ct.c_float) for n in ('fx', 'fy', 'cx', 'cy', 'k1', 'k2', 'p1', 'p2', 'k3', 'side_m', 'max_rms_px')]

class Point(ct.Structure):
    _fields_ = [('x', ct.c_float), ('y', ct.c_float)]

class Pose(ct.Structure):
    _fields_ = [('valid', ct.c_uint), ('iterations', ct.c_uint),
                ('rotation', ct.c_float * 9), ('translation', ct.c_float * 3),
                ('quaternion', ct.c_float * 4), ('rms_px', ct.c_float)]

class Workspace(ct.Union):
    _fields_ = [('h', ct.c_float * 72), ('lm', ct.c_float * 90)]

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    TMP.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env['PATH'] = 'C:/msys64/ucrt64/bin;' + env['PATH']
    dll = TMP / 'pose.dll'
    subprocess.run(['C:/msys64/ucrt64/bin/gcc.exe', '-std=c99', '-O2', '-Wall', '-Wextra', '-Werror',
                    '-shared', str(MCU / 'aruco_app/aruco_pose.c'), '-o', str(dll)], check=True, env=env)
    os.add_dll_directory('C:/msys64/ucrt64/bin')
    lib = ct.CDLL(str(dll))
    lib.ua_aruco_pose_solve.argtypes = [ct.POINTER(Camera), ct.POINTER(Point), ct.POINTER(Workspace), ct.POINTER(Pose)]
    c = Camera(1, 1280, 720, 900, 910, 640, 360, -.12, .025, .001, -.001, 0, .08, 2)
    K = np.array([[c.fx, 0, c.cx], [0, c.fy, c.cy], [0, 0, 1]], np.float64)
    D = np.array([c.k1, c.k2, c.p1, c.p2, c.k3], np.float64)
    obj = np.array([[-.04, .04, 0], [.04, .04, 0], [.04, -.04, 0], [-.04, -.04, 0]], np.float64)
    ws = Workspace()
    def solve(points, camera=c):
        p = (Point * 4)(*[Point(*v) for v in points])
        result = Pose()
        code = lib.ua_aruco_pose_solve(ct.byref(camera), p, ct.byref(ws), ct.byref(result))
        return code, result

    rng = np.random.default_rng(20261016)
    rows, views = [], []
    for idx in range(120):
        angles = rng.uniform([-.65, -.65, -1.4], [.65, .65, 1.4])
        perturb = cv2.Rodrigues(angles)[0]
        R = perturb @ np.diag([1., -1., -1.])
        rv = cv2.Rodrigues(R)[0]
        t = rng.uniform([-.055, -.03, .25], [.055, .03, .85])
        points = cv2.projectPoints(obj, rv, t, K, D)[0].reshape(4, 2)
        for noise in (0., .25):
            q = points + rng.normal(0, noise, points.shape)
            code, res = solve(q)
            assert code == 1 and res.valid, (idx, noise, code, res.rms_px)
            rr = np.array(res.rotation).reshape(3, 3)
            tt = np.array(res.translation)
            angle_err = np.degrees(np.arccos(np.clip((np.trace(rr @ R.T)-1)/2, -1, 1)))
            distance_err = np.linalg.norm(tt-t)
            assert np.allclose(rr.T @ rr, np.eye(3), atol=2e-5)
            assert abs(np.linalg.det(rr)-1) < 2e-5
            quat = np.array(res.quaternion)
            assert abs(np.linalg.norm(quat)-1) < 2e-5
            w, x, y, z = quat
            qr = np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                           [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                           [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])
            assert np.allclose(qr, rr, atol=2e-5)
            ref = cv2.solvePnPGeneric(obj, q, K, D, flags=cv2.SOLVEPNP_IPPE_SQUARE)
            ref_rms = min(float(np.sqrt(np.mean(np.sum((cv2.projectPoints(obj, a, b, K, D)[0].reshape(4, 2)-q)**2, axis=1))))
                          for a, b in zip(ref[1], ref[2]))
            if noise == 0:
                assert distance_err < 1e-4 and angle_err < .1, (idx, distance_err, angle_err)
            else:
                assert res.rms_px < .8 and distance_err < .025, (idx, distance_err, res.rms_px)
            rows.append(dict(case=idx, noise_px=noise, rms_px=res.rms_px, ippe_rms_px=ref_rms,
                             position_error_m=float(distance_err), rotation_error_deg=float(angle_err), iterations=res.iterations))
            if idx < 6 and noise == 0:
                views.append((q, rr.copy(), tt.copy(), res.rms_px))

    # Explicit calibration/safety/degeneracy cases: invalid output must be cleared.
    base = np.array([[500., 220.], [780., 220.], [780., 500.], [500., 500.]])
    invalid_count = 0
    for field, value in [('calibrated', 0), ('fx', 0), ('side_m', 0), ('k1', float('nan')), ('max_rms_px', -1)]:
        bad = Camera.from_buffer_copy(c)
        setattr(bad, field, value)
        code, res = solve(base, bad)
        assert code < 0 and not res.valid
        invalid_count += 1
    for bad in [np.zeros((4, 2)), np.array([[10, 10], [20, 20], [30, 30], [40, 40]]),
                base[[0, 2, 1, 3]], base[::-1], base * np.nan, base - 1000,
                np.array([[100, 100], [1100, 100], [700, 650], [500, 650]])]:
        code, res = solve(bad)
        assert code < 0 and not res.valid, (bad, code, res.rms_px)
        invalid_count += 1

    # Quantization at the existing 160x90 snapshot is a separate uncertainty
    # experiment, not grounds to claim mm accuracy on the actual camera.
    quantized = []
    for q, rr, tt, _ in views:
        code, res = solve(np.round(q / 8) * 8)
        quantized.append(dict(accepted=code == 1, status=code, rms_px=res.rms_px,
                              distance_error_m=float(np.linalg.norm(np.array(res.translation)-tt)) if code == 1 else None))

    canvas = np.full((1215, 1280, 3), 238, np.uint8)
    for idx, (points, r, t, rms) in enumerate(views):
        im = np.full((720, 1280, 3), (208, 218, 228), np.uint8)
        cv2.fillConvexPoly(im, np.round(points).astype(np.int32), (245, 245, 245))
        cv2.polylines(im, [np.round(points).astype(np.int32)], True, (15, 15, 15), 5)
        cube = np.concatenate([obj, obj + [0, 0, .04]])
        projected = cv2.projectPoints(cube, cv2.Rodrigues(r)[0], t, K, D)[0].reshape(-1, 2).astype(int)
        for a, b in [(0,1),(1,2),(2,3),(3,0),(4,5),(5,6),(6,7),(7,4),(0,4),(1,5),(2,6),(3,7)]:
            cv2.line(im, tuple(projected[a]), tuple(projected[b]), (40, 155, 20), 3)
        axes = np.array([[0,0,0],[.04,0,0],[0,.04,0],[0,0,.04]], np.float64)
        a = cv2.projectPoints(axes, cv2.Rodrigues(r)[0], t, K, D)[0].reshape(-1,2).astype(int)
        for i, col in enumerate([(0,0,255),(0,180,0),(255,0,0)], 1):
            cv2.arrowedLine(im, tuple(a[0]), tuple(a[i]), col, 4, tipLength=.15)
        im = cv2.resize(im, (640,360))
        x,y = (idx%2)*640, (idx//2)*405
        canvas[y:y+360,x:x+640] = im
        cv2.putText(canvas, f'C pose: Z={t[2]*1000:.1f} mm  RMS={rms:.4f}px',
                    (x+12,y+388), cv2.FONT_HERSHEY_SIMPLEX,.54,(25,25,25),1,cv2.LINE_AA)
    cv2.imwrite(str(OUT / 'pose_reference.png'), canvas)

    # Full image -> production C detector -> production C pose, not OpenCV detection.
    detector_dll = TMP / 'detector.dll'
    subprocess.run(['C:/msys64/ucrt64/bin/gcc.exe', '-std=c99', '-O2', '-Wall', '-Wextra', '-Werror', '-shared',
                    '-I',str(MCU/'aruco_app'),
                    str(MCU/'tests/aruco_pose_host.c'), str(MCU/'aruco_app/aruco_decode.c'),
                    str(MCU/'aruco_app/aruco_detect.c'),str(MCU/'aruco_app/aruco_refine.c'),
                    str(MCU/'aruco_app/aruco_pose.c'),
                    '-o', str(detector_dll)], check=True, env=env)
    detector = ct.CDLL(str(detector_dll))
    detector.ua_test_image_pose.argtypes = [ct.POINTER(ct.c_ubyte),ct.POINTER(Camera),
                                           ct.POINTER(Pose),ct.POINTER(ct.c_float),ct.POINTER(ct.c_int)]
    # Half one snapshot pixel = 4 full720 pixels. This coarse-image gate is
    # deliberately distinct from the 2px gate in the subpixel solver tests.
    camera_image = Camera(1,1280,720,900,900,640,360,0,0,0,0,0,.08,4)
    ki = np.array([[900,0,640],[0,900,360],[0,0,1]],np.float64)
    dictionary = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50)
    marker = cv2.aruco.generateImageMarker(dictionary,23,120)
    image_results, panels = [], []
    rtl_sources=['host/tests/tb_aruco_image_link.sv','rtl/user/aruco/ua_aruco_peripheral.v',
                 'rtl/user/aruco/ua_aruco_snapshot.v','rtl/user/aruco/ua_aruco_ahb_bridge.v',
                 'rtl/user/aruco/ua_servo_pwm_safe.v']
    subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb_aruco_image_link',
                    '-Ptb_aruco_image_link.BUS_HALF_NS=10','-Ptb_aruco_image_link.SRC_HALF_NS=8.333',
                    '-Ptb_aruco_image_link.BUBBLES=1','-o',str(TMP/'pose_link.vvp'),*rtl_sources],
                   cwd=ROOT,check=True,capture_output=True)
    for idx,(label,angles,translation,low,high,noise) in enumerate([
        ('frontal',[0,0,0],[0,0,.18],18,230,0),
        ('dark + noise',[0,0,0],[0,0,.18],18,80,2),
        ('tilted',[.32,.28,.15],[0,0,.19],18,230,0),
        ('dark tilted',[-.25,.35,-.22],[.005,0,.20],18,80,2),
        ('far / coarse',[.15,.3,.3],[0,0,.32],18,230,0),
        ('removed',[0,0,0],[0,0,.18],70,70,0)]):
        rotation=cv2.Rodrigues(np.array(angles,np.float64))[0] @ np.diag([1.,-1.,-1.])
        truth=cv2.projectPoints(obj,cv2.Rodrigues(rotation)[0],np.array(translation),ki,None)[0].reshape(4,2)/8
        h=cv2.getPerspectiveTransform(np.float32([[-.5,-.5],[119.5,-.5],[119.5,119.5],[-.5,119.5]]),truth.astype(np.float32))
        image=cv2.warpPerspective(marker,h,(160,90),flags=cv2.INTER_NEAREST,borderValue=255).astype(np.float32)
        image=low+image*((high-low)/255)
        image=np.ascontiguousarray(np.clip(image+rng.normal(0,noise,image.shape),0,255),dtype=np.uint8)
        corners=(ct.c_float*8)();status=ct.c_int();res=Pose()
        marker_id=detector.ua_test_image_pose(image.ctypes.data_as(ct.POINTER(ct.c_ubyte)),
                                             ct.byref(camera_image),ct.byref(res),corners,ct.byref(status))
        assert marker_id == (-1 if label=='removed' else 23), (label,marker_id)
        rtl_checked=False
        if idx in (1,4):
            fixture=TMP/f'scene{idx}_input.hex';output=TMP/f'scene{idx}_output.hex'
            np.savetxt(fixture,image.reshape(-1),fmt='%02x')
            run=subprocess.run(['C:/iverilog/bin/vvp.exe',str(TMP/'pose_link.vvp'),
                                '+INPUT='+fixture.relative_to(ROOT).as_posix(),
                                '+OUTPUT='+output.relative_to(ROOT).as_posix()],
                               cwd=ROOT,check=True,capture_output=True,text=True,timeout=60)
            (TMP/f'scene{idx}_rtl.log').write_text(run.stdout+run.stderr,encoding='utf-8')
            readback=np.loadtxt(output,dtype=np.uint8,converters=lambda text:int(text,16)).reshape(90,160)
            assert np.array_equal(readback,image)
            again=Pose();again_corners=(ct.c_float*8)();again_status=ct.c_int()
            again_id=detector.ua_test_image_pose(readback.ctypes.data_as(ct.POINTER(ct.c_ubyte)),
                                                ct.byref(camera_image),ct.byref(again),again_corners,ct.byref(again_status))
            assert again_id==marker_id and again_status.value==status.value and bytes(again)==bytes(res)
            rtl_checked=True
        detected=np.array(corners).reshape(4,2)
        code=status.value
        row=dict(scene=label,id=marker_id,pose_status=code,pose_valid=bool(res.valid),
                 rms_px=res.rms_px,truth_z_m=translation[2],
                 estimated_z_m=res.translation[2] if res.valid else None,
                 full720_rtl_pose_identical=rtl_checked,
                 corners720=detected.tolist() if marker_id>=0 else [])
        if marker_id>=0:
            assert res.valid, row
            row['position_error_m']=float(np.linalg.norm(np.array(res.translation)-translation))
            row['rotation_error_deg']=float(np.degrees(np.arccos(np.clip((np.trace(np.array(res.rotation).reshape(3,3) @ rotation.T)-1)/2,-1,1))))
            assert row['position_error_m']<.015, row
        image_results.append(row)
        rgb=cv2.cvtColor(cv2.resize(image,(640,360),interpolation=cv2.INTER_NEAREST),cv2.COLOR_GRAY2BGR)
        if marker_id>=0:
            cv2.polylines(rgb,[np.round(detected*.5).astype(np.int32)],True,(20,180,20),2)
        if res.valid:
            cr=np.array(res.rotation).reshape(3,3).astype(np.float64)
            cv2.drawFrameAxes(rgb,ki*.5+np.diag([0,0,.5]),None,cv2.Rodrigues(cr)[0],
                              np.array(res.translation,dtype=np.float64),.035,2)
        panel=np.full((414,640,3),245,np.uint8);panel[:360]=rgb
        cv2.putText(panel,f'{label}: ID={marker_id} pose={"OK" if res.valid else "NO/REJECT"}',
                    (10,381),cv2.FONT_HERSHEY_SIMPLEX,.52,(20,20,20),1,cv2.LINE_AA)
        note=(f'Z={res.translation[2]*1000:.1f}mm (truth {translation[2]*1000:.0f}) RMS={res.rms_px:.2f}px'
              if res.valid else f'status={code}; no distance output')
        cv2.putText(panel,note,(10,404),cv2.FONT_HERSHEY_SIMPLEX,.49,(20,20,20),1,cv2.LINE_AA)
        panels.append(panel)
    cv2.imwrite(str(OUT/'image_to_pose.png'),np.vstack([np.hstack(panels[i:i+2]) for i in (0,2,4)]))
    summary = dict(status='HOST_C_POSE_PASS_NOT_BOARD_VERIFIED', synthetic_camera=True,
                   cases=len(rows), invalid_rejections=invalid_count, max_iterations=16,
                   workspace_bytes=ct.sizeof(Workspace), results=rows, quantized_8px=quantized,
                   image_to_c_detector_to_c_pose=image_results,
                   coarse_image_reprojection_gate_px=camera_image.max_rms_px,
                   input_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in
                                 [Path(__file__), MCU/'aruco_app/aruco_pose.c',MCU/'aruco_app/aruco_pose.h',
                                  MCU/'aruco_app/aruco_detect.c',MCU/'aruco_app/aruco_decode.c',
                                  MCU/'aruco_app/aruco_dictionary.h',MCU/'aruco_app/aruco_refine.c',
                                  MCU/'aruco_app/aruco_refine.h',MCU/'tests/aruco_pose_host.c',
                                  *[ROOT/p for p in rtl_sources]]},
                   limitations=['Single planar solution; not full two-solution IPPE',
                                'No physical camera calibration; runtime pose disabled by default',
                                'Host timing is not MCU timing; no hardware MMIO validation'])
    (OUT / 'validation.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    print('ARUCO_POSE_PASS', len(rows), 'projection cases;', invalid_count, 'invalid rejected')
    print('max noiseless position error m:', max(r['position_error_m'] for r in rows if not r['noise_px']))
    print('max noisy position/rotation errors:', max(r['position_error_m'] for r in rows if r['noise_px']),
          max(r['rotation_error_deg'] for r in rows if r['noise_px']))
    print('quantized snapshot:', quantized)
    print('image-to-pose:',image_results)

if __name__ == '__main__':
    main()
