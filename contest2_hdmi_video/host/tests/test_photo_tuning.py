"""Arithmetic invariants for numerical candidates, not hardware tests."""
import sys
import unittest
from pathlib import Path
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from preview_photo_tuning import finish, tone_lut


class PhotoTuningTest(unittest.TestCase):
    anchors = [(0,0),(16,16),(32,38),(64,84),(128,152),(192,208),(224,235),(255,255)]

    def test_neutral_ramp(self):
        ramp = np.repeat(np.arange(256, dtype=np.uint8)[None,:,None], 3, axis=2)
        result = finish(ramp, (1,1,1), self.anchors, 272)
        self.assertTrue(np.array_equal(result[0,:,0], tone_lut(self.anchors)))
        self.assertTrue(np.array_equal(result[:,:,0], result[:,:,1]))
        self.assertTrue(np.array_equal(result[:,:,0], result[:,:,2]))

    def test_shadow_correction_preserves_white_and_black(self):
        patches = np.array([[[0,0,0],[255,255,255],[224,224,224]]], dtype=np.uint8)
        result = finish(patches, (1.12,.84,1.25), [(0,0),(255,255)], 256, True)
        self.assertTrue(np.array_equal(result, patches))

    def test_random_gamut_bounded(self):
        rgb = np.random.default_rng(720).integers(0,256,(64,128,3),dtype=np.uint8)
        result = finish(rgb, (1.12,.84,1.25), self.anchors, 272, True)
        self.assertEqual(result.shape, rgb.shape)
        self.assertEqual(result.dtype, np.uint8)

    def test_fixed_curve_no_scene_dependence(self):
        a = np.full((1,1,3), 64, dtype=np.uint8)
        b = np.concatenate((a, np.full_like(a,255)), axis=1)
        self.assertTrue(np.array_equal(finish(a,(1,1,1),self.anchors,256),
                                      finish(b,(1,1,1),self.anchors,256)[:,:1]))


if __name__ == '__main__':
    unittest.main()
