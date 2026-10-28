"""Portable delivery entry point. Only 'program' accesses the connected board."""
from pathlib import Path
import argparse,hashlib,json,os,re,shutil,struct,subprocess,sys,zlib
ROOT=Path(__file__).resolve().parents[1]
FPGA=ROOT/'contest2_hdmi_video'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def config():
 p=ROOT/'config.local.json'
 return json.loads((p if p.exists() else ROOT/'config.example.json').read_text(encoding='utf-8'))
def toolhome(name):
 env={'td_home':'ANLOGIC_TD_HOME','fd_home':'ANLOGIC_FD_HOME'}[name]
 return Path(os.environ.get(env,config()[name]))
def run(args,cwd=ROOT,log=None,env=None):
 if log:
  log=Path(log);log.parent.mkdir(parents=True,exist_ok=True)
  with log.open('w',encoding='utf-8') as stream:r=subprocess.run(list(map(str,args)),cwd=cwd,env=env,stdout=stream,stderr=subprocess.STDOUT)
  assert r.returncode==0,f'Command failed, see {log}'
  content=log.read_text(encoding='utf-8-sig',errors='replace')
  assert not re.search(r'\bERROR\b|_FAILED\b',content),f'Tool error, see {log}'
  return content
 subprocess.run(list(map(str,args)),cwd=cwd,env=env,check=True)
def verify():
 manifest=json.loads((ROOT/'PACKAGE_MANIFEST.json').read_text(encoding='utf-8'))
 for rel,h in manifest['sha256'].items():
  p=(ROOT/rel).resolve();assert p.is_relative_to(ROOT) and p.is_file(),rel
  assert sha(p)==h,rel
 run([sys.executable,'tools/build.py','verify','--binary-hand'],FPGA)
 print(f"DELIVERY_VERIFIED files={len(manifest['sha256'])}; no board access")
def fpga():
 td=toolhome('td_home');env=dict(os.environ);env['ANLOGIC_TD_HOME']=str(td).replace('\\','/')
 (FPGA/'tmp').mkdir(exist_ok=True);(FPGA/'deliverables').mkdir(exist_ok=True)
 run([sys.executable,'tools/build.py','setup','--binary-hand'],FPGA)
 run([sys.executable,'tools/build.py','verify','--binary-hand'],FPGA)
 work=FPGA/'prj/td_project'
 text=run([td/'bin/td_commands_prompt.exe','../../tools/release_area.tcl'],work,FPGA/'tmp/release_area.log',env)
 assert 'HDMI_RELEASE_AREA_FLOW_COMPLETE' in text
 shutil.copy2(work/'camera_to_dsi_display_hdmi_place.db',FPGA/'tmp/release_placed.db')
 text=run([td/'bin/td_commands_prompt.exe','../../tools/release_route.tcl'],work,FPGA/'tmp/release_route.log',env)
 assert 'HDMI_RELEASE_ROUTED_BIT_COMPLETE' in text
 timing=(FPGA/'tmp/release_final_routed.timing').read_text()
 assert re.search(r'Confidence\s*:\s*Routed',timing)
 for k in ['SWNS','HWNS','STNS','HTNS']:
  values=[float(x) for x in re.findall(k+r':\s*([-\d.]+)ns',timing)]
  assert values and all(x>=0 for x in values),k
  if k.endswith('TNS'):assert all(x==0 for x in values),k
 print('FPGA_ROUTED_TIMING_PASS_NOT_PROGRAMMED')
def mcu():
 fd=toolhome('fd_home');work=Path(config()['mcu_build_workspace'])
 # Vendor GNU make assumes no spaces in SDK/build paths. Stage only in the
 # explicitly configured workspace; never delete or alter the delivered SDK.
 assert not re.search(r'\s',str(work)),'Choose an ASCII workspace without spaces'
 work.mkdir(parents=True,exist_ok=True)
 for name in ['fpsoc','platform','tools','3rdparty','prebuild']:
  src=ROOT/'vendor/anlogic_sdk'/name
  if src.exists():shutil.copytree(src,work/name,dirs_exist_ok=True)
 folder=work/'stepper_firmware'
 for name in ['aruco_app','stepper_app']:
  shutil.copytree(ROOT/'mcu_tracking'/name,folder/name,dirs_exist_ok=True)
 app=folder/'app';app.mkdir(exist_ok=True)
 for p in (ROOT/'mcu_tracking/stepper_firmware').iterdir():
  if p.is_file():shutil.copy2(p,app/p.name)
 makefile=(app/'Makefile').read_text(encoding='utf-8')
 makefile=re.sub(r'(?m)^SDK_ROOT\s*:=.*$',f'SDK_ROOT := {work.as_posix()}',makefile)
 prefix=(fd/'toolchain/gcc/riscv/ph1p35/bin/riscv64-unknown-elf-').as_posix()
 makefile=re.sub(r'(?m)^COMPILE_PREFIX\s*:=.*$',f'COMPILE_PREFIX := {prefix}',makefile)
 (app/'Makefile').write_text(makefile,encoding='utf-8')
 env=dict(os.environ);env['PATH']=str(fd/'toolchain/build-tools/bin')+os.pathsep+env.get('PATH','')
 run([fd/'toolchain/build-tools/bin/make.exe','-C',app,'-j4','TARGET=mcu_app'],ROOT,ROOT/'build/mcu_build.log',env)
 exe=app/'build/mcu_app.elf';assert exe.exists()
 sizes=subprocess.check_output([str(fd/'toolchain/gcc/riscv/ph1p35/bin/riscv64-unknown-elf-size.exe'),str(exe)],text=True)
 match=re.search(r'(?m)^\s*(\d+)\s+(\d+)\s+(\d+)\s+\d+',sizes);assert match,sizes
 assert sum(map(int,match.groups()))+2048<=49152,'TCM+stack budget exceeded'
 out=ROOT/'build/mcu';out.mkdir(parents=True,exist_ok=True)
 for ext in ['elf','map']:
  p=app/f'build/mcu_app.{ext}'
  if p.exists():shutil.copy2(p,out/p.name)
 print(sizes);print('MCU_BUILD_PASS_NOT_PROGRAMMED',out)
def flash_image():
 base=FPGA/'deliverables/camera_system_fpga.bit'
 assert base.exists(),'Build FPGA first'
 built=ROOT/'build/mcu/mcu_app.elf'
 elf=built if built.exists() else ROOT/'firmware/mcu_app.elf'
 out=FPGA/'tmp/release_boot';out.mkdir(parents=True,exist_ok=True)
 fd=toolhome('fd_home')
 run([fd/'toolchain/gcc/riscv/ph1p35/bin/riscv64-unknown-elf-objcopy.exe','-O','binary',elf,out/'app.bin'])
 app=(out/'app.bin').read_bytes();assert len(app)%4==0 and 0<len(app)<49152
 payload=struct.pack('<8I',0x41525543,len(app),0x08000000,0x08000100,zlib.crc32(app),102,0,0)+app
 (out/'payload.bin').write_bytes(payload)
 sys.path.insert(0,str(FPGA/'host/tests'))
 from test_v54_boot_machine import execute
 boot=(ROOT/'firmware/boot/boot.bin').read_bytes()
 assert sha(ROOT/'firmware/boot/boot.bin')=='1039b54f4eb85947691d85d2a5ef7000bd4d5f239fc8bd859d0f11985950ebdb'
 state,ram,_=execute(boot,payload);assert state=='entry' and ram[:len(app)]==app
 bad=bytearray(payload);bad[-1]^=1;assert execute(boot,bytes(bad))[0]=='fail_closed'
 target=FPGA/'deliverables/camera_system_flash.bit'
 assert not target.exists(),'Output exists; archive it before explicitly rebuilding'
 run([toolhome('td_home')/'bin/bw_commands_prompt.exe','tools/release_merge.tcl'],FPGA,FPGA/'tmp/release_merge.log')
 b=base.read_bytes();j=target.read_bytes();bs=b.index(b'\n\n')+2;js=j.index(b'\n\n')+2
 assert j[js:js+len(b)-bs]==b[bs:]
 assert j[js+0xe00000:js+0xe00000+len(boot)]==boot
 assert j[js+0xe10000:js+0xe10000+len(payload)]==payload
 print('FLASH_IMAGE_VERIFIED_NOT_PROGRAMMED',target,sha(target))
def program():
 # Explicit user command only; default verify/build/test never calls this.
 td=toolhome('td_home');bit=ROOT/'firmware/camera_system_flash.bit'
 manifest=json.loads((ROOT/'PACKAGE_MANIFEST.json').read_text(encoding='utf-8'))
 assert sha(bit)==manifest['sha256'][bit.relative_to(ROOT).as_posix()]
 script=ROOT/'tools/program_flash.tcl'
 run([td/'bin/bw_commands_prompt.exe',script],ROOT,ROOT/'build/program_flash.log')
 print('PREBUILT_RELEASE_FLASH_PROGRAM_VERIFY_PASS_COLD_BOOT_PENDING')
def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('action',choices=['verify','setup','fpga','mcu','flash-image','test','program'],nargs='?',default='verify')
 a=p.parse_args().action
 if a=='verify':verify()
 elif a=='setup':run([sys.executable,'tools/build.py','setup','--binary-hand'],FPGA)
 elif a=='fpga':fpga()
 elif a=='mcu':mcu()
 elif a=='flash-image':flash_image()
 elif a=='test':
  (FPGA/'tmp').mkdir(exist_ok=True)
  run([sys.executable,'tools/test_digit_v106.py'],FPGA)
  for top,source,marker in [('tb_stream_fps_v101','host/tests/tb_stream_fps_v101.sv','STREAM_FPS_V101_PASS'),
      ('tb_latency_frames_v101','host/tests/tb_latency_frames_v101.sv','LATENCY_FRAMES_V101_PASS')]:
   exe=FPGA/f'tmp/{top}.vvp'
   run([os.environ.get('IVERILOG','iverilog'),'-g2012','-s',top,'-o',exe,
        'rtl/user/ua_frame_latency.v',source],FPGA,ROOT/f'build/{top}_compile.log')
   text=run([os.environ.get('VVP','vvp'),exe],FPGA,ROOT/f'build/{top}_simulation.log')
   assert marker in text,top
 elif a=='program':program()
if __name__=='__main__':main()
