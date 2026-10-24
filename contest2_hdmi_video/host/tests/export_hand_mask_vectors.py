"""Generate oracle masks from full HDMI-frame four-pixel sums, no labels."""
import argparse
import json
from pathlib import Path
import sys
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from hand_fpga_grid_model import masks
from hand_ccl_prototype import file_sha256

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--input',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
p.add_argument('--frames',required=True,help='Comma-separated zero-based source frames')
a=p.parse_args();a.out.mkdir(parents=True,exist_ok=False)
words=np.memmap(a.input/'groups.bin',dtype='>u4',mode='r').reshape(-1,180,320)
selected=[int(s) for s in a.frames.split(',')];records=[]
for frame in selected:
    packed=words[frame];rgb=[((packed>>s)&1023).astype(np.int32) for s in (20,10,0)]
    r,g,b=[((v[1::2,::2]+v[1::2,1::2])>>1) for v in rgb]
    seed,grown=masks(r,g,b);rg=r-g;gb=g-b
    loose=((r>=16)&(rg>=4)&(12*rg>=r)&(gb>=0)&(32*gb>=g)&(rg<=3*np.maximum(gb,8)))
    pixels=seed.astype(np.uint32)|(loose.astype(np.uint32)<<1)|(grown.astype(np.uint32)<<2)
    output=[]
    for y in range(90):
        for wc in range(27):
            value=0
            for slot in range(6):
                x=wc*6+slot
                if x<160:value|=int(pixels[y,x])<<(slot*3)
            output.append(f'{value:05x}\n')
    path=a.out/f'frame_{frame:04d}.hex';path.write_text(''.join(output),encoding='ascii')
    records.append(dict(frame=frame,path=str(path.resolve()),sha256=file_sha256(path)))
(a.out/'manifest.json').write_text(json.dumps(dict(status='MASK_ORACLE_ONLY_NOT_CLASSIFIER',
    groups_sha256=file_sha256(a.input/'groups.bin'),model_sha256=file_sha256(Path(__file__).resolve().parents[1]/'hand_fpga_grid_model.py'),
    frames=records),indent=2),encoding='utf-8')
print(f'MASK_VECTORS_READY frames={len(records)} words_per_frame=2430')
