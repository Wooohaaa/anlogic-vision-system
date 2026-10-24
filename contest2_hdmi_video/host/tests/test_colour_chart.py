import sys
import unittest
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from verify_colour_chart import expected_chart


class ColourChartTest(unittest.TestCase):
    def test_complete_geometry_and_codes(self):
        rgb=expected_chart()
        self.assertEqual(rgb.shape,(720,1280,3))
        self.assertEqual(rgb.dtype,np.uint8)
        self.assertEqual(rgb[0,0].tolist(),[255,0,0])
        self.assertEqual(rgb[0,160].tolist(),[0,255,0])
        self.assertEqual(rgb[0,320].tolist(),[0,0,255])
        self.assertEqual(rgb[239,1279].tolist(),[0,0,0])
        for value in range(256):
            self.assertEqual(rgb[300,value*4].tolist(),[value]*3)
        for value in range(16):
            self.assertEqual(rgb[600,value*64].tolist(),[value]*3)
        self.assertTrue(np.all(rgb[240:,1024:]==255))
        self.assertTrue(np.array_equal(rgb[240:,:,:1],rgb[240:,:,1:2]))
        self.assertTrue(np.array_equal(rgb[240:,:,1:2],rgb[240:,:,2:3]))

    def test_short_chart_geometry(self):
        self.assertTrue(np.array_equal(expected_chart(16),expected_chart()[:16]))

    def test_bad_height(self):
        for height in (0,721):
            with self.assertRaises(ValueError):expected_chart(height)


if __name__=='__main__':unittest.main()
