"""Read-only audit of TD-exported ROM initialization against the v5 model."""
import argparse
from pathlib import Path
import re
from photo_vectors import tone,wide_tone

parser=argparse.ArgumentParser()
parser.add_argument('netlist',type=Path)
parser.add_argument('--mapped',action='store_true')
parser.add_argument('--bits',type=int,choices=(8,9),default=8)
parser.add_argument('--instance',default='u_photo_finish',help='mapped hierarchy instance containing tone ROMs')
args=parser.parse_args()
text=args.netlist.read_text(encoding='utf-8')
entries=1<<args.bits
expected=[wide_tone(c) if args.bits==9 else tone(c,0) for c in range(entries)]
if args.mapped:
    # TD's 8-bit logical ROM uses native 10-bit words: bits 3:0 in
    # data[3:0], bits 7:5 in data[6:4], bit 4 in parity[0].
    blocks=re.findall(r'// [^\n]*'+re.escape(args.instance)+r'/ramread[^\n]*_'+str(entries)+r'x8\s+PH1P_PHY_ERAM_V2 #\((.*?)\)\s+\\[^\s]+',text,re.S)
    assert len(blocks)==6, f'Expected six mapped ROMs, found {len(blocks)}'
    for bank,block in enumerate(blocks):
        params=dict(re.findall(r'\.(INITP?_[0-9A-F]{2})\(256\x27h([0-9a-fA-F]{64})\)',block))
        data=sum(int(params[f'INIT_{i:02X}'],16)<<(256*i) for i in range(entries//32))
        parity=sum(int(params[f'INITP_{i:02X}'],16)<<(256*i) for i in range(entries//128))
        actual=[]
        for c in range(entries):
            b=(data>>(8*c))&255
            actual.append((b&15)|(((b>>4)&7)<<5)|(((parity>>(2*c))&1)<<4))
        assert actual==expected, f'Mapped ROM {bank} data/parity mismatch'
    print(f'TD_MAPPED_ROM_INIT_PASS banks=6 entries={entries} data_parity exact_model')
    raise SystemExit(0)
table_bits=entries*8
tables=re.findall(r'\.INIT_VALUE\('+str(table_bits)+r'\x27b([01]{'+str(table_bits)+r'})\)',text)
assert len(tables)==6, f'Expected six tone banks, found {len(tables)}'
for index,bits in enumerate(tables):
    actual=[int(bits[table_bits-8*(c+1):table_bits-8*c],2) for c in range(entries)]
    assert actual==expected, f'TD ROM bank {index} initialization mismatch'
print(f'TD_ROM_INIT_PASS banks=6 entries={entries} each exact_model')
