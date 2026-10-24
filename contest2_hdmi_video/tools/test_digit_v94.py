"""Native RGB tests: old upright gallery, negatives and independently tilted cards."""
import os,shutil
from pathlib import Path
import cv2,numpy as np,hashlib,json,subprocess,concurrent.futures
from prototype_digit_v94 import GLYPHS
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'tmp/v94_digit'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 OUT.mkdir(parents=True,exist_ok=True)
 for old,new in [('tb_digit_auto_v93.sv','tb_digit_auto_v94.sv'),('tb_digit_auto_negative_v93.sv','tb_digit_auto_negative_v94.sv')]:
  text=(ROOT/'host/tests'/old).read_text().replace('v93','v94').replace('V93','V94').replace('repeat(400)','repeat(24000)')
  if 'negative' not in old:text=text.replace('f<10;','f<8;')
  (OUT/new).write_text(text)
 digit=['rtl/user/ua_digit_recognizer.v','rtl/user/ua_digit_card_locator.v','rtl/user/ua_digit_template_rom.v']
 jobs=[('tb_digit_auto_v94',['tmp/v94_digit/tb_digit_auto_v94.sv',*digit],{},'DIGIT_AUTO_V94_PASS',None,None),
  ('tb_digit_auto_negative_v94',['tmp/v94_digit/tb_digit_auto_negative_v94.sv',*digit],{},'DIGIT_AUTO_NEGATIVE_V94_PASS',None,None)]
 # Render glyphs and white cards together. Camera frames are not used here.
 for digit_id,glyph in enumerate(GLYPHS):
  for angle in [-15,0,15]:
   image=np.full((240,320),22,np.uint8);white=112 if angle==0 else 220;ink=40 if angle==0 else 24
   image[42:198,102:218]=white
   for r,row in enumerate(glyph.split('/')):
    for c,bit in enumerate(row):
     if bit=='1':image[64+r*16:64+(r+1)*16,120+c*16:120+(c+1)*16]=ink
   image=cv2.warpAffine(image,cv2.getRotationMatrix2D((160,120),angle,1),(320,240),flags=cv2.INTER_LINEAR,borderValue=22)
   rgb=np.repeat(image[:,:,None],3,2).reshape(-1,12)
   p=OUT/f'glyph_{digit_id}_{angle}.hex';p.write_text('\n'.join(row.tobytes().hex() for row in rgb)+'\n')
   jobs.append(('tb_digit_vector_v94',['host/tests/tb_digit_vector_v94.sv',*digit],{},'DIGIT_VECTOR_V94_PASS',p,digit_id))
 files={'tools/test_digit_v94.py','tools/prototype_digit_v94.py','tools/generate_digit_templates_v94.py',
  'host/tests/tb_digit_auto_v93.sv','host/tests/tb_digit_auto_negative_v93.sv'}
 for _,src,_,_,p,_ in jobs:
  files.update(src)
  if p is not None:files.add(str(p.relative_to(ROOT)))
 frozen={str(ROOT/p):sha(ROOT/p) for p in files}
 vector_exe=OUT/'vector.vvp'
 # Compile common vector top once; gallery/negative have separate tops.
 vector_comp=subprocess.run([os.environ.get('IVERILOG',shutil.which('iverilog') or 'C:/iverilog/bin/iverilog.exe'),'-Wall','-g2012','-s','tb_digit_vector_v94','-o',str(vector_exe),
  'host/tests/tb_digit_vector_v94.sv',*digit],cwd=ROOT,capture_output=True,text=True)
 assert vector_comp.returncode==0 and 'implicit definition' not in vector_comp.stderr,vector_comp.stderr
 def run(job):
  i,(top,src,params,marker,path,label)=job;exe=vector_exe
  if path is None:
   exe=OUT/f'{i}.vvp';comp=subprocess.run([os.environ.get('IVERILOG',shutil.which('iverilog') or 'C:/iverilog/bin/iverilog.exe'),'-Wall','-g2012','-s',top,'-o',str(exe),*src],cwd=ROOT,capture_output=True,text=True)
   (OUT/f'{i}_compile.log').write_text(comp.stdout+comp.stderr);assert comp.returncode==0 and 'implicit definition' not in comp.stderr,comp.stderr
  cmd=[os.environ.get('VVP',shutil.which('vvp') or 'C:/iverilog/bin/vvp.exe'),'-i',str(exe)]
  if path is not None:cmd += [f'+INPUT={path.relative_to(ROOT).as_posix()}',f'+EXPECTED={label}']
  log=OUT/f'{i}_simulation.log'
  with log.open('w') as stream:r=subprocess.run(cmd,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT)
  text=log.read_text();assert r.returncode==0 and marker in text,str(log)+'\n'+text[-3000:]
  print('DIGIT_V94_CASE_PASS',i,top,label,flush=True)
  return dict(index=i,top=top,label=label)
 with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:results=list(pool.map(run,enumerate(jobs)))
 assert frozen=={p:sha(p) for p in frozen}
 (OUT/'result.json').write_text(json.dumps(dict(status='DIGIT_V94_RGB_AND_TILT_RTL_PASS_NOT_BOARD',hashes=frozen,cases=results,hardware_verified=False),indent=2))
 print('DIGIT_V94_RGB_AND_TILT_RTL_PASS_NOT_BOARD',flush=True)
if __name__=='__main__':main()
