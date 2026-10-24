"""Guard the actual assembly scope, not just standalone detector/OSD blocks."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

def connected(source):
    ports = re.search(r'\)u_hdmi_mixer_user\((.*?)\n\s*\);', source, re.S)
    if not ports:
        return False
    for suffix in ('valid', 'id_bcd', 'corner0', 'corner1', 'corner2', 'corner3',
                   'edge0', 'edge1', 'edge2', 'edge3'):
        if not re.search(r'\.I_aruco_'+suffix+r'\s*\(\s*gen_ae\.S_aruco_display_'+suffix+r'\s*\)', ports[1]):
            return False
    return True

class Links(unittest.TestCase):
    def test_maintained_top(self):
        self.assertTrue(connected((ROOT/'rtl/user/design_top_user.v').read_text(encoding='utf-8')))

    def test_catches_v31_scope_error(self):
        source=(ROOT/'rtl/user/design_top_user.v').read_text(encoding='utf-8')
        self.assertFalse(connected(source.replace('gen_ae.S_aruco_display_', 'S_aruco_display_')))

if __name__ == '__main__':
    unittest.main()
