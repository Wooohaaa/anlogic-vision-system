#ifndef UA_ARUCO_POSE_H
#define UA_ARUCO_POSE_H
#include "aruco_detect.h"
/* Camera: x right, y down, z forward. Marker: x right, y up, z out of
 * printed face. Canonical corners: (-,+), (+,+), (+,-), (-,-). SI units. */
typedef struct {
    unsigned calibrated,width,height;
    float fx,fy,cx,cy,k1,k2,p1,p2,k3,side_m,max_rms_px;
} ua_aruco_camera;
typedef struct {
    unsigned valid,iterations;
    float rotation[9],translation[3],quaternion[4],rms_px;
} ua_aruco_pose;
typedef struct {
    union {
        float homography[8][9];
        struct {float jacobian[8][6],normal[6][7];} lm;
    } phase; /* Initialization and refinement never need storage simultaneously. */
} ua_aruco_pose_workspace;
enum {UA_POSE_NO_MARKER=0,UA_POSE_OK=1,UA_POSE_UNCALIBRATED=-1,UA_POSE_BAD_INPUT=-2,
      UA_POSE_DEGENERATE=-3,UA_POSE_REPROJECTION=-4,UA_POSE_STALE=-5,UA_POSE_CAPTURE_ERROR=-6,
      UA_POSE_DISABLED=-7};
int ua_aruco_camera_valid(const ua_aruco_camera *camera);
/* Project marker centre, +X,+Y,+Z endpoints using measured intrinsics.
 * Translation/length are metres. Failure clears all outputs (never clamps). */
int ua_aruco_pose_axes(const ua_aruco_camera *camera,const ua_aruco_pose *pose,
                       float length_m,ua_aruco_point points[4]);
/* Display-only homography normal with assumed centered, square-pixel intrinsics.
 * focal_px is explicit and is NOT camera calibration. X/Y use the exact plane
 * mapping; Z follows the estimated plane normal. No metric pose is published.
 * Axis length is half the marker side. Only the Z segment is viewport-clipped.
 * A front-facing centered marker naturally has a zero-length projected Z. */
int ua_aruco_axes_estimated(const ua_aruco_point corner[4],unsigned width,unsigned height,
                            float focal_px,ua_aruco_point points[4]);
/* Quality-gated nominal-K preview, not calibrated metric pose. Keeps planar
 * X/Y exact; hides Z by setting endpoint=origin when geometry/fit is unreliable.
 * At most six pose refinement iterations, caller-owned reusable workspace. */
int ua_aruco_axes_preview(const ua_aruco_point corner[4],unsigned width,unsigned height,
                         float focal_px,ua_aruco_pose_workspace *workspace,
                         ua_aruco_point points[4],unsigned *normal_valid);
/* Bounded single-solution planar PnP, NOT a two-solution IPPE implementation.
 * A low reprojection error alone does not resolve planar pose ambiguity. */
int ua_aruco_pose_solve(const ua_aruco_camera *camera,const ua_aruco_point corner[4],
                      ua_aruco_pose_workspace *workspace,ua_aruco_pose *result);
/* Production 160x90 detection -> full720 calibration. Prefer measured boundary
 * corners on a sub-0.25px residual tie; otherwise require lower reprojection. */
int ua_aruco_pose_detection(const ua_aruco_camera *camera,const ua_aruco_detection *detection,
                          ua_aruco_pose_workspace *workspace,ua_aruco_pose *result);
#endif
