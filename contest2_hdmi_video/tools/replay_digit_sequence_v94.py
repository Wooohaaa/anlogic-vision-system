"""Three distinct consecutive 720p HDMI clips, never live sensor evidence."""
import os,shutil
from pathlib import Path
import cv2,hashlib,json,subprocess,concurrent.futures
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'tmp/v94_sequence'
VIDEO=Path(os.environ.get('DIGIT_TEST_VIDEO',str(ROOT/'test_media/digit_regression.mp4')))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 OUT.mkdir(parents=True,exist_ok=True)
 sources=[ROOT/'host/tests/tb_digit_sequence_v94.sv',*[ROOT/'rtl/user'/n for n in
  ['ua_digit_recognizer.v','ua_digit_card_locator.v','ua_digit_template_rom.v']]]
 frozen={str(p):sha(p) for p in [Path(__file__),VIDEO,*sources]}
 exe=OUT/'sequence.vvp'
 r=subprocess.run([os.environ.get('IVERILOG',shutil.which('iverilog') or 'C:/iverilog/bin/iverilog.exe'),'-Wall','-g2012','-s','tb_digit_sequence_v94','-o',str(exe),*map(str,sources)],cwd=ROOT,capture_output=True,text=True)
 assert r.returncode==0 and 'implicit definition' not in r.stderr,r.stderr
 (OUT/'compile.log').write_text(r.stdout+r.stderr)
 cases=[(0,5),(183,7),(526,9)];video=cv2.VideoCapture(str(VIDEO))
 for start,label in cases:
  folder=OUT/str(start);folder.mkdir(exist_ok=True);video.set(cv2.CAP_PROP_POS_FRAMES,start)
  for i in range(12):
   ok,image=video.read();assert ok and image.shape[:2]==(720,1280)
   path=folder/f'{i}.hex';rgb=cv2.cvtColor(image,cv2.COLOR_BGR2RGB).reshape(-1,12)
   # Regenerate from the original video, never trust a stale vector cache.
   path.write_text('\n'.join(row.tobytes().hex() for row in rgb)+'\n')
   frozen[str(path)]=sha(path)
 video.release()
 def run(case):
  start,label=case;log=OUT/f'{start}.log'
  with log.open('w') as stream:r=subprocess.run([os.environ.get('VVP',shutil.which('vvp') or 'C:/iverilog/bin/vvp.exe'),'-i',str(exe),
   f'+FOLDER=tmp/v94_sequence/{start}',f'+EXPECTED={label}'],cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT)
  text=log.read_text();assert r.returncode==0 and 'DIGIT_SEQUENCE_V94_PASS' in text,text[-3000:]
  print(text.splitlines()[-2],flush=True)
  return dict(start=start,label=label,frames=12,log=str(log))
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(run,cases))
 assert frozen=={p:sha(p) for p in frozen}
 (OUT/'result.json').write_text(json.dumps(dict(status='DIGIT_V94_CONSECUTIVE_HDMI_RTL_PASS_NOT_BOARD',
  hashes=frozen,cases=results,frames=36,actual_sensor_input=False),indent=2))
 print('DIGIT_V94_CONSECUTIVE_HDMI_RTL_PASS_NOT_BOARD',flush=True)
if __name__=='__main__':main()
