# ArUco axes without chessboard calibration (v38)

> Historical v38 behavior below: its fixed up/right blue cue has been replaced
> by the v39 estimated plane-normal projection. Current implementation and
> deployment: [ARUCO_AXES_V39_ESTIMATED_NORMAL.md](ARUCO_AXES_V39_ESTIMATED_NORMAL.md).

The measured black outer marker border is 120 mm. The MCU maps its four detected, canonically ordered corners to a known 120 mm square by a planar projective transform and draws the origin at the mapped center. The red +X endpoint and green +Y endpoint are each 60 mm from the center, so they land at the corresponding edge midpoint. This uses the marker's known planar geometry and does not require camera intrinsics or a chessboard calibration.

The blue +Z line is only a screen-space visual cue: it is drawn diagonally up/right with a length approximated from the projected 60 mm in-plane axes, clipped to the display. A single planar square and no camera intrinsics cannot determine the real projection of a point 60 mm in front of the marker. Do not use this blue line as metric pose, camera-space direction, or robot guidance. The existing calibrated PnP/reporting path remains optional and independent; with the current `UA_ARUCO_CAMERA_AVAILABLE=0`, the pose status remains uncalibrated while the visual axes still display.

The existing FPGA v37 register/CDC/HDMI drawing interface is unchanged. The v38 change is MCU runtime-side geometry only. Status bit 31 still means marker detected; bit 30 means a drawable three-axis overlay was committed, not that metric 3D pose is calibrated. When detection is disabled, stale, or absent, the complete overlay bank is cleared.

## Verification

Run `tools/test_aruco_axes_v38.ps1` for the host C detector/runtime checks and the full 1280x720 C-to-MMIO-to-AHB-to-CDC-to-HDMI RTL test. The front-facing fixture also checks that the planar endpoints land at the edge midpoints (half of 120 mm). The generated preview at `deliverables/aruco_axes_v38/rtl_axes_uncalibrated.png` is an RTL simulation frame, not a physical camera capture. The MCU build is `../mcu_tracking/build_aruco.ps1 -Revision v38`: text 28,532 bytes, data 288 bytes, BSS 16,580 bytes; SHA256 `D63EF0551E924BEFA725953E1EB81A471C0FC6F9321156DB605A4A4D5426C957`. Build receipt and input hashes are `tmp/v38_mcu_build_result.json` and `tmp/v38_mcu_source_hashes.json`. The matching FPGA remains `deliverables/camera_hdmi_v37_aruco_axes.bit` (previously routed and verified, not reprogrammed in this change).

The screen-space blue axis and display orientation still need visual confirmation on the actual board.

## SRAM and TCM redeployment (2026-10-17)

The current board was successfully reloaded through terminal commands at 13:45
(FPGA) and 13:47 (MCU), Asia/Shanghai. The bitstream and ELF SHA256 values are
unchanged from those listed above. Native BitWriter completed without an ERROR;
the independent post-load scan returned configuration ID `0x4808f0e7` and status
`0xA9C0125D` (DONE high). All four MCU ELF sections compared successfully.
A subsequent runtime query counted 369 ArUco frames with `errors=0`,
`faults=0`, `armed=0`, and `remaining=0`. No marker was detected during that
query. Current HDMI marker/axis appearance still needs observation on the display.

The Flash boot image exposed only one configuration TAP. After loading the
MCU-enabled v37 SRAM image, the two-TAP MCU/configuration chain became available.
For this verified single-TAP startup case use
`tools/reprogram_hdmi_v37_after_reset.ps1 -InitialChain Single`; the default
`Dual` mode remains for an already active MCU-enabled configuration. The
programmer's multiline completion-marker check was corrected. Neither image
was written to Flash; FPGA SRAM and MCU TCM must be reloaded after power loss.

USB enumeration was also repaired: the physical parent uses Windows `usbccgp`,
only `MI_00` uses WinUSB, and `MI_01` retains FTDI with COM15. Binding WinUSB to
the physical parent had hidden both interfaces. The exact parent was
re-enumerated and the previously installed Interface 0 driver package was
reapplied to `USB\\VID_0403&PID_6042&MI_00` through the Windows driver API.
No driver package was deleted.

Evidence:

- `tmp/v37_fpga_sram_reprogrammed_after_reset.json`
- `tmp/v37_reprogram_native.log` and `tmp/v37_reprogram_done_check.log`
- `tmp/v38_mcu_native_deployment.json` and `tmp/v38_mcu_gdb.log`
- `tmp/v38_runtime_after_redeploy_20261017_134856.log`
- `tmp/bind_jtag_mi00_existing_20261017.json`

SW2 enables the ArUco detector and overlay. With a detected 120 mm marker, HDMI
should show its quadrilateral, ID, red X axis, green Y axis, and blue screen-space
Z cue. The blue line retains the uncalibrated limitation described above.

## Board deployment (2026-10-16)

- FPGA v37 loaded through the official BitWriter SRAM/JTAG flow for `PH1P35MDG324`; independent configuration/DONE check passed. Receipt: `tmp/v37_fpga_sram_programmed.json`; Flash was untouched.
- MCU v38 loaded to TCM on COM15; all ELF sections compared successfully. Receipt: `tmp/v38_mcu_native_deployment.json`; Flash was untouched.
- Runtime safety query reported `armed=0`, `remaining=0`, `faults=0`, ArUco enabled, and 331 processed frames with zero capture errors after startup. At query time no marker was detected, so marker outline/axes were correctly absent. Servo outputs remain off.
- Physical HDMI appearance has not been observed remotely; place the 120 mm marker in view to confirm red/green planar axes and the blue visual cue on the display.
