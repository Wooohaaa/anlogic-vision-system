"""Uncalibrated square-consistency candidate, split-temporal validation.
Not a camera calibration: assumes centered principal point, square pixels and
zero distortion. It does not establish true metric/pose accuracy.
"""
from pathlib import Path
import cv2,json,numpy as np,hashlib
ROOT=Path(__file__).resolve().parents[2]
source=ROOT/'tmp/aruco_video_20261019_185443/analysis.json'
records=json.loads(source.read_text())['records']
H=np.array([cv2.getPerspectiveTransform(np.array([[0,0],[1,0],[1,1],[0,1]],np.float32),np.array(r['reference_corners'],np.float32)) for r in records])
def score(f):
 A=np.array([[1/f,0,-639.5/f],[0,1/f,-359.5/f],[0,0,1]])@H
 a=A[:,:,0];b=A[:,:,1];aa=np.sum(a*a,axis=1);bb=np.sum(b*b,axis=1);ab=np.sum(a*b,axis=1)
 return np.sqrt((2*ab/(aa+bb))**2+((aa-bb)/(aa+bb))**2)
groups=[np.array([r['time']<7.5 for r in records]),np.array([r['time']>=7.5 for r in records])]
fits=[];candidates=np.arange(400,3001,10)
for group in groups:
 objectives=[float(np.median(score(f)[group])) for f in candidates];best=int(candidates[np.argmin(objectives)])
 holdout=float(np.median(score(best)[~group]));old=float(np.median(score(640)[~group]));assert holdout<old
 fits.append(dict(train_views=int(group.sum()),candidate_f_px=best,train_score=min(objectives),holdout_score=holdout,holdout_old640_score=old))
best=int(min(candidates,key=lambda f:np.median(score(f))))
result=dict(status='NOMINAL_FOCAL_SQUARE_CONSISTENCY_IMPROVES_TEMPORAL_HOLDOUT_NOT_CALIBRATION',assumed_principal_point=[639.5,359.5],all_views_candidate_f_px=best,rounded_display_candidate_f_px=1600,old640_median_score=float(np.median(score(640))),candidate1600_median_score=float(np.median(score(1600))),temporal_splits=fits,source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),physical_marker_square_confirmed_by_user=True,measured_distortion=False)
(ROOT/'tmp/v55_preview/focal_audit.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
