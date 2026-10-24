"""Legacy classification, coherent mailbox, dynamic/no-result HDMI and motion."""
import os,shutil
from pathlib import Path
import hashlib,json,subprocess,concurrent.futures
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'tmp/v94_integration'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 OUT.mkdir(parents=True,exist_ok=True)
 baseline={str(ROOT.parent/p):h for p,h in json.loads((ROOT.parent/'PACKAGE_MANIFEST.json').read_text(encoding='utf-8'))['sha256'].items() if p.startswith('contest2_hdmi_video/rtl/')}
 allowed={'ua_digit_recognizer.v','ua_digit_card_locator.v','hdmi_mixer_user.v'}
 for f,h in baseline.items():
  if Path(f).is_relative_to(ROOT/'rtl') and Path(f).name not in allowed:assert sha(f)==h,f
 top=(ROOT/'rtl/user/design_top_user.v').read_text(encoding='utf-8-sig')
 assert '.I_digit_view(gen_ae.S_digit_view_hdmi)' in top and '.I_digit_view_valid(gen_ae.S_digit_view_valid_hdmi)' in top
 overlay=(ROOT/'host/tests/tb_digit_overlay_v93.sv').read_text().replace('tb_digit_overlay_v93','tb_digit_overlay_v94')
 overlay=overlay.replace('  initial begin\n    digit_view=',
  '''  integer dash_pixels=0;
  always @(posedge clk)begin #2;
    if(rst && dut.S_video_de_2d && !dut.S_digit_show && dut.S_digit_seg_on)dash_pixels=dash_pixels+1;
  end
  initial begin
    digit_view=''')
 overlay=overlay.replace('    $display("DIGIT_OVERLAY_V93_PASS',
  '    if(CAMERA && dash_pixels!=90)$fatal(1,"missing search dashes count=%0d",dash_pixels);\n'
  '    $display("DIGIT_OVERLAY_V94_PASS')
 path=OUT/'tb_digit_overlay_v94.sv';path.write_text(overlay)
 mixer=['rtl/user/hdmi_mixer_user.v','rtl/user/osd_char_lib.v','rtl/user/anlogic_logo_rom.v','host/tests/logo_eram_contract_model.v',str(path.relative_to(ROOT))]
 cases=[('tb_digit_adaptive_v67',['host/tests/tb_digit_adaptive_v67.v','rtl/user/ua_digit_recognizer.v'],{},'DIGIT_ADAPTIVE_V67_PASS'),
  ('tb_digit_mailbox_v93',['host/tests/tb_digit_mailbox_v93.sv','rtl/user/ua_motion_grid.v'],{},'DIGIT_MAILBOX_V93_PASS'),
  ('tb_motion_grid_v92',['host/tests/tb_motion_grid_v92.sv','rtl/user/ua_motion_grid.v','rtl/user/ua_motion_detect.v','rtl/user/ua_motion_ref_ram.v'],dict(GAPS=1),'MOTION_GRID_V92_PASS')]
 for cam in [0,1]:cases.append(('tb_digit_overlay_v94',mixer,dict(CAMERA=cam),'DIGIT_OVERLAY_V94_PASS'))
 files={'tools/test_digit_integration_v94.py','tools/build.py','rtl/user/design_top_user.v','rtl/user/isp_top_user.v',
  'rtl/user/font_compact.dath','rtl/user/logo_spans.mif','rtl/user/logo_compact9.mif','host/tests/tb_digit_overlay_v93.sv'}
 for _,src,_,_ in cases:files.update(src)
 frozen={str(ROOT/p):sha(ROOT/p) for p in files}
 def run(job):
  i,(top,src,params,marker)=job;exe=OUT/f'{i}.vvp'
  commands=[('compile',[os.environ.get('IVERILOG',shutil.which('iverilog') or 'C:/iverilog/bin/iverilog.exe'),'-Wall','-g2012','-s',top,'-o',str(exe),
   *[f'-P{top}.{k}={v}' for k,v in params.items()],*src]),('simulation',[os.environ.get('VVP',shutil.which('vvp') or 'C:/iverilog/bin/vvp.exe'),'-i',str(exe)])]
  for stage,cmd in commands:
   log=OUT/f'{i}_{stage}.log'
   with log.open('w') as stream:r=subprocess.run(cmd,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT)
   text=log.read_text();assert r.returncode==0 and 'implicit definition' not in text and (stage=='compile' or marker in text),text[-3500:]
  print('DIGIT_V94_INTEGRATION_CASE_PASS',top,params,flush=True)
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:list(pool.map(run,enumerate(cases)))
 assert frozen=={p:sha(p) for p in frozen}
 (OUT/'result.json').write_text(json.dumps(dict(status='DIGIT_V94_INTEGRATION_RTL_PASS_NOT_BOARD',hashes=frozen,
  cases=[dict(top=t,parameters=p) for t,_,p,_ in cases],hardware_verified=False),indent=2))
 print('DIGIT_V94_INTEGRATION_RTL_PASS_NOT_BOARD',flush=True)
if __name__=='__main__':main()
