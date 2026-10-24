import importlib.util
import unittest
from pathlib import Path
import cv2
import numpy as np

spec=importlib.util.spec_from_file_location('calibration',Path(__file__).resolve().parents[1]/'calibrate_aruco_camera.py')
cal=importlib.util.module_from_spec(spec);spec.loader.exec_module(cal)

class CalibrationTest(unittest.TestCase):
    def test_synthetic_fit_and_header(self):
        k=np.array([[900.,0,640],[0,910.,360],[0,0,1]])
        d=np.array([-.08,.01,.001,-.001,0.])
        obj=np.zeros((54,3),np.float32);obj[:,:2]=np.mgrid[0:9,0:6].T.reshape(-1,2)*.02
        rng=np.random.default_rng(37120);objs=[];imgs=[]
        for _ in range(30):
            r=rng.uniform(-.45,.45,3);t=rng.uniform([-.17,-.14,.45],[.05,.03,.8])
            img=cv2.projectPoints(obj,r,t,k,d)[0].astype(np.float32)
            objs.append(obj.copy());imgs.append(img)
        kk,dd,q=cal.fit(objs,imgs,(1280,720))
        self.assertLess(q['rms_px'],.001)
        np.testing.assert_allclose(kk,k,atol=.05)
        self.assertIn('0.12',cal.header(kk,dd,120))
        self.assertIn('UA_ARUCO_CAMERA_AVAILABLE 1',cal.header(kk,dd,120))
        with self.assertRaises(ValueError):cal.fit(objs[:3],imgs[:3],(1280,720))
        with self.assertRaises(ValueError):cal.fit(objs,imgs,(640,360))
        with self.assertRaises(ValueError):cal.fit(objs,[imgs[0]]*30,(1280,720))
        with self.assertRaises(ValueError):cal.header(kk,dd,float('nan'))

if __name__=='__main__':unittest.main()
