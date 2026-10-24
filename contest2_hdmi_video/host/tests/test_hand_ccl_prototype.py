"""Algorithm plumbing tests, not evidence of real-camera recognition accuracy."""
import sys
from pathlib import Path
import unittest
import cv2
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from hand_ccl_prototype import features,candidate_regions,unpack_sums


class ContourSafety(unittest.TestCase):
    def test_lobe_fist_point_open_and_ambiguous_v(self):
        palm=np.zeros((180,320),np.uint8)
        cv2.circle(palm,(160,100),25,1,-1)
        cv2.rectangle(palm,(148,110),(172,170),1,-1)
        for fingers,expected in [([],1),([160],2),([140,160,180],3),([145,175],0)]:
            mask=palm.copy()
            for x in fingers:cv2.rectangle(mask,(x-4,20),(x+4,100),1,-1)
            result=features(mask,120,15,81,156,.82,'lobe')
            self.assertEqual(result['raw'],expected,(fingers,result))

    def test_no_first_frame_state_and_no_seed_growth(self):
        zeros=np.zeros((180,320),np.int32)
        count,regions=candidate_regions(zeros,zeros,zeros,'hybrid',3)
        self.assertEqual(count,0);self.assertEqual(regions,[])
        _,unseeded=candidate_regions(zeros+80,zeros+60,zeros+40,'hybrid',3)
        self.assertEqual(unseeded,[])
        # A hand-coloured object in the very first frame is segmented without
        # registering an empty scene or reading any previous frame.
        r=zeros.copy();g=zeros.copy();b=zeros.copy()
        cv2.circle(r,(160,100),25,320,-1);cv2.circle(g,(160,100),25,240,-1);cv2.circle(b,(160,100),25,160,-1)
        first=candidate_regions(r,g,b,'hybrid',3)
        second=candidate_regions(r,g,b,'hybrid',3)
        self.assertGreater(len(first[1]),0)
        self.assertTrue(np.array_equal(first[1][0][0],second[1][0][0]))

    def test_sums_stress_bounds(self):
        packed=np.array([[0,(1020<<20)|(512<<10)|12]],np.uint32)
        a=unpack_sums(packed,(200,50,100),64,np.random.default_rng(4))
        b=unpack_sums(packed,(200,50,100),64,np.random.default_rng(4))
        for x,y in zip(a,b):
            self.assertTrue(np.array_equal(x,y));self.assertTrue(((x>=0)&(x<=1020)).all())

    def test_empty(self):
        self.assertIsNone(features(np.zeros((180,320),np.uint8),10,10,60,60))

    def test_synthetic_fist_and_point(self):
        mask=np.zeros((180,320),np.uint8)
        cv2.circle(mask,(160,100),25,1,-1)
        self.assertEqual(features(mask,130,70,61,61)['raw'],1)
        cv2.rectangle(mask,(154,30),(165,90),1,-1)
        self.assertEqual(features(mask,130,25,61,111)['raw'],2)

    def test_noise_and_bridges_never_crash(self):
        rng=np.random.default_rng(417041)
        for _ in range(200):
            mask=(rng.random((70,80))>.45).astype(np.uint8)
            for mode in ('legacy','lobe'):
                result=features(mask,0,0,80,70,.82,mode)
                if result is not None:
                    self.assertIn(result['raw'],range(4))
                    if result['invalid_defects']:self.assertEqual(result['raw'],0)


if __name__=='__main__':unittest.main()
