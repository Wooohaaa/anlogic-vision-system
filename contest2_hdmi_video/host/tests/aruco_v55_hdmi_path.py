"""Replay current runtime MMIO and a zero-length-Z ABI fixture, without hardware."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'tmp/v55_preview/hdmi'
OUT.mkdir(parents=True, exist_ok=True)
sources = [
    'host/tests/tb_aruco_axes_path.sv', 'host/tests/tb_aruco_mcu_bypass.sv',
    'rtl/user/ua_tracking_mcu.v', 'rtl/user/aruco/ua_aruco_peripheral.v',
    'rtl/user/aruco/ua_aruco_snapshot.v', 'rtl/user/aruco/ua_aruco_ahb_bridge.v',
    'rtl/user/aruco/ua_servo_pwm_safe.v', 'rtl/user/hdmi_mixer_user.v',
    'rtl/user/osd_char_lib.v', 'rtl/user/anlogic_logo_rom.v',
    'host/tests/logo_eram_contract_model.v',
]
trace = (ROOT / 'tmp/aruco/v39_axes_runtime.hex').read_text().splitlines()
assert len(trace) == 16
results = {}
for name, visible in [('runtime', 1), ('zero_length_z_abi', 0)]:
    words = trace.copy()
    if not visible:
        # Transport/rendering fixture, not a second C recognition result.
        words[11] = words[8]
        words[14] = '00000000'
    stem = f'tmp/v55_preview/hdmi/{name}'
    (ROOT / f'{stem}.hex').write_text('\n'.join(words) + '\n')
    compile_args = ['C:/iverilog/bin/iverilog.exe', '-g2012', '-s', 'tb_aruco_axes_path',
                    f'-Ptb_aruco_axes_path.TRACE_FILE="{stem}.hex"',
                    f'-Ptb_aruco_axes_path.FRAME_FILE="{stem}.rgb"',
                    f'-Ptb_aruco_axes_path.EXPECT_BLUE={visible}', '-o', f'{stem}.vvp', *sources]
    with (ROOT / f'{stem}_compile.log').open('w') as log:
        subprocess.run(compile_args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    result = subprocess.run(['C:/iverilog/bin/vvp.exe', f'{stem}.vvp'], cwd=ROOT,
                            capture_output=True, text=True)
    (ROOT / f'{stem}.log').write_text(result.stdout + result.stderr)
    result.check_returncode()
    assert 'ARUCO_AXES_HDMI_PATH_PASS ' in result.stdout
    results[name] = result.stdout.strip()
manifest = dict(status='V55_MMIO_AHB_CDC_HDMI_PASS_NOT_BOARD', results=results,
                hidden_z_is_transport_fixture=True, hardware_accessed=False,
                source_sha256={p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest()
                               for p in sources})
(OUT / 'result.json').write_text(json.dumps(manifest, indent=2))
print(json.dumps(manifest, indent=2))
