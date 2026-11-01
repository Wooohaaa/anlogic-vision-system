"""Prepare the exact R6/r18 source profile in a separate submission directory.

Only copies and verifies files; does not build, replay video, or access hardware.
"""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_manifest(root):
    entries = {}
    for path in sorted(root.rglob('*')):
        if not path.is_file():
            continue
        rel = path.relative_to(root)
        if path.name == 'PACKAGE_MANIFEST.json' or '__pycache__' in rel.parts:
            continue
        entries[rel.as_posix()] = sha(path)
    result = {
        'created': datetime.now(timezone(timedelta(hours=8))).isoformat(),
        'source_profile': 'R6 areaopt4 + MCU r18',
        'sha256': entries,
    }
    (root / 'PACKAGE_MANIFEST.json').write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    dest = args.output.resolve()
    if dest.exists():
        raise SystemExit('Output exists; select a new empty submission directory')
    if ROOT == dest or ROOT.is_relative_to(dest):
        raise SystemExit('Output must not replace the repository or its parents')
    if dest.is_relative_to(ROOT) and not dest.is_relative_to(ROOT / 'build'):
        raise SystemExit('Repository-local output must be under build/')

    if (ROOT / '.git').exists():
        raw = subprocess.check_output(
            ['git', 'ls-files', '-c', '-o', '--exclude-standard', '-z'], cwd=ROOT)
        names = sorted(set(x for x in raw.decode('utf-8').split('\0') if x))
    else:
        names = list(json.loads((ROOT / 'PACKAGE_MANIFEST.json').read_text(
            encoding='utf-8'))['sha256'])
        names.append('PACKAGE_MANIFEST.json')
    for name in names:
        source = (ROOT / name).resolve()
        if not source.is_relative_to(ROOT) or not source.is_file():
            raise RuntimeError('Invalid source path: ' + name)
        if name == 'config.local.json' or '.git' in Path(name).parts:
            raise RuntimeError('Private configuration must not enter a submission')
        target = dest / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)

    profile = json.loads((ROOT / 'verification/r6_source_profile.json').read_text(
        encoding='utf-8'))
    for name, item in profile['overlays'].items():
        source = (ROOT / item['source']).resolve()
        target = (dest / name).resolve()
        assert source.is_relative_to(ROOT) and target.is_relative_to(dest)
        assert sha(source) == item['sha256'], name
        shutil.copy2(source, target)

    area = dest / 'contest2_hdmi_video/tools/release_area.tcl'
    text, count = re.subn(r'place seed 1\b', 'place seed 2', area.read_text(encoding='utf-8'))
    assert count == 1
    area.write_text(text, encoding='utf-8')
    route = dest / 'contest2_hdmi_video/tools/release_route.tcl'
    text = route.read_text(encoding='utf-8')
    assert 'slice 20000 eram 108 dsp 40' in text
    route.write_text(text.replace('slice 20000 eram 108 dsp 40',
                                  'slice 20091 eram 108 dsp 40'), encoding='utf-8')
    entry = dest / 'tools/repository.py'
    text = entry.read_text(encoding='utf-8')
    assert 'zlib.crc32(app),102,0,0' in text
    entry.write_text(text.replace('zlib.crc32(app),102,0,0',
                                  'zlib.crc32(app),95,0,0'), encoding='utf-8')

    env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
    for action in ['setup', 'verify']:
        subprocess.run([sys.executable, 'tools/build.py', action, '--binary-hand'],
                       cwd=dest / 'contest2_hdmi_video', env=env, check=True)
    for group in ['rtl_sha256', 'mcu_source_sha256']:
        for name, expected in profile[group].items():
            assert sha(dest / name) == expected, name
    assert sha(dest / 'vendor/anlogic_sdk/fpsoc/chip/ph1p35/lds/gcc_ph1p35_tcm.ld') == profile['sdk_linker_sha256']
    evidence = json.loads((dest / 'verification/release_evidence.json').read_text(encoding='utf-8'))
    for name, item in evidence['artifacts'].items():
        assert sha(dest / name) == item['sha256'], name

    info = {
        'release': profile['release'],
        'prepared': datetime.now(timezone(timedelta(hours=8))).isoformat(),
        'source_profile_applied': True,
        'rtl_files_checked': len(profile['rtl_sha256']),
        'mcu_source_files_checked': len(profile['mcu_source_sha256']),
        'place_seed': 2, 'slice_ceiling': 20091,
        'mcu_optimization': '-Os', 'payload_version': 95,
        'hardware_access_during_packaging': False,
    }
    (dest / 'SUBMISSION_INFO.json').write_text(
        json.dumps(info, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    readme = dest / 'README.md'
    readme.write_text(
        '# 比赛提交工程 R6 FPGA 与 MCU r18\n\n'
        '本目录已应用最终发布源码快照，可直接按下文构建。'
        '源码对应关系见 `SUBMISSION_INFO.json` 与 '
        '`verification/r6_source_profile.json`；'
        '交付说明见 `docs/比赛提交说明.md`。\n\n' + readme.read_text(encoding='utf-8'),
        encoding='utf-8')
    write_manifest(dest)
    subprocess.run([sys.executable, 'tools/repository.py', 'verify'],
                   cwd=dest, env=env, check=True)
    print('SUBMISSION_SOURCE_PROFILE_VERIFIED', dest)


if __name__ == '__main__':
    main()
