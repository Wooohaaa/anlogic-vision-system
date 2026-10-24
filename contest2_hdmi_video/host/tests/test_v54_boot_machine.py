"""Execute compiled RV32 boot instructions with bounded RAM and flash mappings.
This is an instruction-level unit test, NOT a model of PH1P35 QSPI/reset hardware.
"""
from pathlib import Path
import struct,json,hashlib
ROOT=Path(__file__).resolve().parents[2]
def signed(v,b):return v-(1<<b) if v&(1<<(b-1)) else v
def execute(boot,payload):
 regs=[0]*32;ram=bytearray(0xc000);pc=0x20e00000
 def read(address,n):
  for start,data in [(0x20e00000,boot),(0x20e10000,payload),(0x08000000,ram)]:
   if start<=address and address+n<=start+len(data):return int.from_bytes(data[address-start:address-start+n],'little')
  raise AssertionError(f'Unmapped read {address:08x}')
 for cycle in range(3000000):
  if pc==0x08000100:return 'entry',bytes(ram),cycle
  ins=read(pc,4);op=ins&127;rd=(ins>>7)&31;f=(ins>>12)&7;a=(ins>>15)&31;b=(ins>>20)&31;imm=signed(ins>>20,12);nextpc=pc+4;value=None
  if op==0x37:value=ins&0xfffff000
  elif op==0x13:
   if f==0:value=regs[a]+imm
   elif f==7:value=regs[a]&imm
   elif f==4:value=regs[a]^imm
   elif f==5 and ins>>25==0:value=regs[a]>>((ins>>20)&31)
   else:raise AssertionError(hex(ins))
  elif op==0x33:
   if f==0 and ins>>25==0:value=regs[a]+regs[b]
   elif f==4 and ins>>25==0:value=regs[a]^regs[b]
   else:raise AssertionError(hex(ins))
  elif op==3:
   if f not in (2,4):raise AssertionError('Unexpected load')
   value=read((regs[a]+imm)&0xffffffff,4 if f==2 else 1)
  elif op==0x23:
   if f!=2:raise AssertionError('Unexpected store')
   address=(regs[a]+signed(((ins>>25)<<5)|((ins>>7)&31),12))&0xffffffff
   if not 0x08000000<=address<=0x0800bffc:raise AssertionError('Out-of-TCM write')
   ram[address-0x08000000:address-0x08000000+4]=regs[b].to_bytes(4,'little')
  elif op==0x63:
   offset=signed(((ins>>31)<<12)|(((ins>>7)&1)<<11)|(((ins>>25)&63)<<5)|(((ins>>8)&15)<<1),13)
   if f not in (0,1,6):raise AssertionError('Unexpected branch')
   take={0:regs[a]==regs[b],1:regs[a]!=regs[b],6:regs[a]<regs[b]}[f]
   if take:nextpc=pc+offset
  elif op==0x67:
   value=pc+4;nextpc=(regs[a]+imm)&~1
  elif op==0x0f:pass
  elif op==0x73:
   if ins==0x10500073:return 'fail_closed',bytes(ram),cycle
   if f not in (1,7) or ins>>20 not in (0x304,0x300,0x7ca) or rd!=0:raise AssertionError('Unexpected CSR')
  else:raise AssertionError(f'Unsupported instruction {ins:08x}')
  if value is not None and rd:regs[rd]=value&0xffffffff
  regs[0]=0;pc=nextpc&0xffffffff
 raise AssertionError('Boot timeout')
def main():
 out=ROOT/'tmp/v54_boot';boot=(out/'boot.bin').read_bytes();payload=(out/'payload.bin').read_bytes();app=(out/'app.bin').read_bytes()
 cases=[('valid',payload,True)]
 for name,index,val in [('magic',0,0),('empty',1,0),('oversize',1,0xc004),('unaligned',1,3),('destination',2,0),('entry',3,0),('crc',4,0)]:
  bad=bytearray(payload);struct.pack_into('<I',bad,index*4,val);cases.append((name,bytes(bad),False))
 bad=bytearray(payload);bad[-1]^=1;cases.append(('payload_corruption',bytes(bad),False))
 records=[]
 for name,data,good in cases:
  status,ram,steps=execute(boot,data)
  assert (status=='entry')==good,(name,status)
  if good:assert ram[:len(app)]==app
  records.append(dict(case=name,status=status,instructions=steps));print(name,status,steps,flush=True)
 hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [ROOT/'boot/v54/start.S',ROOT/'boot/v54/link.ld',Path(__file__),out/'boot.bin',out/'payload.bin',out/'app.bin']}
 (out/'machine_test.json').write_text(json.dumps(dict(status='RV32_BOOT_MACHINE_TEST_PASS_NOT_BOARD',records=records,hashes=hashes),indent=2))
if __name__=='__main__':main()
