"""Streaming row-envelope prototype and independent synthetic tilted templates."""
import os,shutil
from pathlib import Path
import cv2,numpy as np,json
ROOT=Path(__file__).resolve().parents[1]
GLYPHS=['01110/10001/10001/10001/10001/10001/01110','00100/01100/00100/00100/00100/00100/01110',
 '01110/10001/00001/00010/00100/01000/11111','11110/00001/00001/01110/00001/00001/11110',
 '00010/00110/01010/10010/11111/00010/00010','11111/10000/10000/11110/00001/00001/11110',
 '01110/10000/10000/11110/10001/10001/01110','11111/00001/00010/00100/01000/01000/01000',
 '01110/10001/10001/01110/10001/10001/01110','01110/10001/10001/01111/00001/00001/01110']
def normalize(mask,box):
 x0,x1,y0,y1=box;w=x1-x0+1;h=y1-y0+4
 if w*4<h//2:
  width=(h>>3)+(h>>5)+(h>>6)+(h>>7);sx=(width+4)//5;x0=(x0+x1+1-5*sx)//2
 else:sx=(w+4)//5
 sy=(h+6)//7;gate=max(2,int(sx*((sy+3)//4)*1.5));bits=np.zeros((7,5),np.uint8)
 for r in range(7):
  yy=np.arange(y0+r*sy,y0+(r+1)*sy);yy=yy[(yy%4==0)&(yy>=0)&(yy<mask.shape[0])]
  for c in range(5):
   xx=np.arange((x0+c*sx)*4,(x0+(c+1)*sx)*4);xx=xx[(xx>=0)&(xx<mask.shape[1])]
   bits[r,c]=mask[np.ix_(yy,xx)].sum()>=gate
 return bits
def templates():
 result=[]
 for glyph in GLYPHS:
  patterns={tuple(map(int,glyph.replace('/','')))}
  cells=np.array([[int(x) for x in row] for row in glyph.split('/')],np.uint8)
  for aspect in [.8,1.,1.2]:
   shape=cv2.resize(cells,(round(160*aspect),224),interpolation=cv2.INTER_NEAREST)
   src=np.zeros((400,400),np.uint8);h,w=shape.shape;src[80:80+h,100:100+w]=shape
   for angle in range(-25,26,5):
    rotated=cv2.warpAffine(src,cv2.getRotationMatrix2D((200,200),angle,1),(400,400),flags=cv2.INTER_NEAREST)
    ys,xs=np.where(rotated);box=(int(xs.min()//4),int(xs.max()//4),int(ys.min()),int(ys.max()))
    patterns.add(tuple(normalize(rotated,box).ravel()))
  # Include quantization at the hardware's four-pixel / fourth-row sampling.
  # Templates come only from synthetic glyphs, independently of camera frames.
  for scale in [12,16,24]:
   shape=cv2.resize(cells,(5*scale,7*scale),interpolation=cv2.INTER_NEAREST)
   src=np.full((400,400),220,np.uint8)
   src[64:64+7*scale,120:120+5*scale]=220-shape*196
   for angle in range(-25,26,5):
    image=cv2.warpAffine(src,cv2.getRotationMatrix2D((160,120),angle,1),(400,400),flags=cv2.INTER_LINEAR,borderValue=220)
    boxes,_=locate(np.repeat(image[:,:,None],3,2),160)
    if not boxes:continue
    box=boxes[0][:4];mask=(image<128).astype(np.uint8)
    mask[:,:box[0]*4]=0;mask[:,(box[1]+1)*4:]=0
    mask[:box[2]]=0;mask[box[3]+4:]=0
    patterns.add(tuple(normalize(mask,box).ravel()))
  result.append(np.array(list(sorted(patterns)),np.uint8).reshape(-1,7,5))
 return result
def locate(rgb,level=160):
 g=rgb.astype(np.int32).reshape(rgb.shape[0],-1,4,3);y=(g[:,:,:,0]+2*g[:,:,:,1]+g[:,:,:,2])//4
 white=(y>=level).all(2)&(np.abs(g[:,:,0,0]-g[:,:,0,1])<=48)&(np.abs(g[:,:,0,2]-g[:,:,0,1])<=48)
 dark=(y<max(32,level-32)).sum(2)>=3
 rows=[]
 for yy in range(0,len(rgb),4):
  runs=[];changes=np.diff(np.r_[False,dark[yy],False].astype(np.int8));starts=np.where(changes==1)[0];ends=np.where(changes==-1)[0]-1
  for a,b in zip(starts,ends):
   if 2<=b-a+1<=128 and white[yy,max(0,a-4):a].any() and white[yy,b+1:b+5].any():runs.append((int(a),int(b)))
  if runs:
   a=min(r[0] for r in runs);b=max(r[1] for r in runs)
   if b-a+1<=128:rows.append((yy,a,b))
 candidates=[];cand=None
 for yy,a,b in rows:
  if cand and yy-cand[3]<=32 and max(b,cand[1])-min(a,cand[0])+1<=128:
   cand=[min(a,cand[0]),max(b,cand[1]),cand[2],yy,cand[4]+1]
  else:
   if cand:candidates.append(cand)
   cand=[a,b,yy,yy,1]
 if cand:candidates.append(cand)
 candidates=[c for c in candidates if c[3]-c[2]>=36 and c[4]>=8 and c[3]-c[2]+4>=2*(c[1]-c[0]+1) and c[3]-c[2]+4<=16*(c[1]-c[0]+1)]
 return sorted(candidates,key=lambda c:c[3]-c[2],reverse=True),y.reshape(rgb.shape[0],rgb.shape[1])
def main():
 table=templates();print('template_counts',[len(t) for t in table])
 v=cv2.VideoCapture('C:/Users/Chieh yu/Videos/2026-10-24 18-55-14.mp4')
 for frame in [0,60,183,220,360,480,526,600]:
  v.set(cv2.CAP_PROP_POS_FRAMES,frame);ok,img=v.read();assert ok;rgb=cv2.cvtColor(img,cv2.COLOR_BGR2RGB)
  boxes,y=locate(rgb)
  values=[]
  for box in boxes[:3]:
   bits=normalize((y<128).astype(np.uint8),box[:4]);distance=np.array([np.min((t!=bits).sum((1,2))) for t in table]);order=np.argsort(distance)
   values.append(dict(box=box,digit=int(order[0]),distance=distance.tolist(),margin=int(distance[order[1]]-distance[order[0]]),bits=[''.join(map(str,r)) for r in bits]))
  print(frame,values)
 v.release()
if __name__=='__main__':main()
