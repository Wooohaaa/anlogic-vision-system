#!/usr/bin/env python3
"""Prepare and verify the TD GUI project.

Usage:
  python build.py verify   # read-only project consistency checks (default)
  python build.py setup    # sync maintained RTL and fix the .al project metadata

The default gesture profile is binary OPEN/FIST. Historical profiles require
--native-hand or --legacy-hand explicitly; --binary-hand remains supported.

This helper only synchronizes and verifies the TD 6.2.1 project; it does not
launch TD. Per the current workflow, the assistant runs the vendor synthesis,
implementation and bitstream flow separately, verifies its reports and delivers
the exact .bit path. The user programs the board through BitWriter.
"""

from __future__ import annotations

import hashlib
import argparse
import os
import re
import shutil
import sys


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PRJ_DIR = os.path.join(ROOT, "prj", "td_project")
AL_FILE = os.path.join(PRJ_DIR, "camera_to_dsi_display_hdmi.al")
USER_RTL = os.path.join(ROOT, "rtl", "user")
OFFICIAL_RTL = os.path.join(ROOT, "rtl", "official", "hdl_source")
PRJ_HDL = os.path.normpath(
    os.path.join(PRJ_DIR, "..", "user_source", "hdl_source")
)

TOP_USER = "design_top_user"
DEVICE = "PH1P35MDG324"
NATIVE_HAND_VARIANT = "--native-hand" in sys.argv
LEGACY_HAND_VARIANT = "--legacy-hand" in sys.argv
if sum(flag in sys.argv for flag in ("--native-hand", "--binary-hand", "--legacy-hand")) > 1:
    raise RuntimeError("Select only one gesture build variant")
# The deployed product is the pure-FPGA binary hand implementation. An
# unqualified setup must never silently replace it with the old profile.
BINARY_HAND_VARIANT = not (NATIVE_HAND_VARIANT or LEGACY_HAND_VARIANT)

USER_FILES = [
    "aruco/ua_aruco_snapshot.v",
    "aruco/ua_servo_pwm_safe.v",
    "aruco/ua_stepper_position.v",
    "aruco/ua_aruco_ahb_bridge.v",
    "aruco/ua_aruco_peripheral.v",
    "ua_tracking_mcu.v",
    "ua_red_ball_uart.v",
    "design_top_user.v",
    "isp_top_user.v",
    "ua_demosaic_border.v",
    "ua_awb_frame.v",
    "ua_photo_finish_96.v",
    "ua_raw_black_40.v",
    "ua_color_balance.v",
    "ua_luma_stats.v",
    "ua_auto_exposure.v",
    "ua_exposure_seg6.v",
    "ua_frame_latency.v",
    "blk_mem_gen_awb_delay_signal_compact.v",
    "ua_user_algo_96.v",
    "ua_motion_detect.v",
    "ua_motion_grid.v",
    "ua_motion_ref_ram.v",
    "ua_demosaic_line_ram.v",
    "ua_hand_profile.v",
    "ua_hand_native_classifier.v", "ua_hand_mask_frame.v", "ua_hand_blob_scan.v",
    "ua_hand_binary_native.v", "ua_hand_binary_shape.v",
    "ua_hand_label_map.v", "ua_hand_descriptor_build.v", "ua_hand_associate.v",
    "ua_hand_frame_classifier.v", "ua_hand_frame_policy.v", "ua_hand_temporal_vote.v",
    "ua_hand_shape_classifier.v", "ua_hand_tip_candidates.v", "ua_hand_tip_filter.v",
    "ua_hand_tip_width.v", "ua_hand_product_serial.v", "ua_hand_integer_math.v",
    "ua_hand_defect_geometry.v", "ua_hand_defect_scan.v", "ua_hand_defect_edge.v",
    "ua_hand_geometry_shared.v", "ua_hand_scratch_ram.v", "ua_hand_component_mask.v",
    "ua_hand_palm_distance.v", "ua_hand_wrist_median.v", "ua_hand_convex_hull.v", "ua_hand_contour_trace.v",
    "ua_track_detect.v",
    "ua_digit_recognizer.v",
    "ua_digit_card_locator.v",
    "ua_digit_template_rom.v",
    "ua_mode_ctrl.v",
    "ua_detect_switch_ctrl.v",
    "hdmi_mixer_user.v",
    "osd_char_lib.v",
    "anlogic_logo_rom.v",
]

# ROM data are deployment inputs, not Verilog compilation units.
USER_ASSETS = ["logo_compact9.mif", "logo_spans.mif", "font_compact.dath"]


def _td_user_text(relative_path: str, text: str) -> str:
    if relative_path == "osd_char_lib.v":
        marker = 'parameter INIT_FILE="rtl/user/font_compact.dath"'
        path = "../user_source/hdl_source/font_compact.dath"
        if text.count(marker) != 1:
            raise RuntimeError("Font INIT_FILE marker missing or duplicated")
        text = text.replace(marker, f'parameter INIT_FILE="{path}"')
    if relative_path == "design_top_user.v" and (NATIVE_HAND_VARIANT or BINARY_HAND_VARIANT):
        marker = ".ENABLE_HAND(1),"
        if text.count(marker) != 1:
            raise RuntimeError("Native hand build selector missing or duplicated")
        text = text.replace(marker, ".ENABLE_HAND(3)," if BINARY_HAND_VARIANT else ".ENABLE_HAND(2),")
    if relative_path == "anlogic_logo_rom.v":
        # GUI run working directories vary. Resolve this when the project moves.
        for parameter, asset in (("INIT_FILE", "logo_compact9.mif"),
                                 ("META_FILE", "logo_spans.mif")):
            marker = f'parameter {parameter}="rtl/user/{asset}"'
            path = "../user_source/hdl_source/" + asset
            if text.count(marker) != 1:
                raise RuntimeError(f"Logo {parameter} marker missing or duplicated")
            text = text.replace(marker, f'parameter {parameter}="{path}"')
    return text

# These vendor-example files contain small maintained integration fixes. ModelSim
# uses rtl/official while TD uses prj/user_source, so both copies must stay equal.
PATCHED_OFFICIAL_FILES = [
    "video_in.v",
    "video_out.v",
    "design_top_wrapper.v",
    os.path.join("ph1p35_ddr", "ph1p35_324_ddr_wrapper.v"),
    os.path.join("uics500_cfg", "uicfgcs500.v"),
    # 2026 SC500 factory HD mode.  Keep the legacy 1024x600 table available
    # for historical simulation, but compile the 720p configuration explicitly
    # in the hardware top.
    os.path.join("uics500_cfg", "uicfgcs500_720p.v"),
    os.path.join("uics500_cfg", "uics500reg_720p60.v"),
    os.path.join("uics500_cfg", "SC500GainTbl.v"),
    os.path.join("uics500_cfg", "uii2c_ce.v"),
    # Keep the official ISP geometry aligned with the 720p sensor mode.  The
    # original contest project hard-coded 1024x600 here, which mismatched the
    # updated SC500/HDMI path and made TD pack an inconsistent pixel pipeline.
    os.path.join("isp", "isp_top.v"),
    "hdmi_tx.v",
    "key_remove_shakes.v",
    "signal_delay.v",
    os.path.join("isp", "demosaic_4x_2_0", "line_buffer_demosaic.v"),
    os.path.join("isp", "demosaic_4x_2_0", "zhenghe.v"),
]

# These are new official-source entries that did not exist in the original
# TD project manifest.  setup_al adds them with the same P&R attributes as the
# maintained user sources so a fresh project cannot silently omit the 720p
# sensor table.
EXTRA_VERILOG_FILES = [
    os.path.join("uics500_cfg", "uicfgcs500_720p.v"),
    os.path.join("uics500_cfg", "uics500reg_720p60.v"),
    os.path.join("uics500_cfg", "uii2c_ce.v"),
]

# TD may keep generating syn_1 from a cached GUI source list.  The AWB modules
# are therefore included by the already-registered isp_top_user.v translation
# unit instead of being required as independent active project entries.
TD_INLINE_USER_FILES = {
    "ua_demosaic_border.v",
    "ua_awb_frame.v",
    "ua_photo_finish_96.v",
    "ua_raw_black_40.v",
    "signal_delay.v",
    "blk_mem_gen_awb_delay_signal_compact.v",
}
# This standalone implementation is not instantiated; the ISP uses the
# uniquely named compatibility implementation embedded in isp_top_user.v.
TD_UNUSED_USER_FILES = {"ua_color_balance.v"}


def _sha256(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _copy_files(source_root: str, relative_paths: list[str], label: str) -> bool:
    ok = True
    for relative_path in relative_paths:
        source = os.path.join(source_root, relative_path)
        target = os.path.join(PRJ_HDL, relative_path)
        if not os.path.isfile(source):
            print(f"ERROR: missing {label} source: {source}")
            ok = False
            continue
        os.makedirs(os.path.dirname(target), exist_ok=True)
        if label == "user" and (relative_path in ("anlogic_logo_rom.v", "osd_char_lib.v") or
                                (relative_path == "design_top_user.v" and (NATIVE_HAND_VARIANT or BINARY_HAND_VARIANT))):
            with open(source, encoding="utf-8") as stream:
                text = _td_user_text(relative_path, stream.read())
            with open(target, "w", encoding="utf-8", newline="\n") as stream:
                stream.write(text)
        else:
            shutil.copy2(source, target)
        print(f"  sync {label}: {relative_path}")
    return ok


def sync_user_files() -> bool:
    """Sync every maintained RTL file used by the TD GUI project."""
    users_ok = _copy_files(USER_RTL, USER_FILES, "user")
    assets_ok = _copy_files(USER_RTL, USER_ASSETS, "user-asset")
    official_ok = _copy_files(
        OFFICIAL_RTL, PATCHED_OFFICIAL_FILES, "official-patch"
    )
    if users_ok and official_ok and assets_ok:
        print(f"OK: maintained RTL synchronized to {PRJ_HDL}")
    return users_ok and official_ok and assets_ok


def _replace_one(text: str, pattern: str, replacement: str, description: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.DOTALL)
    if count != 1:
        raise RuntimeError(f"cannot update {description}: matches={count}")
    return updated


def setup_al() -> bool:
    """Synchronize RTL and make design_top_user the persistent TD GUI top."""
    if not sync_user_files():
        return False
    if not os.path.isfile(AL_FILE):
        print(f"ERROR: missing TD project: {AL_FILE}")
        return False

    with open(AL_FILE, encoding="utf-8") as stream:
        al_text = stream.read()

    # TD stores an absolute project directory separately from its relative
    # source list. Relocate it too when a delivery is moved to another drive.
    portable_project_dir = "."
    al_text = _replace_one(
        al_text, r'(<Project\b[^>]*\bPath=")[^"]*(")',
        r'\g<1>' + portable_project_dir + r'\g<2>', "project directory",
    )

    # Keep the maintained top source in the file list even if setup is run on a
    # fresh copy of the official project.
    al_text = re.sub(
        r'Path="[^"]*design_top_wrapper\.v"',
        f'Path="../user_source/hdl_source/{TOP_USER}.v"',
        al_text,
        count=1,
    )

    verilog_end = al_text.find("</Verilog>")
    if verilog_end < 0:
        print("ERROR: cannot locate </Verilog> in TD project")
        return False

    existing_orders = [
        int(value)
        for value in re.findall(r'Name="CompileOrder" Val="(\d+)"', al_text)
    ]
    next_order = max(existing_orders, default=49) + 1
    # TD accepts both slash styles in an .al file, but treats the two spellings
    # as separate file-set members. Older setup runs could therefore append a
    # second copy of a source when the original project used backslashes.
    existing_paths_normalized = {
        path.replace("\\", "/")
        for path in re.findall(r'<File Path="([^"]+)"', al_text)
    }
    for user_file in reversed(USER_FILES + EXTRA_VERILOG_FILES):
        if user_file in TD_INLINE_USER_FILES or user_file in TD_UNUSED_USER_FILES:
            continue
        project_path = (
            "../user_source/hdl_source/" + user_file.replace("\\", "/")
        )
        if project_path.replace("\\", "/") in existing_paths_normalized:
            continue
        entry = (
            f'\n            <File Path="{project_path}">\n'
            "                <FileInfo>\n"
            '                    <Attr Name="UsedInSyn" Val="true"/>\n'
            # TD's .al parser expects the same literal attribute spelling used
            # by projects written by the GUI.  Despite the XML-like format,
            # escaping '&' here makes TD silently omit the whole source entry
            # from the generated synthesis .prj file.
            '                    <Attr Name="UsedInP&R" Val="true"/>\n'
            '                    <Attr Name="BelongTo" Val="design_1"/>\n'
            f'                    <Attr Name="CompileOrder" Val="{next_order}"/>\n'
            "                </FileInfo>\n"
            "            </File>"
        )
        al_text = al_text[:verilog_end] + entry + al_text[verilog_end:]
        verilog_end += len(entry)
        next_order += 1
        existing_paths_normalized.add(project_path.replace("\\", "/"))

    # Files textually included by isp_top_user.v must not also be compiled as
    # standalone design units. Preserve their entries for IDE navigation, but
    # mark any present entries excluded from synthesis/implementation.
    for relative_path in TD_INLINE_USER_FILES:
        project_path = "../user_source/hdl_source/" + relative_path.replace("\\", "/")
        entry_pattern = (
            r'(<File Path="' + re.escape(project_path) + r'">)(.*?)(</File>)'
        )

        def mark_auto_excluded(match: re.Match[str]) -> str:
            entry_body = match.group(2)
            if re.search(
                r'<Attr Name="AutoExcluded" Val="true"\s*/>', entry_body
            ):
                return match.group(0)
            close_index = entry_body.find("</FileInfo>")
            if close_index < 0:
                return match.group(0)
            entry_body = (
                entry_body[:close_index]
                + '                    <Attr Name="AutoExcluded" Val="true"/>\n'
                + entry_body[close_index:]
            )
            return match.group(1) + entry_body + match.group(3)

        al_text = re.sub(
            entry_pattern, mark_auto_excluded, al_text, count=1, flags=re.DOTALL
        )

    try:
        project_name = os.path.splitext(os.path.basename(AL_FILE))[0]
        al_text = _replace_one(
            al_text,
            r"(<Name>)[^<]*(</Name>)",
            rf"\g<1>{project_name}\g<2>",
            "Project/Name",
        )
        al_text = _replace_one(
            al_text,
            r"(<TOP_MODULE>.*?<LABEL>)[^<]*(</LABEL>)",
            rf"\g<1>{TOP_USER}\g<2>",
            "TOP_MODULE/LABEL",
        )
        al_text = _replace_one(
            al_text,
            r"(<TOP_MODULE>.*?<MODULE>)[^<]*(</MODULE>)",
            rf"\g<1>{TOP_USER}\g<2>",
            "TOP_MODULE/MODULE",
        )
    except RuntimeError as error:
        print(f"ERROR: {error}")
        return False

    with open(AL_FILE, "w", encoding="utf-8", newline="") as stream:
        stream.write(al_text)
    print(f"OK: TD project metadata updated, top={TOP_USER}")
    return True


def verify_project() -> bool:
    """Check the checked-in TD project without modifying it."""
    errors: list[str] = []
    if not os.path.isfile(AL_FILE):
        print(f"ERROR: missing TD project: {AL_FILE}")
        return False

    # The HX1P35A board has four slide switches (SW1..SW4).  KEY2/KEY3 are
    # momentary buttons on B9/C7, so accepting the old six-input mapping here
    # would make the first two detection controls appear dead on hardware.
    pin_file = os.path.join(PRJ_DIR, "..", "user_source", "constraints_source", "pin.adc")
    if not os.path.isfile(pin_file):
        print(f"ERROR: missing pin constraint file: {pin_file}")
        return False
    with open(pin_file, encoding="utf-8") as stream:
        pin_text = stream.read()
    expected_switch_pins = ("A4", "B4", "E11", "D11")
    for index, location in enumerate(expected_switch_pins):
        pattern = (
            rf"\{{\s*I_detect_sw\[{index}\]\s*\}}\s*"
            rf"\{{[^}}]*LOCATION\s*=\s*{location}\s*;"
        )
        if not re.search(pattern, pin_text):
            errors.append(
                f"I_detect_sw[{index}] is not constrained to the SW pin {location}"
            )
    if re.search(r"I_detect_sw\[[45]\]", pin_text):
        errors.append("pin ADC still contains obsolete I_detect_sw[4]/[5] entries")

    # The four momentary keys are input-only HDIO pins.  The board example
    # intentionally uses pull-ups without DRIVESTRENGTH; TD rejects a drive
    # strength attribute on an INPUT (USR-8409/USR-8168).
    expected_button_pins = ("D5", "A9", "B9", "C7")
    for index, location in enumerate(expected_button_pins):
        pattern = (
            rf"\{{\s*I_button\[{index}\]\s*\}}\s*"
            rf"\{{[^}}]*LOCATION\s*=\s*{location}\s*;"
        )
        if not re.search(pattern, pin_text):
            errors.append(
                f"I_button[{index}] is not constrained to the KEY pin {location}"
            )
        strength_pattern = (
            rf"set_pin_assignment\s+\{{\s*I_button\[{index}\]\s*\}}"
            rf"\s*\{{[^}}]*DRIVESTRENGTH"
        )
        if re.search(strength_pattern, pin_text):
            errors.append(
                f"I_button[{index}] is an input and must not specify DRIVESTRENGTH"
            )

    if re.search(r'O_eth_|IO_eth_', pin_text):
        errors.append('obsolete Ethernet pin assignments remain')

    # Dedicated SLP/RST terminals, BANK32 = 3.3V, GPIOB2..9 = J2.3..10.
    motor_pins = {
        'O_motor_step[0]': 'E12', 'O_motor_dir[0]': 'E16',
        'O_motor_awake[0]': 'E17', 'O_motor_step[1]': 'F13',
        'O_motor_dir[1]': 'F14', 'O_motor_awake[1]': 'F18',
        'O_motor_reset_n[0]': 'G17', 'O_motor_reset_n[1]': 'H17',
    }
    for port, ball in motor_pins.items():
        pattern = (r'\{\s*' + re.escape(port) + r'\s*\}\s*'
                   r'\{[^}]*LOCATION\s*=\s*' + ball + r'\s*;[^}]*IOSTANDARD\s*=\s*LVCMOS33\s*;')
        if not re.search(pattern, pin_text):
            errors.append(f'{port} must use dedicated 3.3V pad {ball}')
        owners = re.findall(r'set_pin_assignment\s+\{([^}]+)\}\s*\{[^}]*LOCATION\s*=\s*' + ball + r'\s*;', pin_text)
        if len(owners) != 1:
            errors.append(f'Motor pad {ball} has {len(owners)} owners')

    # The supplied static seven-segment example uses six active-low digit
    # selects and eight active-low segment lines.  Keep these checks here so a
    # future pin-file edit cannot silently leave the new top-level outputs
    # unconstrained (which would make TD bitgen reject the design).
    expected_seg_pins = {
        **{f"O_seg_sel[{i}]": pin for i, pin in enumerate(
            ("G15", "G14", "A17", "A18", "B16", "A15")
        )},
        **{f"O_seg_led[{i}]": pin for i, pin in enumerate(
            ("C9", "C11", "B11", "E7", "E6", "B6", "B7", "E5")
        )},
    }
    for signal, location in expected_seg_pins.items():
        pattern = (
            rf"set_pin_assignment\s+\{{\s*{re.escape(signal)}\s*\}}\s*"
            rf"\{{[^}}]*LOCATION\s*=\s*{location}\s*;"
        )
        if not re.search(pattern, pin_text):
            errors.append(f"{signal} is not constrained to seven-segment pin {location}")

    # TD 6.2.1 can retain a stale generated source list for an existing run.
    # Keep a uniquely named scanner copy in the guaranteed top source; the
    # standalone scanner remains in the project list for fresh runs/simulation.
    top_user_source = os.path.join(USER_RTL, "design_top_user.v")
    with open(top_user_source, encoding="utf-8") as stream:
        top_user_text = stream.read()
    if not re.search(r"module\s+ua_exposure_seg6_embedded\b", top_user_text):
        errors.append(
            "design_top_user.v must embed ua_exposure_seg6_embedded to avoid a stale TD black box"
        )

    if re.search(r"\b(?:O_eth_|IO_eth_|ua_eth_video_bridge|ua_yt8511_config)", top_user_text):
        errors.append("Ethernet functionality remains in the top")
    if not re.search(r"ua_ae_panel_embedded\s+u_ae_panel\s*\([^;]*\.I_index\(S_gain_index\)[^;]*\.I_enable\(S_ae_auto_enable_s1\)", top_user_text, re.DOTALL):
        errors.append("fixed AE panel is not connected to gain index and KEY4 enable")

    with open(AL_FILE, encoding="utf-8") as stream:
        al_text = stream.read()

    def require(pattern: str, description: str) -> None:
        if not re.search(pattern, al_text, flags=re.DOTALL):
            errors.append(description)

    project_name = os.path.splitext(os.path.basename(AL_FILE))[0]
    require(
        rf"<Name>{re.escape(project_name)}</Name>",
        f"project <Name> does not match .al filename stem {project_name}",
    )
    require(rf"<Device>{re.escape(DEVICE)}</Device>", f"device is not {DEVICE}")
    require(
        rf"<TOP_MODULE>.*?<LABEL>{TOP_USER}</LABEL>.*?<MODULE>{TOP_USER}</MODULE>",
        f"persistent top is not {TOP_USER}",
    )
    require(r'Path="camera_to_dsi_display\.sdc"', "project SDC is not listed")
    require(
        r'Path="\.\./user_source/constraints_source/pin\.adc"',
        "pin ADC is not listed",
    )

    project_paths = re.findall(r'<File Path="([^"]+)"', al_text)
    if 'Name="UsedInP&amp;R"' in al_text:
        errors.append(
            "invalid TD attribute UsedInP&amp;R; use literal UsedInP&R"
        )
    for project_path in project_paths:
        resolved = os.path.normpath(os.path.join(PRJ_DIR, project_path))
        if not os.path.exists(resolved):
            errors.append(f"missing project entry: {project_path}")

    # These AWB files are included by isp_top_user.v because TD can regenerate
    # syn_1 from a stale GUI file list. Verify the include contract and ensure
    # any standalone entries remain excluded to avoid duplicate definitions.
    isp_user_source = os.path.join(USER_RTL, "isp_top_user.v")
    with open(isp_user_source, encoding="utf-8") as stream:
        isp_user_text = stream.read()
    inline_awb_files = (
        "ua_awb_frame.v",
        "signal_delay.v",
        "blk_mem_gen_awb_delay_signal_compact.v",
    )
    for relative_path in inline_awb_files:
        if not re.search(
            rf'^\s*`include\s+"{re.escape(relative_path)}"',
            isp_user_text,
            flags=re.MULTILINE,
        ):
            errors.append(
                f"isp_top_user.v must include AWB dependency {relative_path}"
            )
        project_entry = (
            "../user_source/hdl_source/" + relative_path.replace("\\", "/")
        )
        entry_pattern = (
            r'<File Path="' + re.escape(project_entry) + r'">(.*?)</File>'
        )
        entry_match = re.search(entry_pattern, al_text, flags=re.DOTALL)
        if entry_match and not re.search(
            r'<Attr Name="AutoExcluded" Val="true"\s*/>',
            entry_match.group(1),
        ):
            errors.append(
                f"textually included AWB RTL must be AutoExcluded as a standalone source: {relative_path}"
            )

    for relative_path in USER_FILES:
        project_entry = (
            "../user_source/hdl_source/" + relative_path.replace("\\", "/")
        )
        if (
            project_entry not in project_paths
            and relative_path not in TD_INLINE_USER_FILES
            and relative_path not in TD_UNUSED_USER_FILES
        ):
            errors.append(f"user RTL missing from project file list: {relative_path}")
        source = os.path.join(USER_RTL, relative_path)
        target = os.path.join(PRJ_HDL, relative_path)
        if (relative_path in ("anlogic_logo_rom.v", "osd_char_lib.v") or
            (relative_path == "design_top_user.v" and (NATIVE_HAND_VARIANT or BINARY_HAND_VARIANT))) and os.path.isfile(target):
            with open(source, encoding="utf-8") as stream:
                expected = _td_user_text(relative_path, stream.read())
            with open(target, encoding="utf-8") as stream:
                matches = stream.read() == expected
        else:
            matches = os.path.isfile(target) and _sha256(source) == _sha256(target)
        if not matches:
            errors.append(f"user RTL is not synchronized: {relative_path}")

    for relative_path in USER_ASSETS:
        source = os.path.join(USER_RTL, relative_path)
        target = os.path.join(PRJ_HDL, relative_path)
        if not os.path.isfile(source) or not os.path.isfile(target) or _sha256(source) != _sha256(target):
            errors.append(f"ROM asset missing or not synchronized: {relative_path}")

    for relative_path in PATCHED_OFFICIAL_FILES:
        source = os.path.join(OFFICIAL_RTL, relative_path)
        target = os.path.join(PRJ_HDL, relative_path)
        if not os.path.isfile(target) or _sha256(source) != _sha256(target):
            errors.append(f"official integration patch is not synchronized: {relative_path}")

    for relative_path in EXTRA_VERILOG_FILES:
        project_entry = (
            "../user_source/hdl_source/" + relative_path.replace("\\", "/")
        )
        if project_entry not in project_paths:
            errors.append(f"new 720p sensor source missing from project file list: {relative_path}")
        source = os.path.join(OFFICIAL_RTL, relative_path)
        target = os.path.join(PRJ_HDL, relative_path)
        if not os.path.isfile(target) or _sha256(source) != _sha256(target):
            errors.append(f"720p sensor source is not synchronized: {relative_path}")

    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        print(f"FAIL: TD project preflight found {len(errors)} issue(s)")
        return False

    print(
        f"OK: TD project preflight top={TOP_USER} device={DEVICE} "
        f"entries={len(project_paths)} maintained_files="
        f"{len(USER_FILES) + len(PATCHED_OFFICIAL_FILES) + len(EXTRA_VERILOG_FILES)} "
        f"hand={'binary' if BINARY_HAND_VARIANT else 'native' if NATIVE_HAND_VARIANT else 'legacy'}"
    )
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", nargs="?", choices=("setup", "verify"), default="verify")
    variants = parser.add_mutually_exclusive_group()
    for variant in ("binary", "native", "legacy"):
        variants.add_argument(f"--{variant}-hand", action="store_true")
    command = parser.parse_args().command
    if command == "setup":
        return 0 if setup_al() and verify_project() else 1
    if command == "verify":
        return 0 if verify_project() else 1
    print(__doc__)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
