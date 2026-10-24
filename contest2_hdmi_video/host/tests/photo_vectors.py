"""Independent scalar scoreboard vectors for the packed RTL photo pipeline."""
from pathlib import Path
import random
import statistics
import argparse

def close(a,b,dark_denoise=True):
    t=(24 if dark_denoise else 18) if max(a)<64 else 12
    return max(abs(x-y) for x,y in zip(a,b))<=t

def blend(c,n,dark_denoise=True):
    if not close(c,n,dark_denoise):return c
    if dark_denoise and max(c)<64 and max(n)<64:
        return tuple((x+3*y+2)//4 for x,y in zip(c,n))
    return tuple((x+y+1)//2 for x,y in zip(c,n))

def legacy_tone(c,s):
    if c<16:v=c//2
    elif c<32:
        d=c-16;v=8+d+(d//2 if s==2 else 0)
    elif s==2:
        if c<64:d=c-32;v=32+d+d//2+d//4
        elif c<128:d=c-64;v=88+d+d//2
        elif c<192:d=c-128;v=184+d-d//4
        else:d=c-192;v=232+d//4+d//8
    elif s==1:
        if c<64:d=c-32;v=24+d+d//2
        elif c<128:d=c-64;v=72+d+d//4
        elif c<192:d=c-128;v=152+d
        else:d=c-192;v=216+d//2+d//8
    else:
        if c<64:v=c-8
        elif c<128:d=c-64;v=56+d+d//8
        elif c<192:d=c-128;v=128+d+d//8
        else:d=c-192;v=200+d-d//8
    return 255 if c==255 else min(255,v)

def srgb(c):
    x=c/255.0
    y=12.92*x if x<=0.0031308 else 1.055*x**(1/2.4)-0.055
    return max(0,min(255,int(y*255+0.5)))

def tone(c,s):
    # A smooth return avoids a steep local transition at linear code 8.
    # Display-encoded noise shaping, not another RAW pedestal subtraction.
    y=srgb(c)
    reduction=10 if y<=128 else int(10*(255-y)/127+0.5)
    y=max(0,y-reduction)
    anchors=((0,0),(16,6),(32,20),(64,48),(128,144),(192,216),(224,240),(255,255))
    for (a,b),(d,e) in zip(anchors,anchors[1:]):
        if y<=d:
            return b+((y-a)*(e-b)+(d-a)//2)//(d-a)

def wide_tone(c):
    anchors=((0,0),(1,3),(2,6),(4,14),(8,28),(16,48),(32,88),
             (64,144),(96,177),(128,206),(160,216),(192,228),(224,235),
             (255,240),(320,246),(384,250),(448,252),(510,254),(511,254))
    for (a,b),(d,e) in zip(anchors,anchors[1:]):
        if c<=d:
            return b+((c-a)*(e-b)+(d-a)//2)//(d-a)
    raise ValueError("9-bit tone input out of range")

def saturate(p):
    lo,hi=min(p),max(p)
    if lo<=24 or hi>=224 or hi<=80 or hi-lo<=16:
        return p
    mid=(lo+hi)//2
    return tuple(min(255,c+(c-mid)//4) if c>=mid else max(0,c-(mid-c)//4) for c in p)

def finish(p,s,enabled=True):
    return saturate(tuple(tone(c,s) for c in p)) if enabled else p

def denoise(image,bubbles=True,dark_denoise=True,fractional_history=True,recursive=False,true_neighbours=True,window5=True):
    five=window5 and not recursive and len(image[0])>=16
    weights=(1,2,2,2,1)
    h=[]
    for row in image:
        out=[]
        for x,c in enumerate(row):
            if five:
                neighbours=[row[max(0,min(len(row)-1,x+k-2))] for k in range(5)]
                neighbours=[n if close(c,n,dark_denoise) else c for n in neighbours]
                out.append(tuple((sum(w*n[ch] for w,n in zip(weights,neighbours))+4)//8 for ch in range(3)))
                continue
            l=row[max(0,x-1)]
            # The testbench inserts two invalid cycles after group 1.
            r=c if not true_neighbours and bubbles and x==7 else row[min(len(row)-1,x+1)]
            if not close(c,l,dark_denoise):l=c
            if not close(c,r,dark_denoise):r=c
            out.append(tuple((a+2*b+d+2)//4 for a,b,d in zip(l,c,r)))
        h.append(out)
    result=[]
    states=[]
    for y,row in enumerate(h):
        if not recursive:
            out=[]
            for x,c in enumerate(row):
                if five:
                    neighbours=[h[y-k][x] if y>=k else c for k in range(5)]
                    neighbours=[n if close(c,n,dark_denoise) else c for n in neighbours]
                    out.append(tuple((sum(w*n[ch] for w,n in zip(weights,neighbours))+4)//8 for ch in range(3)))
                    continue
                a=h[y-1][x] if y and close(c,h[y-1][x],dark_denoise) else c
                b=h[y-2][x] if y>=2 and len(row)>=16 and close(c,h[y-2][x],dark_denoise) else c
                out.append(tuple((v+2*n+m+2)//4 for v,n,m in zip(c,a,b)))
            result.append(out)
        elif fractional_history and len(row)>=16:
            new_states=[]
            for x,c in enumerate(row):
                if y==0:
                    value=tuple(v*16 for v in c)
                else:
                    prior=states[y-1][x]
                    whole=tuple((v+8)//16 for v in prior)
                    if close(c,whole,dark_denoise):
                        if dark_denoise and max(c)<64 and max(whole)<64:
                            value=tuple((v*16+3*n+2)//4 for v,n in zip(c,prior))
                        else:
                            value=tuple((v*16+n+1)//2 for v,n in zip(c,prior))
                    else:
                        value=tuple(v*16 for v in blend(c,whole,dark_denoise))
                new_states.append(value)
            states.append(new_states)
            result.append([tuple((v+8)//16 for v in pixel) for pixel in new_states])
        else:
            prior=result[y-1] if len(row)>=16 and y else (h[y-1] if y else None)
            result.append([c if y==0 else blend(c,prior[x],dark_denoise) for x,c in enumerate(row)])
    return result

def packed(pixels,bits=8):
    value=0
    for p in pixels:
        for c in p:value=(value<<bits)|c
    return f'{value:0{(12*bits+3)//4}x}'

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--width',type=int,default=16)
    parser.add_argument('--tone-enable',type=int,choices=(0,1),default=1)
    parser.add_argument('--bubbles',type=int,choices=(0,1),default=1)
    parser.add_argument('--input-bits',type=int,choices=(8,9),default=8)
    parser.add_argument('--dark-noise',action='store_true',
                        help='exercise noisy pre-tone shadows in every channel')
    parser.add_argument('--window5',type=int,choices=(0,1),default=1)
    parser.add_argument('--height',type=int,default=8)
    parser.add_argument('--seed',type=int,default=7138)
    args=parser.parse_args()
    assert args.width>=4 and args.width%4==0
    assert args.height>=1
    rng=random.Random(args.seed);src=[];dst=[]
    for f,s in enumerate((2,1,0)):
        image=[]
        for y in range(args.height):
            row=[]
            for x in range(args.width):
                base=((0,0,0),(40,42,38),(185,75,40),(250,250,250))[(x%16)//4]
                if args.dark_noise:
                    base=(14,12,10) if x%16<12 else (180,180,180)
                if f==1:
                    # Horizontal discontinuity must break recursive history.
                    base=(24,28,20) if y<4 else (210,218,202)
                elif f==2:
                    # Diagonal boundary, coloured one-pixel stroke, flat field.
                    base=(42,45,39) if x%16<y+3 else (176,181,168)
                    if x%16==12: base=(220,32,45)
                noise_span=6 if args.dark_noise else 5
                pixel=tuple(max(0,min(255,c+rng.randint(-noise_span,noise_span))) for c in base)
                if args.input_bits==9:
                    pixel=(pixel[0]*2,pixel[1],pixel[2]*2)
                row.append(pixel)
            image.append(row)
        filtered=denoise(image,bool(args.bubbles),window5=bool(args.window5))
        for y in range(args.height):
            for g in range(args.width//4):
                src.append(packed(image[y][g*4:g*4+4],args.input_bits))
                pixels=filtered[y][g*4:g*4+4]
                if args.input_bits==9:
                    output=[saturate(tuple(wide_tone(c) for c in p)) if args.tone_enable
                            else tuple(min(255,c) for c in p) for p in pixels]
                else:output=[finish(p,s,bool(args.tone_enable)) for p in pixels]
                dst.append(packed(output))
    out=Path('tmp/photo_tests');out.mkdir(parents=True,exist_ok=True)
    (out/'input.hex').write_text('\n'.join(src)+'\n',encoding='ascii')
    (out/'expected.hex').write_text('\n'.join(dst)+'\n',encoding='ascii')
    (out/'gamma.hex').write_text('\n'.join(f'{tone(c,0):02x}' for c in range(256))+'\n',encoding='ascii')
    (out/'gamma_wide.hex').write_text('\n'.join(f'{wide_tone(c):02x}' for c in range(512))+'\n',encoding='ascii')
    alignment=[saturate((wide_tone(2*(c+f)),wide_tone(c+f),wide_tone(2*(c+f))))
               for f in range(3) for c in (24,60,160,240)]
    (out/'alignment_wide.hex').write_text('\n'.join(f'{p[0]:02x}{p[1]:02x}{p[2]:02x}' for p in alignment)+'\n',encoding='ascii')
    for s in range(3):
        values=[tone(c,s) for c in range(256)]
        assert values[0]==0 and values[-1]==255 and values==sorted(values)
    # Constant patch noise reduction, before tone gain. No large-edge blending.
    patch=[[tuple(60+rng.randint(-4,4) for _ in range(3)) for x in range(16)] for y in range(64)]
    filtered=denoise(patch)
    a=[c for row in patch[1:] for p in row for c in p]
    b=[c for row in filtered[1:] for p in row for c in p]
    before=statistics.pstdev(a);after=statistics.pstdev(b)
    assert after<before*.85
    assert not close((32,32,32),(230,230,230))
    print(f'PHOTO_MODEL_PASS words={len(src)} tone_enable={args.tone_enable} tone_monotone=3/3 flat_noise_sigma={before:.3f}->{after:.3f}')

if __name__=='__main__':main()
