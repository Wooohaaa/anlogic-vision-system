# v86：自动白平衡强偏色捕获范围修复

> **2026-10-23：用户反馈 v86r1 仍整体偏绿，实板效果未通过。按用户要求撤回该方向，v87 恢复 v83 颜色链路，仅保留卡通对齐和 HDMI 首行灰色覆盖。v86 的算法仿真缺口不能作为板上唯一根因。**

## 现场现象及证据边界

用户报告 v85r1 开关 KEY3 都偏绿。采集卡 1280×720 实抓可见整体偏绿；附件白色参考物的近似中央区域输出 RGB 中位数为 (142,176,87)。这已经经过 ISP、色调和 HDMI/采集卡，不能当作传感器 RAW，也不能据此证明原始通道比、KEY3 状态或实际增益。

实际 RAW 解码子模块→96bit 转换→首行桥→AWB 的 1280×8、28 帧受控仿真通过（`tools/test_v86_raw_awb_probe.py`），仅证明该输入的流/颜色和增益计算，不是实板根因证明。

## 确认的算法缺口

旧采样需要 min ≥ max/2，且通道校正限于 0.5～2.0。对 RGB=(60,100,40) 的合法非饱和参考，蓝通道所需增益 2.5，但所有样本被拒绝。连续 96 帧后 samples=0、gain_r=gain_b=65536，打开也等于单位增益，因此开关没有色彩变化。

此缺口已独立复现，但板上是否只有这一原因仍待验证。不能把截图的后处理颜色当作精确 RAW 回放。

## 修复契约

- `ua_awb_frame.v` 新增 `GREEN_CAST_RECOVERY`，默认 0 保留原有行为，产品 ISP 显式启用 1。
- 新模式允许 min ≥ max/3 的非饱和候选，通道增益限制为 0.5～3.0；不使用固定 RGB 校色系数。
- 暗像素阈值、过曝排除、至少两象限覆盖、已占用象限方向一致、三次稳定估计、帧边界提交、1/8 平滑和校正后中性色跟踪规则保留。
- 9bit 输出超过 511 时饱和，而非取低位回绕；8bit 输出仍饱和到 255。新增可达增益不应造成高光数值回绕。
- KEY3 关闭仍施加单位增益，统计和缓慢自适应继续；重新开启使用已有完整增益对。没有新增 MCU 运算、RAM 或除法器。
- 较宽采样仍无法从纯色物体和单色照明之间获得无歧义真值；象限/时间一致性降低风险，并不能消除这一先验限制。增益到 3.0 仍不能修复任意强偏色。

## 回归

`tools/test_awb_recovery_v86.py` 同时要求：

1. 旧参数配置明确复现 samples=0、单位增益的失败。
2. 新配置从真实估计器收敛为 gain_r=109219、gain_b=163833（约 1.667/2.500），四通道并行像素接近 (100,100,100)，ON→OFF→ON 输出和状态正确，不强制内部增益。
3. 保留极饱和绿色、暗噪声保持；0.5～3.0 增益网格遍历全部 256 个输入值检查 9bit 饱和和限制端点。
4. 旧参数下原 bootstrap、scene confidence、toggle、arithmetic 回归通过；跟框和首行桥回归通过。
5. 完整 1280×720、两帧实际 9bit AWB→5×5 finishing→显示算法→96/128 打包重新跑通，不复用 v85 的旧 AWB 哈希。

综合/布线的 Slice 上限仍为 19518，ERAM≤108，DSP≤40。全部通过才封装联合 Flash 并单次下载。MCU 仍为 v83，上电电机 OFF；不发送运动命令，不改电机逻辑。

## 当前状态

v86 针对性及完整 720p 回归通过，但布局 19525 Slice，比 19518 门限高 7；流程停止于布局后，未布线、未烧录。

v86r1 仅对等价的候选比较作资源精简：对 max≥min，旧的 2x 域属于 3x 域，因此启用新模式时只计算 3x 比较，不保留二者 OR。所有 32896 个合法 8bit min/max 组合穷举证明接收集合完全相同；修订后针对性 RTL 回归也通过，完整 720p 重新运行，不以源码哈希不一致复用 v86 记录。

最终资源、时序、SHA256 和烧录结果以 `tmp/v86r1_*result.json` / `tmp/v86r1_flash_programmed.json` 为准。未完成实板冷启动和白平衡效果验收。

v86r1 新的完整 720p 回归通过。布局占用为 Slice 19482/21216（91.83%）、ERAM 102/108、DSP 32/40；相对 v85r1 增加 21 Slice，未增加 ERAM/DSP，满足 ≤92% 门限，已进入布线。此处不是最终 Routed 时序或烧录通过声明。

## 最终实现和部署

初次 v86r1 布线完成 DRC 后未达到建立时序，SWNS=-1.064 ns（HDMI ArUco 描边路径），因此停止，未生成或烧录失败镜像；原失败日志和 `tmp/v86r1_initial_route_failure.json` 保留。

使用厂商 CLI 已说明的 `phys_opt -effort high -post_route -mode reroute`、`route -incremental` 对相同 RTL/同一布线数据库作物理修复，再运行原 hold 修复和最终检查。未改时钟、管脚、false path 或 multicycle；后优化只重排两条关键连线。脚本 `tools/finish_hdmi_v86r1_post_route.tcl`，日志 `tmp/v86r1_post_route.log`。

最终 Confidence Routed：Slice 19482/21216（91.83%）、ERAM 102/108、DSP 32/40；SWNS=0.132 ns、HWNS=0.020 ns、STNS=0、HTNS=0。STA coverage 为 95.35%，是既有约束下的工具覆盖率，不声称所有路径已约束。

- FPGA：`deliverables/camera_hdmi_v86r1_color_fpga.bit`，SHA256 `45ac2ac6aab14e2ceebd0bf32e22221f4c1f0bad3d029eee9578778143cc7e99`。
- FPGA＋MCU Flash：`deliverables/camera_hdmi_v86r1_fpga_mcu_flash.bit`，SHA256 `10a8083a74ca1cd2c5fcb69d2aaca741284be2c0a42b6e2b9a7eaf1615c5e064`。
- MCU 原 v83 ELF 和 payload 验证未改；本次不增加 MCU 白平衡或手势任务，不发送运动命令。电机启动仍由原 KEY2/MCU 策略控制。
- 2026-10-23 13:58（北京时间），官方 BitWriter 对 PH1P35MDG324 识别通过，Flash Page program and verify 完成，日志 `tmp/v86r1_flash_program.log` 有 `V86R1_FLASH_PROGRAM_VERIFY_COMPLETE`。只执行了一次 Flash 下载。
- 记录：`tmp/v86r1_build_result.json`、`tmp/v86r1_flash_build_result.json`、`tmp/v86r1_flash_programmed.json`；额外物理修复脚本/输入数据库哈希在 `tmp/v86r1_post_route_proof.json`。烧录后独立复核冻结源、两个镜像 SHA、全部最终时序指标及物理修复证明输入哈希，一致。

部署状态为 `FLASH_PROGRAMMED_NATIVE_VERIFY_PASS_COLD_BOOT_PENDING`。需要用户断电重启后观察白色参考物及 KEY3 的实际校正差异；没有用仿真或 Flash 校验代替板上白平衡验收，也未证明该算法缺口是原偏绿的唯一根因。
