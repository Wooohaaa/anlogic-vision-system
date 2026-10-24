import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from aruco_bus_trace import decode


class ArucoBusTraceTests(unittest.TestCase):
    def record(self, address=0, size=2):
        return (0xA7 << 56 | 1 << 55 | 1 << 54 | 1 << 53 | 1 << 52 |
                2 << 50 | size << 46 | address << 15 | 0x52A5)

    def test_valid_request(self):
        result = decode(self.record())
        self.assertTrue(result['seen'] and result['error_seen'])
        self.assertEqual(result['haddr'], '0x00000000')
        self.assertFalse(result['rejected_by_v27_address_size'])

    def test_window_size_alignment(self):
        for address, size in [(0x40000000, 2), (1, 2), (0, 0), (0x100000, 2)]:
            with self.subTest(address=address, size=size):
                self.assertTrue(decode(self.record(address, size))['rejected_by_v27_address_size'])

    def test_framing(self):
        for value in [0, -1, 1 << 64, self.record() ^ 1, self.record() ^ 1 << 63]:
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    decode(value)

    def test_v30_error_side_debug(self):
        debug = (1 << 10) | (3 << 7) | (1 << 5) | (1 << 4) | (1 << 3) | 1
        value = (0xA8 << 56 | 1 << 55 | 1 << 54 | 1 << 53 | 1 << 52 |
                 2 << 50 | 2 << 46 | debug << 35 | 0x00000000 << 15 | 0x52A5)
        result = decode(value)
        self.assertEqual(result['version'], 0xA8)
        self.assertEqual(result['haddr'], '0x00000000')
        self.assertEqual(result['debug']['bridge_state'], 3)
        self.assertTrue(result['debug']['apb_select'])
        self.assertFalse(result['debug']['apb_error'])
        self.assertTrue(result['debug']['bridge_hready'])
