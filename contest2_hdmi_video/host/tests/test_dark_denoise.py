"""Synthetic pre-tone noise tests; not measured camera performance."""
import random
import statistics
import unittest
from photo_vectors import denoise


class DarkDenoiseTest(unittest.TestCase):
    def test_finite5_noise_across_brightness_gate_and_headroom(self):
        # Include the dark/bright gate transition and the actual 9-bit range.
        for base in (4,24,56,63,64,70,100,160,240,500):
            rng=random.Random(base+10415)
            src=[[tuple(max(0,min(511,base+rng.randint(-12,12)))
                        for _ in range(3)) for _ in range(64)] for _ in range(48)]
            values=lambda image:[c for row in image[8:] for p in row[4:-4] for c in p]
            original=values(src)
            prior=values(denoise(src,window5=False))
            result=values(denoise(src))
            self.assertLess(statistics.pstdev(result),statistics.pstdev(prior))
            self.assertLess(abs(statistics.mean(result)-statistics.mean(original)),1.5)

    def test_downward_spread_is_bounded_in_dark_and_bright_regions(self):
        for level, amplitude in ((24, 12), (100, 8)):
            first = [(level + (x % (2 * amplitude + 1)) - amplitude,) * 3
                     for x in range(64)]
            source = [first] + [[(level,) * 3] * 64 for _ in range(15)]
            old = denoise(source, recursive=True)
            self.assertGreater(len(set(old[3])), 1)
            new = denoise(source)
            for row in new[5:]:
                self.assertEqual(row, [(level,) * 3] * 64)
            for row in denoise(source,window5=False)[3:]:
                self.assertEqual(row, [(level,) * 3] * 64)

    def test_bubbles_do_not_change_neighbour_pixels(self):
        rng = random.Random(723)
        source = [[tuple(80 + rng.randint(-10, 10) for _ in range(3))
                   for _ in range(64)] for _ in range(16)]
        self.assertEqual(denoise(source, bubbles=True),
                         denoise(source, bubbles=False))

    def test_dark_noise_improves_without_colour_shift(self):
        rng = random.Random(721)
        source = [[tuple(base + rng.randint(-12, 12) for base in (28, 24, 20))
                   for _ in range(64)] for _ in range(128)]
        old = denoise(source, bubbles=False, dark_denoise=False,fractional_history=False,recursive=True)
        previous=denoise(source,bubbles=False,recursive=True)
        new = denoise(source, bubbles=False)
        v23 = denoise(source,bubbles=False,window5=False)
        sigmas = []
        for channel in range(3):
            values = lambda image: [p[channel] for row in image[8:] for p in row]
            before = statistics.pstdev(values(source))
            prior = statistics.pstdev(values(old))
            after = statistics.pstdev(values(new))
            # Five-tap finite kernels strengthen noise suppression without IIR.
            self.assertLess(after, before * 0.5)
            self.assertLess(after,statistics.pstdev(values(v23))*0.75)
            self.assertLess(abs(statistics.mean(values(new)) -
                                statistics.mean(values(source))), 1.5)
            sigmas.append((before,prior,statistics.pstdev(values(previous)),statistics.pstdev(values(v23)),after))
        print('DARK_NOISE_SYNTHETIC_SIGMA input/v20/v22/v23/v24', sigmas)

    def test_bright_path_unchanged(self):
        rng = random.Random(722)
        source = [[tuple(base + rng.randint(-6, 6) for base in (160, 170, 150))
                   for _ in range(32)] for _ in range(32)]
        self.assertEqual(denoise(source), denoise(source, dark_denoise=False))

    def test_dark_strong_contours_unchanged(self):
        # A dark/bright boundary and a saturated thin finger-colour stroke.
        source = [[(8, 8, 8) if x < 12 else (48, 48, 48)
                   for x in range(32)] for _ in range(16)]
        for row in source:
            row[24] = (90, 24, 12)
        self.assertEqual(denoise(source), source)

    def test_black_constant_frame_history_and_limits(self):
        for value in (0, 1, 24, 63, 64, 255, 511):
            image = [[(value,) * 3] * 16 for _ in range(16)]
            self.assertEqual(denoise(image), image)
        # A separate call models a fresh frame; no temporal ghosting.
        denoise([[(511,) * 3] * 16 for _ in range(16)])
        black = [[(0,) * 3] * 16 for _ in range(16)]
        self.assertEqual(denoise(black), black)

    def test_first_row_noise_must_not_become_vertical_bands(self):
        first=[(24+(x%9)-4,)*3 for x in range(64)]
        src=[first]+[[(24,)*3]*64 for _ in range(63)]
        old=denoise(src,bubbles=False,fractional_history=False,recursive=True)
        self.assertGreater(len(set(old[-1])),1)  # v21 failure is reproduced.
        new=denoise(src,bubbles=False)
        self.assertEqual(new[-1],[(24,)*3]*64)
        for level in (0,1,24,62,63,64,65,128,250,510,511):
            initial=[(max(0,min(511,level+(x%9)-4)),)*3 for x in range(64)]
            image=[initial]+[[(level,)*3]*64 for _ in range(63)]
            self.assertEqual(denoise(image,bubbles=False)[-1],[(level,)*3]*64)


if __name__ == '__main__':
    unittest.main()
