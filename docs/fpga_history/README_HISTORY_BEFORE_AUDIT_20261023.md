# Historical README retained verbatim below; do not use as current instructions.

# HDMI 摄像头工程

2026-10-14：维护源码已加入 v19 固定摄像头红球→板内 MCU→双舵机联动。联合 FPGA 构建已通过，Slice 19336/21216（91.14%），ERAM 79，DSP 15；setup +0.117ns、hold +0.020ns。bit：`deliverables/camera_hdmi_v19_tracking.bit`，还必须加载 MCU ELF，不能只烧 bit 就运行 C 程序。追踪默认关闭，未自动烧录；操作和标定限制见 `../mcu_tracking/CAMERA_TRACKING.md`。原有 v18 交付 bit 保留作视频回退。

本版用 `tools/build_hdmi_v19.ps1` / `tools/test_tracking_v19.ps1`，不要用 v18 脚本把含 MCU 的新源码误标成 v18。

v18 A 方案资源优化基线：保留全部功能、分辨率、色值与识别阈值，改造 OSD ROM 和手势轮廓 RAM。回归、完整综合、布局布线和 bit 生成已通过；Slice 19096/21216（90.01%），ERAM 79/108，DSP 15/40；SWNS +0.103 ns、HWNS +0.020 ns。交付文件 `deliverables/camera_hdmi_v18_resource_a_20261013.bit`，未自动烧录。详见 `docs/RESOURCE_A_V18.md`。v17 文件和下方历史记录保留作回退基线。

当前 TD 项目：`prj/td_project/camera_to_dsi_display_hdmi.al`。
器件：PH1P35MDG324，摄像头 SC500，1280×720。
工作目录为 contest2_hdmi_video；当前设计不含网口功能。
不要再打开旧的 ethernet_preview 工程或烧录旧版 bit。

## 数码管

固定六位显示：左四位曝光半行计数，右两位模拟增益（倍数，四舍五入）。
第四位小数点仅作分隔符，例如 `1990.01` 表示曝光计数 1990、增益约 1×，不是 1990.01 毫秒。
曝光正常范围 2～1990；模拟增益 1～15.75×，显示 01～16。
只进行必要的电气位扫描，不进行内容轮换，不显示白平衡系数。
显示 AE 控制器发出的设置值，不是摄像头寄存器回读值。

KEY1 下一图像模式，KEY2 上一模式；KEY3 切换白平衡（默认开启）。
自动曝光保留，白平衡算法、摄像头采集、图像处理、检测和 HDMI 显示保留。

## 删除范围与恢复

已从当前源码/工程删除 PHY 配置、RGMII 发送、UDP 封包、网络 FIFO、抓图配置握手、
DDR 抓图冻结、网口引脚和时序约束、电脑接收程序及网络专用测试。
原网口文件、接收照片、旧 bit 和相关历史工具移动到工程外的：
`C:/Users/Chieh yu/Desktop/FPGA/anlogic/removed_ethernet_20261012`。
这是恢复备份，不属于当前工程；没有删除原 contest2 或官方参考例程。

## 构建和验证

v18：`pwsh -NoProfile -File tools/test_resource_v18.ps1` 和 `pwsh -NoProfile -File tools/build_hdmi_v18.ps1`；只核验已有输出用 `pwsh -NoProfile -File tools/build_hdmi_v18.ps1 -VerifyOnly`。资源对照用 `pwsh -NoProfile -File tools/report_resource_v18.ps1`。

`python tools/build.py setup`：同步维护源码与 TD 工程并检查配置。
`pwsh -File tools/test_hdmi_v17.ps1`：数码管、按键、自动曝光、帧槽和图像算法回归。
`pwsh -File tools/build_hdmi_v17.ps1`：从新 .al 完整综合、布局布线和 bit 生成（使用 PowerShell 7）。
`pwsh -File tools/build_hdmi_v17.ps1 -VerifyOnly`：复核已有完整构建，不重跑综合；仍验证原始源码哈希与输出时间。
脚本只交付通过新鲜度、源码一致性和实际 routed 时序检查的 bit，不自动烧录。
禁止从历史网口数据库恢复当前构建。

用户报告已自行烧录 v16；v17 的实际板卡显示仍需用新 bit 核验。
仿真、TD 构建及上板验证分别记录，不把仿真通过当作硬件效果保证。

## 本轮构建状态

2026-10-13，v17 回归、综合、布局布线和 bit 生成完成。
实际 routed 时序：SWNS 0.115 ns，HWNS 0.020 ns，无 setup/hold 违例。
最终 Slice 20268/21216（95.53%），LUT 19805，REG 18028，ERAM 74，DSP 15。
STA coverage 94.36%；时序报告通过不等于所有 CDC/I/O 或实际硬件均已验证。
交付文件：`deliverables/camera_hdmi_v17_fixed_ae_20261013.bit`。
SHA256：`C2E3E2B542A755A93FA56B368C6B9818FC912BFE2919376375DFC4F32C661350`。
最终核验记录：`tmp/v17_delivery_audit.json`。未自动烧录，板卡显示效果待实测。
此前两次退出已由用户确认是手动停止，不归因于工具崩溃。
