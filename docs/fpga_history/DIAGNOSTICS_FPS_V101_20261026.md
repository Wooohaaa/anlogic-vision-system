# v101r1 FPS 区域诊断（已写入联合 Flash）

按用户最新要求，不增加第八页，KEY1 保留 0～6 原模式。扩展原有 FPS 行：

`IN:60 OUT:60 C:V0 H:-0 D:?0 A:V0 M:00`

- IN：完整写入 DDR、且关联到有效相机帧首的帧数/秒。
- OUT：完整显示全部 720 行、无读取 FIFO 下溢且不同于上一已显示源帧的帧数/秒。重复显示不计入。
- C/H/D/A/M：颜色形状、手势、数字、ArUco、运动。
- 状态：0 关闭；? 尚无结果发布；- 发布了无目标结果；V 有效目标；S 连续两个一秒边界未发布。
- 状态后的数字：跨过的一秒边界数，3 表示 3 或更多；这是粗略活动年龄，误差小于一秒，不代表精确处理延迟。

FPS 使用 HDMI 75 MHz 既有毫秒时基，一秒一刷新，最大显示 99。OUT 复用现有相机捕获时间戳作帧标识，适用当前原生约60fps、相邻帧首相隔超过1ms的配置。65536ms 回绕的相邻帧正常去重；若超过一个完整回绕周期一直不显示新帧，恰好恢复到同一时间戳会漏计恢复的第一帧。诊断不修改像素、DDR 调度、检测输出、MCU 程序或按键用途。

ArUco 的更新脉冲来自已存在的结果提交 toggle，通过现有同步器进入 HDMI 域；在完整结果银行更新后一拍供诊断读取，不用 ID 是否变化推断心跳。关闭功能会清除该诊断的已见结果。

## 验证进度

当前源码已通过：

- `tb_stream_fps_v101`：重复帧、不完整帧、无效帧、下溢、计数饱和、时间戳相邻回绕、空闲归零、秒边界与复位。
- `tb_latency_frames_v101`：相机/DDR/HDMI 三个异步时钟，完整写入、部分写入、覆盖、额外写入、无效槽。
- 75 MHz 毫秒时基原有测试。
- 原有整帧数字/运动 OSD 测试，921600 个像素的清洁视频支路和边框约束不变。
- 新诊断同一行整帧文字测试与关闭、等待、无目标、有效、过期、年龄饱和及更新恢复。
- ArUco MMIO→AHB→CDC→HDMI 回放，三次提交均在结果银行稳定后发布单周期更新；原有四边框和 RGB 坐标轴保留。
- 视频读取器与 v100 源码逐字比较，唯一差异为 FIFO 下溢观察输出；所有图像算法、模式控制和 MCU 程序均未改动。

证据：`tmp/v101_diag/result.json`、`tmp/v101_diag/transport_result.json`。这些是仿真及源码等价性证据，不是板上识别效果保证。

第一轮 v101 布局为 20031 Slice、108 ERAM、31 DSP，超出目标31 Slice，未布线、未烧录。v101r1 去掉独立的 HDMI 行计数器，直接复用 OSD 已有行计数器的有效最后行结束事件；去掉重复有效位寄存器，诊断年龄由 4bit 改为 2bit 饱和计数。检测算法及全部功能保持。

v101r1 布局通过：19910/21216 Slice（93.84%），108/108 ERAM，31/40 DSP。比已部署 v100 增加 12 Slice，无新增 ERAM/DSP。证据为 `tmp/v101r1_area_result.json`，状态 `PLACED_RESOURCE_PASS_NOT_ROUTED`；该结果不能当作最终 Routed 时序或可烧录镜像。

## 最终结果与部署

2026-10-26 22:08:03，官方 BitWriter 终端完成一次联合 Flash 写入及校验。未额外下载 SRAM，未发送 COM 控制命令，未启动电机。MCU 仍为原 v95，启动默认 OFF。

最终资源：19910 Slice、108 ERAM、31 DSP。最终报告 Confidence=Routed；SWNS +0.122ns、HWNS +0.020ns、STNS/HTNS 0。STA coverage 95.28%，不能称100%约束覆盖。

镜像 SHA256：

- FPGA：`deliverables/camera_hdmi_v101r1_diagnostics_fps_fpga.bit`，`f63336687c7730065b52799ae6111206aa1a1e2f5c90d55fe45d30cb21095d46`。
- 联合 Flash：`deliverables/camera_hdmi_v101r1_diagnostics_fps_fpga_mcu_flash.bit`，`66fa3477378ea872c7782cbe5e4d1952ff661afb9d1fb0057a20dbf347f8fab6`。
- 原 MCU v95 ELF：`965651c38b5adb842bbc6402b001bfb9683e2047552f9c189d96668910c69736`，无新增 MCU 计算或存储需求。

证据：`tmp/v101r1_build_result.json`、`tmp/v101r1_flash_build_result.json`、`tmp/v101r1_flash_programmed.json`、`tmp/v101r1_flash_program.log`、`tmp/v101r1_independent_audit.json`。独立审计核对825项冻结输入、266个维护源码，只改动五个观察/显示相关文件；模式控制、图像算法、约束与 MCU 程序不变。

Flash 写入校验已确认；尚未验证断电冷启动与实际 HDMI 上的计数、识别表现。OUT 表示 FPGA 内部完整有效帧的输出统计，不测量外部显示器或 USB 采集卡的丢帧。
