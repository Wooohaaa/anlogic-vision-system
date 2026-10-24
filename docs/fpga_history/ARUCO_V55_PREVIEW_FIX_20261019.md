# v55 蓝色法向轴与调度修复（未部署）

用户确认黑色外框约 120×120 mm，打印未拉伸。本轮接续 `ARUCO_BLUE_AXIS_AUDIT_20261019.md` 的诊断，已修改 MCU 维护源、完成离线回归、交叉编译及联合 Flash 文件打包；未写 SRAM、TCM 或 Flash，舵机未开启。

## 修改

- 删除每次识别完成后额外等待 100 ms 的空闲。改为最小 40 ms 启动间隔；保留协作式处理和安全控制检查。这不是 25 Hz 实测承诺，采集和算法耗时仍决定最终刷新率。
- 无标定模式保留红绿平面轴。蓝轴使用最多 6 次迭代的刚性位姿拟合，并检查旋转列一致性、尺度比、重投影残差、正深度和投影长度；不可靠则把 Z 终点置为原点，隐藏蓝线，而不是显示旧蓝线。
- 126 组录像诊断轮廓的多视角正方形一致性拟合，假定中心主点、零畸变、方形像素，候选焦距约 1570 px。预览假设从 640 改为 1600 px。分时段拟合得到 1540/1840 px，说明该估计仍不精确；并非真实相机标定，不启用精确位姿输出。
- 原有已标定求解接口仍保留最多 16 次迭代。FPGA 接口、绘制逻辑和其余功能未更改。

## 已验证与限制

- 基础 C/RTL 回归通过：字典、快照、超时、运行时安全、270 个合成图像、240 个标定位姿、PWM、AHB。
- 新预览 400 个无噪声合成视角全部通过；395 个显示 Z，其余投影过短隐藏。该结果不是实际镜头精度。
- 126 组录像参考角点输入：79 组保留 Z，47 组隐藏 Z。参考来自带 OSD 录像的粗轮廓，不是姿态真值；也不是完整实时识别链路的成功率。
- `host/tests/aruco_v55_hdmi_path.py` 单独核验当前 C 的 MMIO 记录经过 AHB、CDC、HDMI，以及零长度 Z 的传输/隐藏约定。零长度输入是接口夹具，不冒充第二次 C 图像识别。
- MCU text 30800 字节（比原 v39 增加 800），data 288、BSS 16580 不变，链接通过；未实测新 MCU 时延及最坏栈占用。
- FPGA 配置字节与 v54 完全相同：额外 Slice 为 0。沿用已通过布局布线的 19494/21216 Slice（91.88%）、97/108 ERAM、25/40 DSP，非本轮重新综合数据。

## 产物

- MCU：`deliverables/mcu_aruco_v55.elf`
  SHA256 `1A37280AB34199A31E6923E090D5C8E2066535BF7BA2E0E38FCD448790958B45`
- 联合掉电保持镜像：`deliverables/camera_hdmi_v55_fpga_mcu_flash.bit`
  SHA256 `E3DD68D40D712351F931390CE5813FFC7A80D0CCFDAFCBCA346EFB7691682A6F`
- 打包核验：`tmp/v55_flash_build_result.json`，状态 `FLASH_IMAGE_VERIFIED_NOT_PROGRAMMED`。同一 FPGA 配置、原 bootloader、新 MCU CRC 均核验，bootloader 指令模拟验证有效载荷拷贝/跳转和损坏载荷拒绝；不是板上冷启动证明。

下一步先部署验证 MCU 处理时间、显示刷新与移动场景，再决定是否固化。准确三维轴仍需实际摄像头内参和畸变标定，120 mm 尺寸不能替代它。

## 用户授权后的 Flash 部署

2026-10-19 20:46（北京时间），按用户“烧录”指令运行 `tools/program_v55_flash.ps1`，官方 BitWriter CLI 确认目标 PH1P35MDG324，完成联合 Flash 写入和原生校验。所有 v55 镜像/MCU 源码及冻结 v53 输入哈希在写入前后匹配。证据：`tmp/v55_flash_program.log`、`tmp/v55_flash_programmed.json`。没有启用舵机，没有重复下载。

当前状态为 `FLASH_PROGRAMMED_NATIVE_VERIFY_PASS_COLD_BOOT_PENDING`。尚需用户断电重启并检查 HDMI/串口，不能把 Flash 校验当作已通过实际冷启动或画质验证。

烧录后仅查询串口，应用已响应新版本特有状态 `nominal_f_px=1600` 和 `3=planar-only`，ArUco 帧数推进、errors=0，armed=0、remaining=0、faults=0；说明新 MCU 当前正在运行。未进行额外 GDB load/设置 PC/TCM 恢复。串口记录 `tmp/v55_post_flash_uart.log`，仍不替代物理断电启动验证。
