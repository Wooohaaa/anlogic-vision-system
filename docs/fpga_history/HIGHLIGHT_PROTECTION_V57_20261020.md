# v57 高光优先自动曝光（未部署）

## 用户问题及录像证据

用户明确说明 index 快速上升不是问题，暗画面增益有效；本轮解决的是暗背景与局部亮物体共存时，亮处过曝。

输入：`C:/Users/Chieh yu/Videos/2026-10-19 22-49-30.mp4`（842 帧）、`22-51-23.mp4`（1313 帧），均为 1280×720、60 fps 的 HDMI 采集。

`host/audit_highlights_v57.py` 抽取每段 16 帧并排除固定 Logo/部分文字区域。第二段 7.28 秒和 21.85 秒，显示域任一通道≥240 的像素约 24.6%、38.1%，三通道均≥235 约 18.4%、34.2%。接触图可见键盘、纸面逐渐失去细节。结果见 `tmp/v57_highlight/video_audit.json`。这些是压缩 HDMI 亮度指标，不是 RAW 饱和比例，不能逆推出传感器曝光或恢复被裁切的纹理。

## 思路与实现

参考 libcamera AGC 的两阶段原则：平均亮度给出期望曝光，再由直方图上分位区间的亮度约束限制它。官方依据：

- https://docs.libcamera.org/master/internal-api/classlibcamera_1_1ipa_1_1AgcMeanLuminance.html
- https://github.com/raspberrypi/libcamera/blob/main/src/ipa/rpi/controller/rpi/agc_channel.cpp

本实现是适配 FPGA 余量的近似，不声称完整移植 libcamera：

1. 保留 AWB/显示算法之前的中央 1024 点平均亮度。
2. 新增分散全画面的 32×32 网格，累计 max(R,G,B)≥192/224/240 的样本数，各计数器饱和到 31。RGB 最大通道可约束单色通道饱和，避免平均 Y 掩盖纯红/绿/蓝过亮。
3. 240 档≥8/1024 → 强保护；224 档≥8/1024 → 降曝光；192 档≥16/1024 或 224 档≥4/1024 → 保持、不允许暗均值继续增加曝光。单个极亮点不单独触发全局退曝光。网格可能漏掉小于采样间距的光点，不保证每个极小灯珠都被保护。
4. 高光退曝光优先于暗场增益。仍先降模拟增益，再降积分时间，沿用 I2C 整笔参数保持、完成后等待与确认帧机制；不只是限制 index 最大值或放慢反应。关闭 KEY4 恢复基准的行为保留。
5. 产品原始线性亮度目标由 96..144 改为 48..72，避免把线性域当作显示 Gamma 域追到过高目标。这是当前工程的初始调参，不是对 SC500 的通用标定值。
6. 数字补偿改为阴影提升：基础输出 0..96 上升，96..192 平滑减小，≥192 与基础曲线逐码相同。保持黑端、单调性、RGB 视频流水拍数及全部功能。

同时在维护主 SDC 中修正 compact panel 的定向 request 例外，使用源网络而不是旧寄存器名；与 v56 最终独立签核时的有效约束语义一致，不放宽整个时钟对。

## 仿真证据和边界

`python tools/test_highlight_v57.py`，结果 `tmp/v57_regression/result.json`：

- 1280×720 流中中央纯黑、左侧高光：中央均值保持 0，全局 1024 点触发高光保护。
- 单个高光点忽略、8 个红通道热样本、16 个绿通道预警样本、全白计数饱和与上帧一致性发布通过。
- 同一个合成传感器模型、中央暗背景与亮块共存：旧控制器模拟增益码到 143、亮块未裁切数学值 1417（真实 8 位将裁为255）；新控制器增益码稳定52、亮块202。**这不是实板拍摄前后对比。**
- 已经处于最大增益并出现高光时，即使均值为1，也能减少增益/曝光；预警期间禁止再次增加。
- 1536 个阴影 LUT 项单调、亮值≥192 不变，三帧真实像素输出一致。
- 原 KEY4/显示/关闭恢复、原 AE 闭环、完整帧统计、SC500 AE 配置状态机回归通过。底层 I2C 为接受模型，不是实际 ACK 或寄存器回读。

未修改 ArUco MCU、手势算法、其他检测功能；板上仍是 v56，未烧录本修复。高动态范围超过单曝光传感器能力时，保护亮处会使暗背景更暗，这是物理取舍，不能承诺暗部与强光同时无损。数字阴影提升只能利用尚存的信号，不能生成丢失细节。

## 构建记录

综合/布局：`tools/check_area_hdmi_v57.ps1`，冻结输入 `tmp/v57_area_source_hashes.json`。资源必须通过 ≤19518 Slice（92%）、≤108 ERAM、≤40 DSP 门限后才进入布线。

布线/时序：`tools/build_hdmi_v57.ps1`，结果以 `tmp/v57_build_result.json` 为准。本记录不把 RUNNING 或布局通过等同于最终可烧录。

## 最终构建完成（未烧录）

2026-10-20 完成整机新综合、布局、布线、hold 修复与 bitgen：19321/21216 Slice（91.07%）、97/108 ERAM、25/40 DSP；Confidence=Routed，SWNS +0.120 ns、HWNS +0.020 ns，STNS/HTNS 均为零。最终 route 日志无 ERROR、CRITICAL-WARNING 或未匹配的时序对象。早期 read_design 阶段的 MCU 首级寄存器查询警告未被作为签核证据；导入物理数据库后该定向例外正常匹配，最终约束检查通过。

`python tools/build_v57_flash_artifact.py` 已逐项核验冻结输入、回归哈希、最终时序、整个 FPGA 配置字节及原 bootloader/v55 MCU 负载和 CRC，生成 `deliverables/camera_hdmi_v57_fpga_mcu_flash.bit`。

SHA256：`E67FAA9B1A836C1B2E8F05A91FEA4DC8AF739CA1423755D12180D3A4B2230B2B`。

结果 `tmp/v57_flash_build_result.json`：`FLASH_IMAGE_VERIFIED_NOT_PROGRAMMED`。板上仍为 v56，本轮未访问或改写硬件，未启用舵机。实际亮处细节、收敛和明暗取舍待上板验收；不得把合成传感器模型中的 202/255 当作录像修复后的实测结果。

## 用户随后授权烧录

2026-10-20 09:44（北京时间），按用户明确“烧录”指令，用 `tools/program_v57_flash.ps1` 官方 BitWriter 命令行完成一次联合 Flash program/verify，用时约 101.6 秒，目标 PH1P35MDG324。写入前后镜像、冻结 FPGA 输入、回归输入与原 v55 MCU 源码哈希匹配，最终 Routed 时序核验通过。日志 `tmp/v57_flash_program.log`，成功 receipt `tmp/v57_flash_programmed.json`。未重复下载、未启用舵机、未额外 GDB load/设置 PC。

Win32_SerialPort 初次仅返回 COM1，进一步以 .NET 和 PresentOnly PnP 确认 COM15 为 VID_0403/PID_6042 接口 B、状态 OK，再仅查询状态。MCU 应用已响应，armed=0、remaining=0、faults=0；ArUco status=-7（检测开关关闭），frames=0，不能表述成已实际识别标记。串口记录 `tmp/v57_post_flash_uart.log`。真正物理断电启动和高光画质仍待用户验收。
