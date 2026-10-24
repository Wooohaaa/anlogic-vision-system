import unittest
from photo_vectors import srgb,tone,saturate


class SoftToeTests(unittest.TestCase):
    def test_all_levels_monotone_endpoints_and_strength_independent(self):
        a=[tone(c,0) for c in range(256)]
        self.assertEqual(a,sorted(a))
        self.assertEqual((a[0],a[-1]),(0,255))
        for s in range(4):self.assertEqual(a,[tone(c,s) for c in range(256)])

    def test_no_hard_black_threshold_and_bounded_contrast(self):
        a=[tone(c,0) for c in range(9)]
        self.assertTrue(all(x<y for x,y in zip(a,a[1:])))
        self.assertEqual(a[1],1)
        for c in range(1,256):
            self.assertGreater(tone(c,0),0)
            self.assertLessEqual(abs(srgb(c)-tone(c,0)),27)
        self.assertEqual(tone(255,0),srgb(255))

    def test_dark_one_code_flicker_reduced(self):
        self.assertLess(tone(1,0)-tone(0,0),srgb(1)-srgb(0))
        self.assertEqual(tone(1,0)-tone(0,0),1)

    def test_saturation_neutral_and_gamut_guards(self):
        for c in range(256):
            self.assertEqual(saturate((c,c,c)),(c,c,c))
        for p in ((0,80,60),(245,120,70),(32,40,35),(128,132,129)):
            self.assertEqual(saturate(p),p)
        self.assertEqual(saturate((180,100,60)),(195,95,45))
        for p in ((44,58,36),(40,60,35),(64,80,50),(23,150,90),(190,224,100)):
            self.assertEqual(saturate(p),p)

    def test_contrast_darkens_shadows_and_lifts_high_midtones(self):
        def previous(c):
            y=srgb(c)
            return max(0,y-(10 if y<=128 else int(10*(255-y)/127+0.5)))
        for c in (4,8,16,32):
            self.assertLess(tone(c,0),previous(c))
        for c in (96,128,160,192):
            self.assertGreater(tone(c,0),previous(c))


if __name__=='__main__':unittest.main()
