# v48：降低资源后重新布线

## 为什么暂停 v47

用户明确要求先优化资源再布线，因此暂停了旧版自动烧录，并仅停止已核实属于本任务的 v47 TD 进程。v47 最后仍在布线第四阶段，不是综合卡死；其布局为 20592/21216 Slice、104/108 ERAM。停止后的 FAILED receipt 表示任务主动取消，不能据此宣称工具已证明设计不可布线。未烧录任何新版本。

## 本轮实现

仅修改手势缓存实现，不改变张掌/握拳类别、肤色阈值、候选上限、投票规则或其他图像功能，不把手势交给 MCU。

1. **单帧掩膜缓存**：v47 已用整个事务的所有权锁禁止重叠捕获，因此第二个物理帧银行不会被使用。增加默认关闭的 SINGLE_BANK 参数，仅两类手势核启用。保留默认双银行，兼容其他调用。掩膜 ERAM 从 6 块降到 3 块。
2. **10 位双口共享 RAM**：前端和 CCL 使用 10 位 R 样本，随后的 BFS 队列使用 15 位坐标，生命周期不重叠。使用 14400×10 位真双口存储：普通 R 数据单地址，队列一个坐标拆到相邻两个地址，两个端口在同一拍同时读/写。仍一拍响应，没有序列化成两拍，没有新增时钟或 CDC。该 scratch ERAM 从 12 块降到 8 块。
3. 原 16 位通用 scratch 和其他模式的双帧默认实现均保留。原 ArUco MCU 固件、AE/AWB、降噪、各显示模式、颜色/形状、motion、数字识别及 OSD 不关闭。

## 已验证

- 真双口 RAM 98918 次检查：全部 14400 原始样本地址、2500 队列地址、边界、生命周期交替、每拍切换模式及一拍响应通过。`tmp/hand_rtl/packed_scratch_v48/result.json`。
- 冻结 v47 实际综合源先逐项匹配旧 manifest SHA256，再作为仅测试的参考实现保存到 `host/tests/reference/v47_resource/`，不进入生产源清单。
- 96 帧连续真实 RGB 输入下，两个完整核每个周期的结果、框、tips、fault、drop、cycles 全部一致，接受/完成 14 个检测帧。`tmp/hand_rtl/binary_resource_cycle_v48/result.json`。这是逐周期实测，不是“结果看着类似”。
- 两段视频共 14 个代表场景，各重复两次，共 28 次完整 RGB 链路通过，后端 cycles 与 v47 对应场景相同。`tmp/hand_rtl/binary_resource_rgb14_v48/result.json`。不是全部视频帧的 RTL 验证。
- 61 组分量分类、128/129 队列边界、坏帧/截断帧及复位恢复通过，分别见 `binary_shape_resource_v48`、`binary_queue_resource_v48`、`binary_input_recovery_resource_v48`。
- 小模块 TD Gate：2725 Slice（估算）、13 ERAM、4 DSP。ERAM 比 v47 手势核少 7 块，且没有增加检测周期。报告 `tmp/v48_hand_micro.area`，日志 `tmp/hand_rtl/binary_compact_v48_micro.log`。

以上保留原算法在极暗、偏色和非支持手势上的已知识别局限；存储等价优化不等于提高识别率或任意条件都可靠。

## 整机门槛

先执行 `tools/check_area_hdmi_v48.ps1` 做完整综合、布局和源码冻结。必须全部仿真源码匹配，实际 Slice 少于 v47 的 20592、ERAM 不多于 97、DSP 不多于 25，才准许进入新布线。以 `tmp/v48_area_result.json`、`tmp/v48_placed.area` 为准，Gate 估算不算最终面积。

新布线使用 `tools/build_hdmi_v48_binary.ps1` 从冻结 `tmp/v48_binary_placed.db` 继续，最终仍须 Routed 时序 SWNS/HWNS 非负、STNS/HTNS 为零及 bit/source SHA 一致。所有旧 v47/v46 自动烧录路径都不能作为 v48 成功依据。

## v48 实测：RAM 减少但 Slice 未改善，不进入布线

完整综合、布局已结束：20741/21216 Slice（97.76%）、97/108 ERAM、25/40 DSP。相对 v47，ERAM 少 7 块，但 Slice 多 149。资源门槛正确拦截，receipt 为 FAILED（资源减少目标未达成，不是工具综合错误），未布线、未烧录。完整原始证据保留在 `tmp/v48_area.log`、`tmp/v48_placed.area`、`tmp/v48_area_result.json`。

## v49：共享颜色检测的候选跨度运算

保留 v48 的 RAM 优化；在 `ua_blob_select2` 中先选择最大候选，再计算四组投影跨度，替代两个候选同时各算一组减法。保持面积相同时优先槽 0、无候选输出零，以及 EOF 后一拍发布的全部行为。不改判色、形状阈值或平滑规则，也不改 ArUco MCU。

`tools/test_track_v49.ps1` 验证 4×1、16×2、32×2、40×2、64×48、1280×720 六种尺寸，包括输入空拍、无帧间隔、随机颜色及中途复位；所有外部输出逐周期与冻结参考一致。另通过 4096 组归一化和 100000 组随机分类算术测试。源码/日志哈希在 `tmp/v49_track_result.json`。该验证不是板上保证。

v49 整机综合、布局于 2026-10-19 11:01 通过：20491/21216 Slice（96.58%）、97/108 ERAM（89.81%）、25/40 DSP。相对 v47 减少 101 Slice、7 ERAM；相对 v48 减少 250 Slice。仅逻辑降幅较小，仍接近器件满载，不能据此保证布线时间。

证据为 `tmp/v49_area_result.json`、`tmp/v49_placed.area`、`tmp/v49_area.log`；冻结布局 SHA256：`0B1A7C55014661D212264D7DE9A86A968A45FD02D92FA8C7BE66B92F7E6F147C`。全部冻结输入和六组手势仿真哈希通过，另有颜色检测等价回归。

已启动 `tools/build_hdmi_v49_binary.ps1`，从新冻结布局重新布线，不重复综合；最终仍须 Routed SWNS/HWNS 非负、STNS/HTNS 为零及全部输入/bit SHA256 一致。v48 不准烧录，旧 v47 不再继续；尚未宣称 v49 布线闭合或烧录成功。

后台跟进沿用原 automation id `v47`（避免重复任务），已改名为“v49 资源优化后布线及一次 SRAM 部署”，仅监视 v49。通过独立时序与哈希核验后按原授权一次 SRAM 下载及恢复原 ArUco MCU OFF，不写 Flash、不启用舵机；失败或需人工处理时暂停，静态无变化时不通知。
