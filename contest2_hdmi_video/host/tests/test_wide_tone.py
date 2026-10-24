import unittest
from photo_vectors import wide_tone,tone

class WideToneTests(unittest.TestCase):
    def test_all_codes_monotone_bounded_no_black_floor(self):
        values=[wide_tone(c) for c in range(512)]
        self.assertEqual(values,sorted(values))
        self.assertEqual(values[0],0)
        self.assertTrue(all(0<v<=254 for v in values[1:]))
        self.assertEqual(wide_tone(255),240)
        self.assertEqual(wide_tone(510),254)

    def test_shadow_separation_and_midtones(self):
        for c in (1,2,4,8,16):
            self.assertGreater(wide_tone(c),tone(c,0))
        for c in (32,64,96,128):
            self.assertLessEqual(abs(wide_tone(c)-tone(c,0)),6)

    def test_two_times_gain_highlights_no_long_white_plateau(self):
        previous={tone(min(255,2*c),0) for c in range(128,256)}
        improved={wide_tone(2*c) for c in range(128,256)}
        self.assertEqual(len(previous),1)
        self.assertGreaterEqual(len(improved),12)
        self.assertLess(wide_tone(256),wide_tone(510))

if __name__=="__main__":unittest.main()
