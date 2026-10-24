# v17：固定曝光数码管与移除网口

## 本轮行为

数码管不再轮换曝光/增益/白平衡页面。固定左四位显示曝光半行计数，
右两位显示模拟增益的整数倍数（四舍五入）；第四位小数点只是分隔。
例如 1990.01 表示曝光 1990、约 1 倍增益，不表示毫秒。
保留必要的六位电气扫描和换位消隐；数值在完整扫描边界一起更新。
增益最大 15.75 倍会显示 16；小幅增益变化可能被整数显示舍入。
显示控制器设置值，不等于传感器实际寄存器回读。

保留自动曝光、自动白平衡、KEY3 白平衡开关、KEY1/KEY2 图像模式、
拨动开关检测控制及原有 CSI/ISP/DDR/HDMI 链路。
没有调整图像算法参数，没有重新启用 v12/v13 的实验性 Bayer 修改。

## 结构删除

移除 ua_eth_video_bridge、ua_yt8511_config、ua_async_fifo_rgb24，
删除顶层 9 个网口引脚及对应 ADC/SDC，删除网络抓图配置握手、
DDR 抓图暂停端口和条件。删除电脑 UDP 接收程序和网络专用回归。
新工程文件名和项目名均为 camera_to_dsi_display_hdmi，
构建从维护的 .al 读取，不复用旧网口 .prj 或 gate/place 数据库。

网口源码、旧 bit、工具、照片、日志和旧运行目录已从活动工程移出，
恢复备份位于同级 removed_ethernet_20261012，原 contest2 与官方例程未改动。
本轮删除不涉及编程器自身的本地 TCP hwserver，也不更改 USB 驱动。

## 仿真证据

- 全部曝光值 0～1990、全部合法增益码 16～143、越界增益钳位、
  异步快速参数变动、握手数值一致性、六位扫描、分隔点均通过。
- 实际按键消抖模块：KEY3 一次按下只切换一次，KEY1/KEY2 保留，
  KEY4 保留原来的预留行为；AWB 8/9 位开关和运行期估计通过。
- 自动曝光启动写、稳定死区、上下界、闭环收敛、完整参数组保持通过；
  使用实际 SC500 初始化和 AE/Gain 表测试，I2C 总线响应为模型，
  不视为硬件 ACK/寄存器回读验证。
- video_in 连续 20 帧、四个帧槽轮换、读写槽关系通过。
  FIFO 是控制级替身，不是实际 DDR 数据完整性模型。
- 图像处理宽度 4/8/12/16/1280、有效信号间隙、9 位白平衡、
  LUT、饱和度、去噪和行/帧对齐回归，以及 19 项 Python 测试通过。

完整日志：tmp/v17_regression.log。
用户已报告自行烧录 v16；v17 没有自动烧录，需用新 bit 实测数码管和 HDMI。

## TD 证据

目标器件 PH1P35MDG324；TD 6.2.168116。
最终报告与 bit 生成结果完成后追加在下面，不能用布局阶段报告代替。

综合与布局已完成：布局 Slice 20449/21216，LUT 19799，REG 18015，ERAM 74，DSP 15。
这不是最终布线统计。当前布线进程已经退出，最后日志停在再布线阶段，
没有正常完成标记，也没有生成 v17 bit。退出原因未确认；不声称 routed 时序通过。
日志：prj/td_project/td_20261012_134220.log。后续需处理布线收敛并重新生成 bit。

2026-10-12 继续构建：不改 RTL、频率和时序例外，使用 TD 官方 DefaultFlow
的 deferred-hold 分支（arr_filter=on、arr_rwns=0、drHoldFix=on）。
先完成 setup 布线，再执行 fix_hold；最终仍检查全部 SWNS/HWNS 非负。
新版检查不再允许用 place 数据库替代 routed 数据库，并要求正常 bit-flow 完成标记。
独立隐藏构建进程记录 tmp/v17_build_console.log 和 tmp/v17_build_result.json；
RUNNING 不表示构建通过。此次不自动烧录。
用户随后确认上次为手动停止，不能将该次退出归因于 TD 崩溃。

2026-10-13 再次继续：确认 10 月 12 日的构建进程已停止，未生成 bit；
重新从维护源码启动完整构建（10:25:41），日志 td_20261013_102543.log。
数码管固定六位测试和 KEY3/AWB 回归重新通过。
本次布局 Slice 20268/21216（95.53%）、LUT 19805、REG 18028、ERAM 74。
当前正在详细布线，仍未取得最终 routed 时序结论，也未烧录。
构建程序完成后自动检查正常结束标记、实际 routed 数据库、报告/bit 新鲜度、
全部 setup/hold 裕量以及源码哈希；只有全部通过才复制到 deliverables。
tmp/v17_build_result.json 记录结果；RUNNING 还需结合对应进程是否存在判断，
手动强制停止可能来不及更新该文件。历史结果和控制台日志先备份到 tmp/previous_*。

## 最终交付（2026-10-13）

完整 TD 构建于 11:35:47 完成；最终报告 Confidence=Routed，
SWNS 0.115 ns、HWNS 0.020 ns、STNS/HTNS 均为 0，STA coverage 94.36%。
最终 Slice 20268/21216，LUT 19805，REG 18028，ERAM 74，DSP 15。
实际 routed 数据库再次导入检查：数码管请求同步器、ack 源网和保持数据网非空；
网口 bridge 单元和网口顶层端口均不存在。该结构检查不是完整 CDC/RDC 形式证明。
原构建输入 SHA256 全部一致，输出 bit/报告均晚于本次构建开始时间。
交付 bit：deliverables/camera_hdmi_v17_fixed_ae_20261013.bit（1789536 字节）。
SHA256：C2E3E2B542A755A93FA56B368C6B9818FC912BFE2919376375DFC4F32C661350。

交付脚本原先误把 Tcl puts 完成标记当成 TD 内部日志内容；
实际上它出现在 stdout/控制台记录，造成构建成功后被误报失败。
已修复完成标记来源，新增 -VerifyOnly 复核并通过所有交付检查，不重跑综合。
最终状态见 tmp/v17_delivery_audit.json；保留原控制台错误及 previous_validation_error 供追溯。
没有自动烧录。KEY3 白平衡开关、固定数码管以及 HDMI 实际效果仍需用户上板核验。

2026-10-13 12:23，用户要求 SRAM 烧录。交付 bit SHA256 核验一致。
未发现已有烧录服务，启动独立 5556 服务后，在 USB 初始化阶段报
ftdi_usb_reset failed，服务退出，尚未进入器件 ID 读取及 download。
本次没有成功烧录、没有写 Flash、没有修改 USB 驱动或终止用户程序。
日志：tmp/v17_hwserver.stdout.log、tmp/v17_hwserver.stderr.log。
需要用户重新插拔烧录 USB 并确保 BitWriter 关闭后再尝试。

12:44 重插后重试：独立服务未能建立 5556 监听，TD 等待 read_device_id，
未取得芯片 ID，也未执行 download。约一分钟无进展后停止本次明确创建的
hwserver（22096）和 TD 烧录进程（30884），未终止用户程序。
USB 枚举仍为 MI_00 STLink/WinUSB、MI_01 FTDI，设备状态 OK；
仅凭该枚举不能确定故障根因。没有修改驱动，没有写 Flash，没有成功 SRAM 下载。
日志：tmp/v17_hwserver_retry.*.log 和 tmp/v17_sram_program_retry.log。

