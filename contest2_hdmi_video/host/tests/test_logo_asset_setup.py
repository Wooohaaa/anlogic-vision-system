import importlib.util
from pathlib import Path
import tempfile
import unittest
import contextlib
import io

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('td_build',ROOT/'tools/build.py')
build=importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)

class LogoSetup(unittest.TestCase):
    def test_absolute_path_resolves_after_project_move(self):
        saved=build.PRJ_HDL
        try:
            with tempfile.TemporaryDirectory(prefix='logo_asset_') as tmp:
                build.PRJ_HDL=tmp
                source=(ROOT/'rtl/user/anlogic_logo_rom.v').read_text(encoding='utf-8')
                text=build._td_user_text('anlogic_logo_rom.v',source)
                for name in build.USER_ASSETS:
                    self.assertIn(str(Path(tmp)/name).replace('\\','/'),text)
                self.assertNotIn('parameter INIT_FILE="rtl/user/logo_compact9.mif"',text)
                self.assertTrue(build._copy_files(str(ROOT/'rtl/user'),build.USER_ASSETS,'user-asset'))
                for name in build.USER_ASSETS:
                    self.assertEqual((Path(tmp)/name).read_bytes(),
                                     (ROOT/'rtl/user'/name).read_bytes())
        finally:
            build.PRJ_HDL=saved

    def test_marker_cannot_silently_disappear(self):
        with self.assertRaises(RuntimeError):
            build._td_user_text('anlogic_logo_rom.v','module changed;endmodule')

    def test_missing_asset_prevents_setup(self):
        saved=build.PRJ_HDL
        try:
            with tempfile.TemporaryDirectory(prefix='logo_missing_') as tmp:
                build.PRJ_HDL=str(Path(tmp)/'target')
                with contextlib.redirect_stdout(io.StringIO()) as output:
                    self.assertFalse(build._copy_files(tmp,build.USER_ASSETS,'user-asset'))
                self.assertIn('missing user-asset source',output.getvalue())
        finally:
            build.PRJ_HDL=saved

if __name__=='__main__':
    unittest.main()
