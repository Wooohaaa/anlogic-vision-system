# v56：自动曝光/暗部补偿恢复与固定 index 显示

## 行为

- KEY4 每按一次切换整个自动亮度控制，默认开启。KEY3 白平衡及其他功能保留。
- 关闭不再冻结之前的高增益：等待当前 I2C 写事务安全完成，再恢复曝光 1990 半行单位、模拟增益输入 16（表中的 1×）。这不代表关闭传感器曝光，固定曝光仍存在。再次开启后继续帧亮度闭环。
- 数码管左两位固定显示 `00..31` 的综合控制 index，最右一位固定显示使能 `0/1`，中间三位空白，不轮换。
- index 不是物理倍数。00..14 表示曝光时间区间；15 表示最大曝光、1× 模拟增益基准；16..31 表示最大曝光下逐级提高模拟增益。关闭后回到基准，显示 `15   0`，而非虚假的零曝光。暗场上限显示 `31   1`。
- 暗部曲线随同一个 index 控制：开启且 index≥20 为中等、≥24 为强；关闭时为原基础色调曲线。现有降噪、基础颜色/对比度曲线不会被关闭。

## 确认问题与实现

此前 KEY4 只暂停 AE/AG 计算，并没有恢复基准；数码管显示曝光码/四舍五入增益，不能代表完整的自适应状态。photo 模块的生产色调 ROM 初始化始终调用 `tone(...,0)`，忽略输入强度，因此强度改变不会改变 ROM 输出。

新增 `RESTORE_ON_DISABLE=1` 仅用于产品实例，保持旧自动曝光单元的默认兼容行为。`O_gain_index` 同时驱动数码管和暗部曲线选择。24MHz→CSI 使用请求/应答保持的六位 enable+index 邮箱，CSI 在帧首锁存强度，禁止半帧切换。100MHz 数码管同样用一致性快照，每个完整扫描周期提交一次。

运行时曲线使用现有六组双读 ROM，每组深度从 512 增为 2048（包含四个强度地址区，2/3 区相同）。纯查表、不增加逐像素乘法器或视频流水拍数。增强量为 `min(base,255-base)/4` 或 `/2`，端点和单调性已穷举；不能恢复传感器已经裁切的细节。

## 验证

- `python tools/test_brightness_v56.py`：暗/亮收敛、关闭恢复、再次开启、KEY4 边沿保持、全部 32 index×2 enable、位选/段码映射、三条曲线全部 512 输入、真实输出数据与拍数通过。`tmp/v56_regression/result.json`。
- `tools/test_auto3a.ps1`：1024 样本完整 1280×720 黑/白/颜色/气泡统计、闭环、实际 SC500 初始化与五寄存器 AE 表状态机通过；底层 I2C 是接受模型，不是实板 ACK/寄存器回读证据。`tmp/v56_auto3a_full.log`。
- `tools/test_photo_wide.ps1`：8/9 位差值等价、宽度 4/8/12/16/1280、基础色调开关/气泡、ROM、AWB→photo 首尾对齐、AWB 算术等 RTL 部分通过。末尾全目录 Python discover 未全通过：两个 CLI 型手势脚本在 import 时要求参数，一个旧 Logo 测试错误地要求 Logo 源文件包含字体路径。`tmp/v56_photo_wide.log`。不把这次整个脚本称为全通过。
- 整机新综合/布局：19401/21216 Slice（91.45%），97/108 ERAM，25/40 DSP；比 v53 的 19494 Slice 少 93。`tmp/v56_area_result.json`。
- 布线使用冻结的源及数据库，不修改正在运行的输入。初始布局报告发现旧 SDC 的 panel `req_meta_reg` 名称不匹配，因此增加 `camera_hdmi_v56.sdc`，改为唯一请求源 net 加发起/接收时钟的定向例外；不放宽整对时钟。必须经 `tools/verify_v56_constraints.tcl` 重新导入 Routed DB 核验，才算最终签核。

## 部署边界

本轮没有烧录。板上仍是此前 v55 联合 Flash。v56 不修改 ArUco MCU，FPGA 启动向量继续指向原 Flash bootloader 和 v55 MCU 负载；不能把只含 FPGA 的 bit 当作完整 Flash 镜像覆盖旧负载。布线/时序/打包状态以各自 receipt 为准，真实画面效果仍待上板对照。

## 最终结果

布线、hold 修复、bitgen 已完成。再由相同 Routed DB 独立加载 `camera_hdmi_v56.sdc` 检查：无未匹配对象或失败例外，最终 Confidence=Routed，SWNS +0.150 ns、HWNS +0.020 ns，STNS/HTNS 均为零。资源仍为 19401 Slice、97 ERAM、25 DSP。修正版约束仅更正该 mailbox 的定向请求路径，不修改物理网络或位流字节；新构建应使用此版约束，而非照抄旧 panel 寄存器查询。

已生成 `deliverables/camera_hdmi_v56_fpga_mcu_flash.bit`，SHA256 `32BE5FBDD25E0F13FE9BEE6C7152C0BC639ACCF4C2CDB1C1FDB94F7B8F9194B1`，包含新 FPGA 配置、原 bootloader、原 v55 MCU 有效载荷。逐字节核验三个内容区及 MCU CRC，`tmp/v56_flash_build_result.json` 状态 `FLASH_IMAGE_VERIFIED_NOT_PROGRAMMED`。本轮没有烧录或启用舵机，不能宣称板上亮度问题已经验收。

## 用户随后授权烧录

2026-10-19 21:55（北京时间），用户明确要求“烧录”后，通过 `tools/program_v56_flash.ps1` 官方 BitWriter CLI 完成一次联合 Flash 写入和校验，目标 PH1P35MDG324。写入前后核验 v56 镜像/源文件/回归输入及原 v55 MCU 哈希，Routed SWNS/HWNS 非负、STNS/HTNS 为零。日志 `tmp/v56_flash_program.log`，成功记录 `tmp/v56_flash_programmed.json`。不重复烧录、不启用舵机，保留原 v55 MCU。真正断电启动和亮度画面效果仍待用户验收；烧录后仅查询串口，记录 `tmp/v56_post_flash_uart.log`。

两次串口均有应用响应，armed=0、remaining=0、faults=0。ArUco status=-7 是 `UA_POSE_DISABLED`，当前 frames=0，不把它描述为正在识别；没有自动改变用户检测开关。第二次状态见 `tmp/v56_post_flash_uart_second.log`。
