#ifndef UA_ARUCO_CAMERA_CONFIG_H
#define UA_ARUCO_CAMERA_CONFIG_H
/* No synthetic intrinsics in deployed firmware. Replace only with the output
 * of host/calibrate_aruco_camera.py using this camera's 1280x720 capture. */
#define UA_ARUCO_CAMERA_AVAILABLE 0
/* Display preview assumption ONLY, not measured calibration. The 2026-10-19
 * HDMI multiview square-consistency audit favours ~1570px over the old 640px
 * (90deg FOV) assumption. Rounded to 1600px to avoid claiming fit precision.
 * Principal point/distortion remain uncalibrated; quality gating is required.
 * This never enables metric pose or marks the camera as calibrated. */
#define UA_ARUCO_AXES_NOMINAL_FOCAL_PX 1600.0f
#endif
