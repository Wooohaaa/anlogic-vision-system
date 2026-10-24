# ArUco 三维轴链路 v37

> 注意：本文件记录的是 v37 的“真实相机内参＋PnP 位姿”精确投影方案历史。按目前需求，v38 已改为不依赖棋盘标定的 120 mm 平面映射；当前实现和 Z 轴限制请看 [ARUCO_AXES_V38_UNCALIBRATED.md](ARUCO_AXES_V38_UNCALIBRATED.md)。

## 行为与边界

- 用户实测标记黑色外框边长：120 mm，不含白边。
- 轴长为黑框边长的一半，即 60 mm。原点在标记中心，X 红、Y 绿、Z 蓝；沿用现有位姿定义：标记 X 向右、Y 向上、Z 从印刷面向外。
- MCU 用相机内参、5 参数畸变、旋转矩阵和米制平移投影原点及三个端点。FPGA 只执行定点画线，不增加帧缓存。
- 缺少真实标定、无标记、失效/超时、关闭检测时不显示三维轴；四边形与 ID 不依赖标定。
- 端点越界或深度非正时本版抑制整组轴，避免 11 位坐标溢出。极短或与视线重合的轴可能退化为点，这不是检测掉失。
- 保留现有单平面解的限制，不把低重投影误差等同于已经解决平面位姿歧义。

## 通信与时序

保留原 0x110 状态提交地址，bit31=检测有效，新增 bit30=轴有效。0x134/138/13c/140 保存原点/X/Y/Z 端点，格式 `{y[10:0],x[10:0]}`。0x144/148/14c 为三个轴的 Q10 斜率/半像素截距参数，格式与现有四边形边线相同。

MCU 必须先写全部端点、边线和角点，最后写 0x110 提交；接收端通过原 toggle 同步器取完整数据，HDMI 在帧开始锁存一组结果。生产更新间隔沿用现有 100 ms 间隔，不改变跨域协议。三色轴经过与像素相同的显示级数，Logo 优先保留。未改引脚、时钟或时序例外。

## 已执行的验证

- C 投影与 OpenCV `projectPoints` 比较：120 组合成相机/姿态，端点差小于 0.001 像素；未标定、非有限参数、轴长非法、背面/越界等 11 个拒绝案例输出清零。
- 实际 C runtime 写寄存器轨迹输入 AHB→CDC→HDMI RTL：完整 1280×720 帧包含三色轴，原四边形保留，提交前不激活、关闭/失效后清除通过。
- 原 ArUco C/RTL 回归通过，包括捕获、译码、位姿、AHB 错误恢复、PWM 安全。
- 标定工具用合成棋盘点验证内参恢复、视角/数量/分辨率拒绝门限；这些合成内参没有装入生产配置。

这些是主机 C 与 RTL 仿真，不是硬 MCU 指令级仿真，不代表板卡位姿精度或最坏运行时长已经实测。

## 完整工程实现结果（2026-10-16）

TD 完整综合、布局、布线及独立重新导入 Routed 检查通过：

| 资源 | v36 | v37 | 变化 |
| --- | ---: | ---: | ---: |
| Slice / 21,216 | 19,968 | 20,614 | +646，余 602 |
| LUT6 | 19,463 | 19,991 | +528 |
| 寄存器 | 17,251 | 17,707 | +456 |
| ERAM / 108 | 102 | 102 | 不变 |
| DSP / 40 | 19 | 22 | +3 |

最终 SWNS +0.125 ns、HWNS +0.020 ns、STNS/HTNS 均为 0。Slice 约占 97.16%，布线约 16 分钟，不应再轻率增加并行图形逻辑。

MCU text=28,324、data=288、bss=16,580 字节；相较 v34 代码增加 768 字节，data/bss 不变，栈配置仍 2,048 字节。静态栈报告中投影函数 144 字节、发布函数 112 字节；未做板卡栈高水位/WCET 验证。

- FPGA：`deliverables/camera_hdmi_v37_aruco_axes.bit`
- FPGA SHA256：`8E799AA58A5B4D3AA3BA60E39D61D4956CBE4FDDB75FB883966710C1C0C76CCD`
- MCU：`deliverables/mcu_aruco_v37.elf`
- MCU SHA256：`EF4B1AAC762A4451800898DD45CBE2435C57193726F210C898C1C9199DF5811A`
- 构建/仿真凭据：`tmp/v37_fpga_build_result.json`、`tmp/v37_mcu_build_result.json`、`tmp/v37_axes_validation.json`。
- 复现：`tools/test_aruco_axes_v37.ps1`、`tools/build_hdmi_v37.ps1`、`../mcu_tracking/build_aruco.ps1 -Revision v37`。

本轮未访问板卡、未烧录、未写 Flash、未开启舵机，板上仍为 v36。v37 MCU 会访问新增寄存器，必须与 v37 FPGA 配对，不能单独加载到 v36。已准备带版本/哈希/时序检查的终端 SRAM 与 MCU TCM 加载脚本；目前尚未执行。

## 你接下来需要做的事

1. 打印 `deliverables/aruco_calibration/chessboard_9x6.png`，贴平，不拉伸纸张。它是 10×7 方格、9×6 内角点。量打印后的一个方格边长（毫米）。
2. 用开发板摄像头拍摄棋盘，不要用手机拍摄。保持当前摄像头分辨率/裁切/镜像方式不变，使用直通模式，棋盘上不要覆盖 Logo、文字或检测框。
3. 用 HDMI 采集卡保留完整 1280×720 帧。采集卡不被 OBS 占用时，可运行：

   `python host/capture_aruco_calibration.py --device 设备编号`

   空格存一张，Q 退出；存储图像不含工具新增的提示文字。拍 20～30 张，棋盘在左/中/右、上/中/下移动，并有前后及左右倾斜，所有 54 个内角点都要入镜，避免模糊。不要只拍同一位置的重复帧；不要截图整个 OBS 窗口。
4. 把图片目录和实测方格尺寸提供给我，或运行：

   `python host/calibrate_aruco_camera.py --images captures/aruco_calibration --square-mm 实测数值 --marker-mm 120`

5. 工具检查分辨率、有效视图数、位置/倾角覆盖和重投影误差，输出 `deliverables/aruco_calibration/calibration.json` 与候选 `aruco_camera_config.h`。候选配置不会自动覆盖生产文件，也不会自动烧录。
6. 核对数据后，把真实参数接入 MCU 配置并重新构建，再部署 FPGA+MCU 匹配版本，验证轴方向和长度。FPGA bit 无须因单次标定参数变化而重综合。

当前生产 `aruco_camera_config.h` 明确为 `UA_ARUCO_CAMERA_AVAILABLE=0`；在取得真实标定之前，上板不会凭空出现可靠的三维轴。

依据：[OpenCV ArUco](https://docs.opencv.org/4.x/d5/dae/tutorial_aruco_detection.html)、[OpenCV 相机标定](https://docs.opencv.org/4.x/dc/dbb/tutorial_py_calibration.html)。
