"""Numeric contracts for the spatial recursive filter; not camera measurements."""
import random
import statistics
import unittest

from photo_vectors import close, denoise


class RecursiveDenoiseTest(unittest.TestCase):
    def test_flat_noise_vs_previous_fir(self):
        rng=random.Random(104)
        src=[[tuple(60+rng.randint(-6,6) for _ in range(3))
              for x in range(64)] for y in range(128)]
        horizontal=[]
        for row in src:
            out=[]
            for x,c in enumerate(row):
                l=row[max(0,x-1)]
                r=c if x==7 else row[min(len(row)-1,x+1)]
                l=l if close(c,l) else c
                r=r if close(c,r) else c
                out.append(tuple((a+2*b+d+2)//4 for a,b,d in zip(l,c,r)))
            horizontal.append(out)
        old=[[(tuple((3*a+b+2)//4 for a,b in zip(c,horizontal[y-1][x]))
               if close(c,horizontal[y-1][x]) else c)
              for x,c in enumerate(row)] for y,row in enumerate(horizontal[1:],1)]
        new=denoise(src)[1:]
        sigma=lambda image:statistics.pstdev(c for row in image for p in row for c in p)
        self.assertLess(sigma(new),sigma(old)*0.85)
        original_mean=statistics.mean(c for row in src[1:] for p in row for c in p)
        result_mean=statistics.mean(c for row in new for p in row for c in p)
        self.assertLess(abs(result_mean-original_mean),1.0)

    def test_horizontal_edge_cuts_feedback(self):
        src=[[(32,36,28)]*16 for _ in range(4)]+[[(220,225,212)]*16 for _ in range(4)]
        self.assertEqual(denoise(src),src)

    def test_colour_stroke_and_diagonal(self):
        src=[[(24,28,20) if x<y+3 else (200,210,190)
              for x in range(16)] for y in range(8)]
        for row in src: row[12]=(240,20,40)
        self.assertEqual(denoise(src),src)

    def test_separate_frames_have_no_history(self):
        denoise([[(220,220,220)]*16 for _ in range(8)])
        dark=[[(4,5,3)]*16 for _ in range(8)]
        self.assertEqual(denoise(dark),dark)


if __name__=='__main__': unittest.main()
