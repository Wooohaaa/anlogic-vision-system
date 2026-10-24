# ArUco v39：去掉固定蓝轴，按平面法向估算投影

## 现场问题与修复

用户反馈的两张 HDMI 截图中，蓝色 Z 轴始终朝屏幕右上方。v38 的
`display_axes()` 确实使用 `x=center_x+zcomp, y=center_y-zcomp` 生成固定方向示意线，
因此这不是 OSD 缓存或坐标没有刷新，而是蓝轴的几何定义错误。

v39 删除固定方向计算。MCU 从标记四角求平面单应矩阵 H，去除明确假设的 K，
以两个平面基向量的叉积求法向，并投影离标记中心半个边长的 Z 端点。
X/Y 继续使用平面映射，120 mm 黑框对应 60 mm 轴长。蓝轴出屏时沿原线段方向
裁剪，几何输入失效或深度非法时清除轴组。没有标记、关闭 SW2 和超时清除逻辑保留。

这是 OpenCV 单应性位姿初始化相同的几何关系 `H ~ K [r1 r2 t]`，
参考 [OpenCV 官方单应性教程](https://docs.opencv.org/3.4.14/d9/dab/tutorial_homography.html)。

## 未标定的边界

当前继续遵从“暂不做棋盘标定”的要求：名义 `fx=fy=640 px`，主点为画面中心，
忽略镜头畸变。这相当于名义水平视场约 90 度，是预览假设，并非该摄像头的实测参数。
120 mm 边长本身不能确定镜头内参；蓝轴的方向与长度仍可能存在误差。
生产 `UA_ARUCO_CAMERA_AVAILABLE` 仍为 0，米制 POSE 仍报告未标定；
新增独立 `AXES mode=2` 表示估计内参预览，不宣称真实位姿可用于控制。
将来提供有效标定时，`AXES mode=1` 改用已有 PnP 结果和真实相机参数投影；
修复了 v38 显示路径即使有有效 PnP 也未使用该结果的问题。

正常行为：左右/上下倾斜纸面，蓝轴应随法向变化；仅在同一平面内旋转纸张，
法向本来不变，蓝轴不需要随着红绿轴一起转。标记正对镜头且位于光轴中心时，
Z 轴朝向摄像头，屏幕投影应缩成一个点，不再补画任意方向的长线。

## 验证与资源

- OpenCV 独立投影对照 476 组合成姿态，在相同假设内参下最大差异 0.000344 像素；
  这不是实机精度。包括 3 个 Z 出屏裁剪案例和 12 个非法输入清零案例。
- 验证相反倾斜时法向反向、四种纸面内旋转法向不变、居中正视时 Z 投影为零。
- 实际 C runtime 对 MMIO 的写入，经 AHB、CDC 到 HDMI 1280×720 整帧回归通过；
  关闭/失效时清除通过。原检测、位姿、PWM 安全和 AHB 错误恢复回归通过。
- 预览计算为封闭形式，不运行迭代 PnP，不申请动态内存或增加图像缓冲。
- MCU text：28,532 → 30,000 字节（增加 1,468）；data 288、BSS 16,580 不变，
  栈配置仍为 2,048 字节。实际目标检测条件下的最坏运行时间仍待现场统计。
- 生产 FPGA RTL、寄存器协议和 v37 bitstream 均未改动，FPGA 资源不增加。

复现：`tools/test_aruco_axes_v39.ps1`，`../mcu_tracking/build_aruco.ps1 -Revision v39`。
证据：`tmp/v39_axes_validation.json`、`tmp/v39_axes_estimated.log`、
`tmp/v39_axes_hdmi.log`、`tmp/v39_mcu_build_result.json`。
合成示意图：`deliverables/aruco_axes_v39/normal_sweep.png`，不是相机画面。

## 2026-10-17 实板更新

使用终端 `../mcu_tracking/load_aruco_v39_native.ps1 -Port COM15` 更新 MCU TCM，
保留当前 v37 FPGA SRAM 配置，未写 Flash。ELF 四个段均逐段比对成功，
串口返回新 `AXES mode=0 nominal_f_px=640` 身份行（查询时没有标记），
`armed=0 remaining=0 faults=0`。HDMI 上蓝轴的实际倾斜表现仍待用户观察。

- MCU：`deliverables/mcu_aruco_v39.elf`
- SHA256：`D952A80FEE124DDB1B76CCB10783A4C487F13DF9A8B6C9B608504B7992BBF178`
- 部署回执：`tmp/v39_mcu_native_deployment.json`
- 下载比对：`tmp/v39_mcu_gdb.log`，运行状态：`tmp/v39_mcu_off.log`
