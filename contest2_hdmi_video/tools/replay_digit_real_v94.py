"""Replay the user's actual HDMI frames. Not RAW/sensor or live board proof."""
import os,shutil
from pathlib import Path
import cv2,numpy as np,hashlib,json,subprocess,concurrent.futures,sys,shutil
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'tmp/v94_real_digit'
VIDEO=Path(os.environ.get('DIGIT_TEST_VIDEO',str(ROOT/'test_media/digit_regression.mp4')))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 baseline='--baseline' in sys.argv
 OUT.mkdir(parents=True,exist_ok=True);backup=ROOT/'tmp/v94_baseline';backup.mkdir(exist_ok=True)
 for name in ['ua_digit_recognizer.v','ua_digit_card_locator.v','hdmi_mixer_user.v']:
  p=backup/name
  if baseline and not p.exists():shutil.copy2(ROOT/'rtl/user'/name,p)
 src=[str((backup if baseline else ROOT/'rtl/user')/n) for n in ['ua_digit_recognizer.v','ua_digit_card_locator.v']]
 if not baseline:src.append(str(ROOT/'rtl/user/ua_digit_template_rom.v'))
 files=[Path(__file__),VIDEO,ROOT/'host/tests/tb_digit_real_v94.sv',*[Path(p) for p in src]]
 frozen={str(p):sha(p) for p in files}
 exe=OUT/('baseline.vvp' if baseline else 'candidate.vvp')
 run=subprocess.run([os.environ.get('IVERILOG',shutil.which('iverilog') or 'C:/iverilog/bin/iverilog.exe'),'-Wall','-g2012','-s','tb_digit_real_v94','-o',str(exe),
  'host/tests/tb_digit_real_v94.sv',*src],cwd=ROOT,capture_output=True,text=True)
 assert run.returncode==0,run.stderr
 assert 'implicit definition' not in run.stderr,run.stderr
 video=cv2.VideoCapture(str(VIDEO));cases=[(0,5),(183,7),(526,9)]
 for frame,label in cases:
  video.set(cv2.CAP_PROP_POS_FRAMES,frame);ok,img=video.read();assert ok
  assert img.shape[:2]==(720,1280)
  rgb=cv2.cvtColor(img,cv2.COLOR_BGR2RGB).reshape(-1,12)
  path=OUT/f'frame_{frame}.hex'
  if not path.exists():path.write_text('\n'.join(row.tobytes().hex() for row in rgb)+'\n')
 video.release()
 def job(case):
  frame,label=case;log=OUT/f'{"baseline" if baseline else "candidate"}_{frame}.log'
  command=[os.environ.get('VVP',shutil.which('vvp') or 'C:/iverilog/bin/vvp.exe'),'-i',str(exe),f'+INPUT=tmp/v94_real_digit/frame_{frame}.hex']
  if not baseline:command.append(f'+EXPECTED={label}')
  with log.open('w') as stream:r=subprocess.run(command,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT)
  text=log.read_text();print(frame,label,'exit=',r.returncode,text.splitlines()[-2:],flush=True)
  return dict(frame=frame,label=label,returncode=r.returncode,log=str(log))
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(job,cases))
 assert frozen=={p:sha(p) for p in frozen},'Input changed during replay'
 (OUT/('baseline.json' if baseline else 'candidate.json')).write_text(json.dumps(dict(
  status='BASELINE_DIAGNOSTIC_ONLY' if baseline else ('REAL_HDMI_STATIC_RTL_PASS_NOT_BOARD' if all(r['returncode']==0 for r in results) else 'REAL_HDMI_STATIC_RTL_FAILED'),
  cases=results,hashes=frozen,actual_sensor_input=False),indent=2))
 if not baseline:assert all(r['returncode']==0 for r in results),results
if __name__=='__main__':main()
