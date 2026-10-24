# v53：HDMI 视频“始终 --”的帧首重同步修复

## 输入与证据边界

- 用户录像：`C:/Users/Chieh yu/Videos/2026-10-19 13-11-43.mp4`，1280×720 / 60 fps，实际解码 519 帧。
- 视频 SHA256：`37180484d98778c46f74dbbcbf27ad32d94b7d083242b380b456f0a3a88c1479`。
- 当前录像显示手势始终 `H:-- T:0`。离线规则在部分张掌、握拳帧有输出，但这不是人工标注准确率。
- HDMI 录像带 OSD、采集与编码，不能当作 FPGA 内部 ISP 总线的逐位原始抓取。
- 所有功能保留；手势仍是纯 FPGA 张掌/握拳，MCU 不增加手势工作。未写 Flash、未开舵机。

## 已确认的 RTL 缺陷

`ua_motion_detect.v` 原计数器在 `I_tuser` 分支给 x/y 清零，随后另一个非互斥分支又用旧 x/y 递增；同拍非阻塞赋值以后者为准。

当复位释放时摄像头已经输出部分行，下一帧 SOF 不能纠正列偏移。手势前端依赖严格的相邻 RGB 组及 160×90 网格完整性，坐标偏移会导致错误采样或坏帧拒绝。

旧版正常整帧启动测试通过，不代表任意时刻启动能恢复。新增回放在首个完整帧前送 13 组数据，旧版在 `Adapter RGB skew x=0 y=3` 处失败。独立坐标测试使用旧生成副本也复现 `Sample phase ... x=19 y=2 sv=1`。

修复后，当前拍 SOF 将有效坐标直接定义为 (0,0)，后继计数由当前有效坐标计算；同步修正采样相位、参考 RAM 地址、输出坐标及帧末检测，不修改 RGB、肤色阈值、分类或投票。

这是已复现并修复的缺陷，尚未证明是板上失败的唯一原因。

## 验证记录

1. 代表帧真实 RGB → 手势核心：帧 0 / 210 / 240 / 390，各两次，8 次 RTL 回放与模型一致。`tmp/hand_rtl/capture_20261019_v52_diagnosis2/result.json`。不是全视频 RTL 准确率。
2. 正常完整视频时序 → 实际 motion 适配器 → 核心：8 个连续 1280×720 帧，460800 个采样，3 个处理结果，最终 OPEN / 有框。`tmp/hand_rtl/capture_motion_integrated_20261019/result.json`。
3. 增加 13 组启动碎片：修复前失败，日志 `tmp/hand_rtl/capture_motion_preroll13_before/vsim.log`；修复后完整连续流通过，日志与源码哈希见 `tmp/hand_rtl/capture_motion_preroll13_after/result.json`。
4. 独立坐标 oracle：1/2/4 倍行采样，每种覆盖 8 种碎片长度/截断位置，每种校验 7680 拍；`tmp/hand_rtl/motion_sof_d{1,2,4}.log` 全部 PASS。
5. 原运动 RAM 两种实现的周期等价回归：1280×720，以及奇数行、ROI、保持背景开关等四种配置通过。`tmp/hand_rtl/motion_compact_sof_fix/result.json`。

连续 RGB 回放重复了录像帧 210；未保存的非采样行按最近采样行重建。它验证采样时序及已保存 RGB 数据的处理，不冒充全场景动态视频仿真。

## 同步资源精简

`hdmi_mixer_user.v` 七条 ArUco 边/轴线的残差判断从 `abs(error)<=2048` 换成有符号 `-2048<=error<=2048`，省去复制的绝对值加法器。24 位全部 16777216 种残差穷举等价，包括最小负数。描线宽度、坐标、颜色及显示延迟不变。

## 整机综合、布局

`tmp/v53_area_result.json`：2026-10-19 13:51 通过，实际打包 **19494/21216 Slice（91.88%）**，97/108 ERAM、25/40 DSP。相比 v52 的 19516 Slice 少 22 Slice；这是修复加资源改写的净变化，不能拆成未经测量的各项节省。

布局数据库 SHA256：`0DAAF51E67FD4D94379F0F9F3CD0627F7A80DAA9310A27961004E81033442EFF`。面积报告保留手势、5×5 图像处理、AWB/AE、颜色/形状、运动、数字、ArUco 和 OSD 层级。沿用既有 DDR 等厂商警告，不声称整机零警告。

## 最终布线、bit 与独立复核

2026-10-19 14:06 完成：`tmp/v53_build_result.json` 状态 `ROUTED_VERIFIED_NOT_PROGRAMMED`。

- 最终资源仍为 19494 Slice、97 ERAM、25 DSP，未超 92% Slice 上限。
- Confidence `Routed`，SWNS **+0.233 ns**、HWNS **+0.020 ns**、STNS/HTNS 均为 0。
- STA coverage 94.82%，不将已有未覆盖时序路径冒充全部证明完成。
- bit：`deliverables/camera_hdmi_v53_sof_recovery.bit`。
- SHA256：`F67C768FDCF808AF559FC3C19BAF9BB4FA995812D8559D541BC577F4FFC8496A`。
- 构建进程退出后独立重新比对 485 个冻结输入哈希、bit 哈希、最终资源、Routed 时序及完成标记，通过。原 v52 的日志、bit、部署 receipt 未覆盖。

## SRAM 部署（用户明确要求“烧录”后）

2026-10-19 14:17，先独立只读确认当前 MCU＋config 双 TAP、器件 ID `4808f0e7`，再执行一次官方 BitWriter CLI 双 TAP SRAM 下载。未写 Flash，未启舵机，未重复下载。

原生下载到 100% 后出现既有的最终 DONE 读取单一不匹配 `PRG-9507 read=0x00 ref=0x01`，因此不能称原生流程零错误。脚本仅按原有严格条件接受这一特定末尾读取异常，随后通过独立 OpenOCD 检查 MCU/config 链、器件 ID、状态 `a9c0125d`（DONE 高）。记录 `tmp/v53_fpga_sram_programmed.json`，`native_final_check_passed=false`、`independent_done_verified=true`，原始日志保留。

14:19 恢复原 v39 ArUco MCU ELF（TCM 四节逐节比对一致），串口确认 `armed=0 remaining=0 faults=0`。记录 `tmp/v53_aruco_v39_restored.json`。MCU 不承担手势分类。

## 尚待验证

- 板上画面和手势识别效果仍待用户观察，不以成功配置/MCU 自检冒充实际识别恢复。综合脚本：`tools/check_area_hdmi_v53.ps1`，布线脚本：`tools/build_hdmi_v53.ps1`。
- 大手与暖色背景相连时可能超面积上限、握拳混入背景时投票可能误保留 OPEN。这些是另一个算法质量问题，不能用本次帧同步修复宣称全部解决。
