# ArUco FPGA＋MCU 实现记录

## 2026-10-16 已完成板上 MCU 启动与实时采集验证：FPGA v31＋MCU v33

时钟修正完成完整 TD 实现及实板复测。FPGA v31 最终 Slice 19274/21216（90.85%）、LUT6 18697、REG 16952、ERAM 105/108、DSP 15/40；Routed SWNS +0.133ns、HWNS +0.020ns、STNS/HTNS 0，STA coverage 94.56%。bit SHA256 `19EC7F47AC3C017E1D963ADFBD96873FD6FBAEF67F4F3B22FE24643A82B3BCC0`。完整源哈希、冻结时序/面积报告见 `tmp/v31_fpga_*`。

原生 BitWriter 下载正确识别双 TAP 中的 PH1P35MDG324，仍在最后一个状态位检查报 PRG-9507（line 29455519，read=0/ref=1）。**没有伪造原生成功标记**。随后按官方 PH1P35 `check_status_done.svf` 的只读指令（IDCODE 06、read_status 46、DONE mask 80000000）独立扫描，ID=`4808f0e7`、状态=`a9c0125d`、DONE=1。记录状态为 `FPGA_SRAM_PROGRAMMED_DONE_VERIFIED`，明确保留 `native_final_check_passed=false`；该末尾检查差异的具体机制尚未证明。复现检查为 `tools/verify_hdmi_v31_done.ps1`，不会重新配置 FPGA。

MCU v33 ELF（SHA256 `E1A074F28747C10CB1C958050EB17F885FC8ABF91B2B473FFD315577B4371BF7`）已通过终端写入 TCM，四个加载段 compare-sections 全部 matched。修正后 AHB 记录 `0xa8b88000000052a5`：请求被完成、未观察到 HRESP 错误；原先的第一次签名读取故障解除。COM15 返回 `ARUCO enabled=1`、`hw=257`，连续五次实时查询帧数 1290→1293→1296→1299→1302，errors=0、faults=0、armed=0、remaining=0，最大观察单步1453us。当前 id=255/valid=0，没有实际标记检出证据；尚未完成实拍标记框/ID、几何精度及相机标定验收。未写 Flash，未启动舵机。

离线验证含新增 MCU bypass 时钟合同测试（core50/raw25），旧接法负对照失败，新接法及完整扩展回归通过。实板实时证据为 `tmp/v31_aruco_live.log/json`，原生下载日志为 `tmp/v31_native_program.log`，独立 DONE 为 `tmp/v31_read_config_status.log`，MCU写入/段核对为 `tmp/v31_v33_diagnostic.log`。说明与操作见 `deliverables/README_ArUco_v31_board_ready.md`。以下条目为逐阶段历史记录。

## 2026-10-16 v31 时钟接法修正与板上诊断进展

用户再次确认供电后，只读 OpenOCD 扫描识别配置 TAP `0x4808f0e7` 和 RISC-V 核。BitWriter 默认单 TAP 扫描失败的原因已确认：当前链包含 MCU 与配置器件，`read_device_id -level 1 -total 2` 正确返回 PH1P35MDG324。后续原生 SRAM 命令增加 `-total_dev 2 -cur_dev 1 -bypass 5`；v30 下载末尾状态校验失败，不能生成正式成功回执，但板上 GPIO 扫描读到 v30 独有的 A8 记录，证明诊断配置已运行。Flash 未写入。

MCU v33 TCM 四段经 GDB `compare-sections` 全部 matched，运行后记录 `0xa8f8a650000052a5`：首次请求为 NONSEQ、32 位、HADDR=0；错误现场桥状态 DATA、`invalid=1`、APB 无错误。随后已仅恢复原 MCU OFF，串口确认 armed=0、remaining=0、faults=0。

核对 TD 6.2.168116 的官方 `ip/depot/RISCV_F6F1D1P0_1.0/MCU/RTL/MCU.v`，发现 DPLL bypass 分支明确将 Fabric `ahb_clk` 连接 `core_clk`，原语原始 ahb_clk 仅回接 fb_clk。生产封装原先直接用原始输出驱动 Fabric，现按官方分支修正，Fabric 逻辑由 sys_clk_50m 计时，移除错误的原始输出生成时钟约束。新增 core50/raw25 接口仿真通过；强制恢复旧接法的负对照签名读取失败；完整扩展回归通过。此时 v31 正在完整 TD 实现，修正是否解除实板总线错误仍待构建后复测。

## 2026-10-16 v30 AHB 错误现场诊断构建

为定位 v33 首次访问 `0x80000000` 时的硬 MCU Load access fault，在 AHB 外设增加 11 位只读诊断采样（桥状态、地址/尺寸拒绝标志、APB select/enable/ready/error、桥响应），并扩展 GPIO 扫描记录；不改变 PWM 控制或视频通路。Icarus 扩展回归通过：AHB/peripheral、512 笔压力事务和 8 次复位、总线追踪解析、61 个图像/位姿场景及 18 帧 RTL/C 联合仿真。

TD 对 PH1P35MDG324 完成 Routed 和 bitgen；独立复核 231 项输入哈希无差异，四项时序均非负：SWNS +0.176ns、HWNS +0.020ns、STNS 0、HTNS 0。诊断 bit SHA256 `2222E26DD26FF467643A86D3FCA963CE40A77F4C195CE488AA69DEE29175141E`，文件为 `deliverables/camera_hdmi_v30_ahb_diag.bit`。

本轮尚未成功加载板卡：官方 BitWriter CLI 能连接 `hwserver`，但 `read_device_id` 返回空值，因此未执行下载、未写 Flash，也未生成 SRAM 成功回执。此结果不是烧录成功。当前已停止本任务启动的 `hwserver`；等待确认开发板外部供电和 AL-LINK/JTAG 线后再只读核验目标 ID。v30 诊断 bit 尚未上板，尚不能得出 AHB 实板错误分类或宣布 ArUco 已工作。日志：`tmp/v30_native_program.log`、`tmp/v30_build_result.json`。

## 2026-10-16 v33 MCU 终端部署复核

用户确认已手动加载 v29 FPGA。终端通过 OpenOCD/GDB 将 v33 ELF（SHA256 `E1A074F28747C10CB1C958050EB17F885FC8ABF91B2B473FFD315577B4371BF7`）写入 MCU TCM，未写 Flash；但 MCU 在第一次读取 ArUco 签名地址 `0x80000000` 时进入 Load access fault（`mcause=0x38000005`、`mtval=0x80000000`、`mepc=0x080041d0`）。v29 的 GPIO 总线诊断记录为 AHB NONSEQ、32-bit、读、`HADDR=0`，并观察到非零 HRESP 与完成；地址/宽度检查本身未拒绝该请求。说明 ELF/TCM 下载已完成，但 FPGA↔MCU AHB 实板访问仍失败，不能称 MCU ArUco 已运行或 HDMI 框/ID已就绪。

为避免 MCU 留在异常处理状态，已用终端恢复原控制 OFF ELF（SHA256 `B95336606F93CE3C953D24491DF075E95F8CC3EE910B69BD901F8B29983799E9`）；COM15 状态确认 `armed=0`、`remaining=0`、`faults=0`。调试服务已退出，舵机保持关闭。v33 下载日志、总线扫描脚本分别为 `tmp/v33_mcu_gdb.log`、`tmp/v33_read_bus_trace.gdb`。继续实现需先定位/修复 FPGA AHB 响应并构建匹配 bit，再重新加载对应 MCU ELF；本轮未改 RTL、未重配 FPGA。

## 最新阶段：v31边界角点测距与状态清理（2026-10-16）

修正“原始RMS近零就跳过边界候选”的问题；同一180mm样例187.5→181.28mm，暗噪声约181.44mm。106组配对中ID/原始角点/检测步数不变，104个共同有效位姿平均位置误差6.13→4.08mm，最大误差22.82mm未改善。撤走、过期和快照失败现在分别清零旧位姿并给出明确状态。目标ELF占用36000/49152 B（73.24%），比v30增加128 B。旧回归及50/25MHz共14场景实时C/RTL联合仿真通过，详见 `deliverables/aruco_corner_improvement/README.md`。**未改FPGA RTL/bit，未访问板卡或烧录；真实标定、硬核总线问题及MCU时序仍待实板验证。**

## 最新阶段：v30 FPGA↔MCU C实时总线联合仿真（2026-10-16）

新增Icarus/VPI实时耦合：生产MCU runtime/capture逐笔发起AHB事务，实际RTL完成RGB转灰、冻结快照、CDC与MMIO响应，再由同一份C识别/位姿代码消费返回值。50MHz 10场景、25MHz 4场景通过；419436次像素读取逐次核验，其中227948次在干扰帧到来期间，4个跨频率对应场景有效结果一致。生成示范图和10秒回放，详见 `deliverables/aruco_live_cosim/README.md`。发现/确认粗角点的距离偏差：合成180mm正面目标约187.5mm，低重投影误差不代表真实距离无偏。**这是主机C事务级联合仿真，不是硬MCU指令级仿真或实板验收；未访问板卡、未烧录、未启动舵机。生产RTL/MCU源码及v30 ELF哈希保持不变，TCM仍35872字节。**

## 最新阶段：v30 MCU 存储瘦身（2026-10-16）

保留全部识别、位姿及已有控制功能，替换重复的通用日志依赖并按生命周期复用直方图/FIFO。目标TCM从48088 B（97.84%）降至35872 B（72.98%），节省12216 B；仍保留2KiB栈、1KiB堆、1024项队列和原位姿迭代精度。251个v29/v30相同输入的C识别/位姿输出逐字节一致，完整旧回归通过。详见 `deliverables/README_ArUco_v30_MCU_optimization.md`。**本轮不烧录、不访问板卡；存储余量不代表已测CPU实时余量，旧实板总线故障仍待复验。FPGA RTL不变。** 以下为历史记录。

## 最新阶段：v29 MCU 位姿离线实现（2026-10-16）

已增加标定门控的平面位姿、旋转矩阵/四元数、边界直线精化及原始角点回退；目标 MCU 编译通过，text+data+bss=48088/49152 字节（含保留栈/堆）。240 个投影、12 个异常输入、6 个图像到位姿场景，以及新增2帧全720 RTL→C位姿比对与旧回归已纳入验证。完整说明与图片在 `deliverables/aruco_pose_simulation/README.md`。**按用户要求未访问开发板；缺真实标定时固件默认不输出距离，旧硬核总线故障仍待实板验证。FPGA RTL 未改动，沿用 v28 Routed 结果。** 后文是历史记录。

## 最新阶段：v28 离线验证（2026-10-16）

v28 诊断版已修正 GPIO7 返回位保持时间，并完成 Routed 签核（SWNS +0.105ns、HWNS +0.020ns、STNS/HTNS 0）。新增 61 场景效果图、18 帧全720p快照/AHB/C联通、50/25MHz总线压力和一键扩展回归；全部通过。详见 `aruco_bus_debug_v28_20261015.md` 与 `deliverables/aruco_simulation/README.md`。**按用户要求，本轮仅做离线验证，v28 未烧录；之前 v27 硬 MCU 总线异常尚未在新版本实板复测，不能宣称实板 ArUco 已通过。** 以下 v27 章节保留为历史证据。

## 当前交付状态：v27，2026-10-15

**22:57 实板状态更新：FPGA SRAM 已成功加载，用户确认 HDMI 摄像头画面正常；配套 ArUco MCU 未通过总线启动验收，已仅恢复原 MCU OFF 固件。下文“未烧录”是 22:39 离线交付复核时的记录，不代表当前板上 FPGA 版本。ArUco 实板功能仍未通过。**

### 本轮实板故障与安全恢复

- 原生 `tmp/v27_native_program_replug.log` 核验器件 PH1P35MDG324，下载成功，bit 哈希保持不变；未写 Flash。
- `tmp/v27_mcu_gdb.log` 证明 MCU TCM load 执行完成，但串口 OFF/ArUco 身份确认失败，不能将 GDB 返回码当作应用成功。
- 独立调试暂停于 SDK 异常处理循环，`mcause=0x38000005`、`mtval=0x80000000`、`mepc=0x0800047a`；新增暴露 CSR 的调试记录 `mdcause=2`，为总线错误，不是 PMP 权限错误。参考芯来官方 CSR 文档：https://doc.nucleisys.com/nuclei_spec/isa/core_csr.html 。
- SDK `fpsoc/chip/ph1p35/src/al_chip.S` 启动代码向 `0x18000104` 写入 AHB_DIV-1；现平台配置 AHB_DIV=2，而本工程硬件设计/时序按 50MHz。调试器在启动访问前临时改为 DIV=1 仍未恢复串口，故不能把该配置差异认作唯一根因，也未据此修改生产 RTL 或重新构建。
- `tmp/v27_mcu_safe_recovery.log` 证明仅恢复原已校验 MCU ELF（SHA256 `B95336606F93CE3C953D24491DF075E95F8CC3EE910B69BD901F8B29983799E9`），重新启动后 `armed=0 remaining=0 faults=0`。未再次配置 FPGA、未启动舵机。当前持久记录为 `tmp/v27_native_deployment.json`。
- 后续应先做真实硬 MCU 的最小只读签名访问验证，核对导出 AHB 时钟、地址、尺寸与响应时序；在该测试通过之前不继续评价 ArUco 图像准确率。需补硬核接口级测试，现有纯 Fabric 仿真未覆盖此板上故障。

已接入生产顶层，完成整工程 TD 综合、布局布线与 bitgen；MCU 独立应用也已链接完成。**以下第一阶段内容是历史记录，不代表当前仍未接入。v27 尚未烧录或实板验收；本轮没有写 Flash、没有启动舵机。**

当前链路为：增强后、显示特效前的 RGB → FPGA 160×90 冻结灰度快照 → 板内 MCU AHB → 分步 ArUco 单目标 ID/四角识别 → UART 状态输出。现有视频主通路、检测功能及控制协议保留。不是完整位姿版本：尚无标定后的 6DoF、距离或 HDMI ArUco 叠加。

### 最终资源和时序

目标 `design_top_user / PH1P35MDG324 / speed 3`，TD 6.2.168116，最终报告时间 2026-10-15 21:02:15。

| 项目 | v27 最终结果 | 相比 v26 |
|---|---:|---:|
| Slice | 19186 / 21216，90.43% | +240 |
| LUT6 / REG | 18717 / 16846 | 以最终 area 报告为准 |
| ERAM | 105 / 108，97.22% | +7，仅余 3 |
| DSP | 15 / 40 | 不变 |
| Routed setup / hold | SWNS +0.115ns / HWNS +0.020ns | 非负 |
| 总负裕量 | STNS 0 / HTNS 0 | 无已分析路径违例 |

最终 Routing DRC 记录 `No multi-drive`、`No abnormal timing path`、`Bound Check: Check Pass`。STA coverage 为 94.52%，不能宣称全部外部接口均已完整约束；PLL IO 与时钟网络分析警告仍保留在报告中，不能称零警告。

独立复核 `tmp/v27_source_hashes.json` 的 231 项与 `tmp/v27_mcu_source_hashes.json` 的 15 项，均与当前输入一致。最终报告为 `prj/td_project/camera_to_dsi_display_hdmi_pr.timing` 和 `camera_to_dsi_display_hdmi_phy.area`，成功标记为 `tmp/v27_td_stdout.log` 的 `HDMI_V27_BIT_FLOW_COMPLETE`。

### 已解决的 MCU 总线时序问题

初次结果漏计 MCU Fabric 时钟，已明确拒绝该产物并保留为 `NOT_FOR_PROGRAMMING` 历史文件。SDC 增加真实的 50MHz `MCU_FABRIC_CLK` 后暴露返回总线保持违例；未放宽频率，也未通过屏蔽该同步路径掩盖问题。

最终将外设返回的 `hrdata/hresp/hready` 一起在总线下降沿寄存，使 MCU 上升沿采样前后有半周期稳定窗口。桥和 APB 状态仍在上升沿推进；协议仿真覆盖等待、错误、恢复及完整快照读取。最终正常全流程构建已通过 setup/hold。

### MCU 固件与安全边界

单独应用 `../mcu_tracking/aruco_firmware/` 使用原控制主循环，ArUco 分步任务与外设服务共存。CPU MMIO 基址为官方 SDK 的 `0x80000000`；没有把图像复制进 MCU TCM。独立硬件 PWM 接管后默认 OFF，识别结果不会自动开启舵机。

链接结果 text=30644、data=304、bss=9340，总计 40288 字节；显式栈预留 2048 字节已计入链接占用，48KiB 账面余量 8864 字节。尚未测实板栈峰值、识别吞吐与最坏步执行时间；不能将分步预算当作严格实时性证明。

### 交付文件与 SHA256

- `deliverables/camera_hdmi_v27_aruco_capture.bit`：`D6047EFAB52F44EEEA269C1C108D0DAA563CBB2731B44C5139F2CD915BE3866F`
- `deliverables/mcu_aruco_v27.elf`：`259D01F8E1C4F4EE159E4305201C9B8253A27BC5CD36F21D937751E3DB98B636`

两个文件必须配套使用；bit 不包含自动运行此 MCU 应用的部署步骤。详见 `deliverables/README_ArUco_v27.md`。已保留 v26 文件与接入前源码副本，未执行 Git 提交。

只读核验命令为 `tools/verify_v27_delivery.ps1`，不构建、不下载、不复位、不访问串口；成功 JSON 保存为 `tmp/v27_delivery_audit.json`。查阅官方 MCU/Tcl PDF 时生成的两个临时 Markdown 已清理，原始 PDF 保留。

### 回归与仍需完成的工作

`tools/test_aruco.ps1` 重新验证实际嵌入式 C 和 RTL：50 ID×4 方向、3200 个单比特解码测试、270 个合成图像用例、14400 像素整帧对照、RTL→C ID23 联通、CDC 快照协议、AHB 数据相位/错误恢复，以及 1MHz/50MHz 安全 PWM。最终日志为 `tmp/aruco/regression_final.log`。原视频回归本轮也重新运行通过，含 30 项 Python 测试，最终记录为 `tmp/aruco/video_regression_final.log`。2026-10-15 22:39 的独立交付核验通过，见 `tmp/v27_delivery_audit.json`。合成测试不代表实板准确率或 CDC 亚稳态签核。

下一步先在舵机 OFF 状态部署配套 FPGA SRAM＋MCU TCM，打印 ID23 验证实际暗光、旋转、透视、撤走目标、原视频与其他检测功能。记录 `step_max_us`、错误计数和栈峰值后，再做时域确认、角点细化和标定后的平面位姿计算。相机内参、畸变和黑色标记实际边长未取得前，不交付可信米制位姿。

## 第一阶段记录（接入前）

### v27 实板加载尝试补记

2026-10-15 22:43，重新核验交付通过；COM15 已响应停止命令，`armed=0 remaining=0 faults=0`。官方原生流程未能读取器件 ID，尚未执行 download；线缆初始化进一步报告 `usb_open() failed`。因此未加载 v27 FPGA/MCU、未写 Flash、未开启舵机，也未修改 USB 驱动。阻断记录为 `tmp/v27_native_attempt.json`。需用户关闭 BitWriter、重新插拔烧录 USB 后再检查连接，不将此失败记为成功部署。

本轮完成第一阶段的独立模块、C 图像识别与联通仿真。**尚未接入生产顶层、尚未生成新的整工程 bit、尚未部署 ArUco、尚未实现完整位姿估计或 HDMI ArUco OSD。** 板上仍是已烧录的 v26；没有下载 MCU 新程序，没有启动舵机。现有生产 RTL、工程 manifest、引脚约束与已校验交付 ELF 均未修改。

最终目标：FPGA 流式图像前端和确定时序；MCU 做少量候选解码、位姿与控制；FPGA PWM 防止软件运算阻塞舵机时序。本阶段先用 MCU 做低分辨率候选定位来验证完整识别流程，再按实测耗时决定哪些候选操作迁到 FPGA，不能声称 FPGA 候选定位已经完成。

## 已实现

### FPGA 灰度快照：rtl/user/aruco/ua_aruco_snapshot.v

- 输入为每拍四个 RGB888 像素的旁路流；要求 tuser/sof 与首个有效拍同时，tlast/eol 为每行最后有效拍。拟接 ISP 的增强后、显示特效前支路，不改摄像头与 DDR 主通路。
- 1280×720 每八个像素、每八行取一个像素，输出 160×90、8 位灰度。灰度为 `(R+2G+B)>>2`。本阶段为点采样，不是抗混叠面积平均，也不是传感器 RAW。
- 单缓冲 14400 字节。MCU 请求后从下一个完整帧开始，采完冻结；未释放前不会被下一帧或重复请求覆盖。使用请求/完成 toggle、三级完成同步和稳定多位状态；RAM 仅在发布前写，MCU 仅在 ready 后读。
- 错误行宽不发布有效图；源时钟停止时由 MCU 超时退出，不阻塞控制主循环。源/总线 reset 必须共同断言，不支持事务中独立重置一端。
- APB 读遵循 setup/access，RAM 同步读一个时钟；非法地址、未就绪读内存、非法写返回错误。

相对寄存器布局（CPU 绝对映射接入前仍需复核）：

| 字节偏移 | 含义 |
|---|---|
| 0x00 | 签名 0x41525531，ARU1 |
| 0x04 | bit0 busy、bit1 ready、bit2 frame error |
| 0x08 | 写 1 请求；写 2 释放，分开两次事务 |
| 0x0C | 成功/失败采集完成序号 |
| 0x10 | 高 16 位高度、低 16 位宽度 |
| 0x1000＋4×n | 第 n 个灰度像素，32 位对齐字读取，仅低 8 位有效 |

### 总线桥：rtl/user/aruco/ua_aruco_ahb_bridge.v

- 同一个总线时钟内 AHB-Lite 转 APB，支持逐笔串行传输和完成时接收下一地址；区分地址与写数据相位。
- 只支持 32 位对齐 MMIO，其他尺寸、非对齐及窗外访问先拒绝，避免写副作用。
- 支持 APB 等待与两周期 AHB ERROR 响应。未连接硬 MCU，尚未验证硬核导出接口上的实测行为。
- 官方 FD SDK `solutions/demo/baremetal/ahb_demo_n/ahb_demo.c` 使用 CPU AHB 基址 `0x80000000`；PH1P 导出的地址端口为 31 位。本轮记录此证据，不使用其他芯片的总线地址作替代。

### 安全 PWM：rtl/user/aruco/ua_servo_pwm_safe.v

- 默认 OFF；独立 arm 和 update；两路脉宽默认限定 1300～1700us（沿用当前机械安全范围，不扩大行程）。
- 20ms 周期边界更新脉宽，不在脉冲中途应用新宽度。独立微秒时基，不使用乘法器。
- 150ms 无刷新自动撤销输出；arm 拉低立即撤销；复位不输出脉冲。
- 尚未替换生产 GPIO PWM，现有云台行为不变。

### MCU：../mcu_tracking/aruco_app/

- `aruco_detect.c/h`：固定工作区、无 malloc、无递归；分步全图 Otsu、二值图、4 连通黑区域、16 方向极值凸包、四角近似、真正透视映射、每单元 3×3 多数投票与字典校验。支持 `DICT_4X4_50`，首个有效目标，按 ID 旋转恢复规范角点顺序。
- `aruco_decode.c/h`：保留已有 4 方向字典解码与歧义拒绝。图像识别初版采用零位错误严格匹配；单比特纠错仅独立单元测试，不在未实现时域确认前启用。
- `aruco_capture.c/h`：签名、尺寸核验；请求、轮询、分步识别、核验帧序号、释放；超时采用可处理毫秒计数回绕的比较。总线读写是回调，不硬编码未经实板核验的地址。
- 输入快照必须保持不变。主循环每次调用 step(budget)，然后返回外设服务；不从 PWM ISR 调用。budget 限制像素/节点数，但候选校验额外至多 324 次像素读和有限字典比较，因此不是严格微秒级 WCET 保证。
- FIFO 队列溢出整帧拒绝，不能把被截断的组件继续当合法标记。候选数量受限，不输出过期或半帧结果。
- Detector 主机工作区 4656 字节；带采集客户端主机工作区 4736 字节。32 位 MCU 的实际布局以链接结果为准，不能直接套 64 位主机 sizeof。

## 验证与资源

运行：`tools/test_aruco.ps1`，日志 `tmp/aruco/regression.log`。

- 字典：50 ID×4 方向、3200 个单比特错误测试、边框错误及无效输入拒绝。
- 图像：OpenCV 4.10 独立生成标记，实际被测是同一份嵌入式 C，而非调用 OpenCV 检测器；覆盖方向、任意角度、部分透视、暗灰/颗粒、无标记噪声、裁切与小目标。合成测试不代表真实摄像头准确率。
- 720p 仿真输入经 RTL 快照后，14400 个像素与参考逐点一致，C 客户端识别测试 ID 23；该联通测试是文件联通模型，不是板上 AHB、CDC 亚稳态或实测帧率证明。
- 快照协议：非同频源/总线时钟、冻结、重复请求、释放重采、错误行宽、复位。
- AHB 桥：写数据相位、等待、对齐拒绝、APB 错误转两周期 ERROR、恢复。
- PWM：1MHz 和 50MHz 配置下检查实际输出周期内高电平计数、限幅、超时、重新接收命令、撤销与复位；不驱动实物。

独立 TD Optimize-Gate（不是整工程布局或 Routed）：

| 模块 | Slice 门级估算 | ERAM | DSP |
|---|---:|---:|---:|
| 160×90×8 快照＋APB | 171 | 7 | 0 |
| 双路安全 PWM，微秒计数版 | 102 | 0 | 0 |

快照日志 `tmp/aruco/snapshot_synth.log`，PWM 日志 `tmp/aruco/servo_synth.log`。微模块顶层无外部引脚约束的警告是独立测量环境，不用于可烧录 bit。快照还有 TD 通用未驱动引脚默认置零警告，接入前需要进一步检查门级 RAM 端口/输出语义，不能把门级成功等同于 RAM 硬件签核。

v26 已有 98 ERAM，直接相加将到 105/108，余量仅 3。没有把上述 Slice 简单相加当成最终占用；总线桥、寄存器、结果显示及布线还需单独计入。必要时改用候选小窗复用或减少独立快照缓存，但不能未经验证降低识别质量。

`../mcu_tracking/build_aruco_probe.ps1` 将完整现有控制固件、采集客户端和识别代码链接进单独的 TCM 容量探针工程，产物名显式包含 `NOT_FOR_DEPLOYMENT`；未替换当前校验 ELF。实测 text=29800、data=304、bss=8236，总计 38340 字节；48KiB 账面余量 10812 字节，尚需栈峰值、库调用、中断嵌套和位姿模块一起评估。`-fstack-usage` 记录最大候选函数局部栈 560 字节，不能据此宣称整个程序只需 560 字节栈。

## 下一阶段顺序

1. 完成 AHB 桥＋快照的组合仿真与 RAM 门级语义检查；保留 v26 回退包。
2. 将前特效 RGB 支路接到快照，连接 MCU AHB 和硬件 PWM 寄存器；验证总线地址、时钟、复位，保持引脚不变。
3. 合入 MCU 非阻塞任务，保留云台/外设服务，测每步耗时、快照年龄、队列上限和栈峰值。先只输出 ID/四角/错误码，舵机仍 OFF。
4. 整工程综合/布局/时序/bitgen，通过后才交付候选烧录版本；实板打印标记验证暗光、移动、倾斜、无目标误检。
5. 加时域确认、角点细化，再加入标定参数与位姿初值/重投影检验。位姿目前未实现；没有内参、畸变、真实标记边长时不输出可信米制距离。
6. 相机固定的安装方式采用标定后的指向映射，不套用随动相机居中 PID。云台动作必须另行明确授权。

原理参考：OpenCV 官方 ArUco 检测教程（候选四边形、透视采样与字典识别）及 solvePnP 文档。实现是本项目的受限嵌入式 C，不宣称等同于完整 OpenCV 的鲁棒性。

- https://docs.opencv.org/4.13.0/d5/dae/tutorial_aruco_detection.html
- https://docs.opencv.org/4.13.0/d5/d1f/calib3d_solvePnP.html
