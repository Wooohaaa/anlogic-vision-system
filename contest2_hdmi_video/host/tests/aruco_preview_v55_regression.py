"""Quality-gated C preview: synthetic oracle and real HDMI corner replay.
Real-video silhouettes are diagnostic references, NOT pose ground truth.
No hardware/programming APIs.
"""
import ctypes as ct,hashlib,json,os,subprocess,time,re
from pathlib import Path
import cv2
import numpy as np
from aruco_pose_regression import ROOT,MCU,Point,Workspace
def main():
 out=ROOT/'tmp/v55_preview';out.mkdir(exist_ok=True)
 sources=[MCU/'aruco_app/aruco_pose.c',MCU/'aruco_app/aruco_pose.h',MCU/'aruco_app/aruco_camera_config.h',Path(__file__)]
 nominal=float(re.search(r'#define UA_ARUCO_AXES_NOMINAL_FOCAL_PX ([0-9.]+)f',sources[2].read_text())[1])
 before={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
 env=dict(os.environ,PATH='C:/msys64/ucrt64/bin;'+os.environ['PATH'])
 dll=out/'preview.dll'
 subprocess.run(['C:/msys64/ucrt64/bin/gcc.exe','-std=c99','-O2','-Wall','-Wextra','-Werror','-shared',str(sources[0]),'-o',str(dll)],env=env,check=True)
 os.add_dll_directory('C:/msys64/ucrt64/bin');lib=ct.CDLL(str(dll));ws=Workspace()
 fn=lib.ua_aruco_axes_preview;fn.argtypes=[ct.POINTER(Point),ct.c_uint,ct.c_uint,ct.c_float,ct.POINTER(Workspace),ct.POINTER(Point),ct.POINTER(ct.c_uint)]
 old=lib.ua_aruco_axes_estimated;old.argtypes=[ct.POINTER(Point),ct.c_uint,ct.c_uint,ct.c_float,ct.POINTER(Point)]
 def call(q,focal=640):
  p=(Point*4)(*[Point(*a) for a in q]);result=(Point*4)();normal=ct.c_uint(99)
  start=time.perf_counter_ns();ok=fn(p,1280,720,focal,ct.byref(ws),result,ct.byref(normal));elapsed=(time.perf_counter_ns()-start)/1000
  baseline=(Point*4)();previous=old(p,1280,720,focal,baseline)
  got=np.array([[p.x,p.y] for p in result]);base=np.array([[p.x,p.y] for p in baseline])
  assert ok==previous
  if ok:assert np.max(np.abs(got[:3]-base[:3]))<.001
  if ok and not normal.value:assert np.array_equal(got[0],got[3])
  if not ok:assert not got.any() and normal.value==0
  return ok,normal.value,got,elapsed
 rng=np.random.default_rng(55);K=np.array([[640,0,639.5],[0,640,359.5],[0,0,1]],float)
 obj=np.array([[-.5,.5,0],[.5,.5,0],[.5,-.5,0],[-.5,-.5,0]],float);axes=np.array([[0,0,0],[.5,0,0],[0,.5,0],[0,0,.5]],float)
 synthetic=0;visible=0;worst=0;times=[]
 for _ in range(400):
  R=cv2.Rodrigues(rng.uniform([-.6,-.6,-3.14],[.6,.6,3.14]))[0]@np.diag([1.,-1.,-1.]);t=rng.uniform([-.5,-.3,2],[.5,.3,5])
  q=cv2.projectPoints(obj,cv2.Rodrigues(R)[0],t,K,None)[0].reshape(4,2)
  if np.any(q<0) or np.any(q>[1279,719]):continue
  expected=cv2.projectPoints(axes,cv2.Rodrigues(R)[0],t,K,None)[0].reshape(4,2)
  ok,normal,got,us=call(q);assert ok;synthetic+=1;times.append(us)
  if normal:
   if np.any(expected[3]<0) or np.any(expected[3]>[1279,719]):continue
   error=float(np.max(np.abs(got[3]-expected[3])));assert error<.15,error;visible+=1;worst=max(worst,error)
 assert synthetic>300 and visible>250,(synthetic,visible)
 # Unequal sides/shear are not a trustworthy 3-D square under this K.
 inconsistent=np.array([[350,150],[850,150],[1000,650],[350,650]],float)
 assert call(inconsistent)[0:2]==(1,0)
 for q in [np.zeros((4,2)),np.array([[0,0],[0,100],[100,100],[100,0]],float),np.full((4,2),np.nan)]:assert not call(q)[0]
 video=json.loads((ROOT/'tmp/aruco_video_20261019_185443/analysis.json').read_text());rows=[]
 assert call(next(r for r in video['records'] if r['frame']==665)['reference_corners'],640)[1]==0
 for row in video['records']:
  ok,normal,got,us=call(row['reference_corners'],nominal);times.append(us)
  rows.append(dict(frame=row['frame'],planar_valid=bool(ok),normal_valid=bool(normal),points=got.tolist(),host_call_us=us))
 assert 0<sum(r['normal_valid'] for r in rows)<len(rows)
 assert before=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
 report=dict(status='QUALITY_GATED_NOMINAL_AXES_C_REGRESSION_PASS_NOT_BOARD',hashes=before,nominal_focal_px=nominal,synthetic_cases=synthetic,synthetic_visible_z_cases=visible,max_synthetic_z_error_px=worst,video_cases=len(rows),video_visible_z=sum(r['normal_valid'] for r in rows),video_hidden_z=sum(r['planar_valid'] and not r['normal_valid'] for r in rows),host_mean_us=float(np.mean(times)),host_max_us=max(times),host_times_are_not_mcu_benchmarks=True,measured_camera_calibration=False,rows=rows)
 (out/'result.json').write_text(json.dumps(report,indent=2));print(json.dumps({k:v for k,v in report.items() if k not in ('hashes','rows')}))
if __name__=='__main__':main()
