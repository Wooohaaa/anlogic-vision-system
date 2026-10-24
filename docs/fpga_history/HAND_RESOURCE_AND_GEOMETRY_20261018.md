# 2026-10-18：新手势移植与保功能资源优化

## 验收边界

完整分类器尚未完成，生产工程仍为旧 `ua_hand_profile`。本轮没有生成新手势 bit，没有烧录 SRAM/Flash、重配 MCU 或开启舵机。不能把单模块仿真、软件开发视频通过、整体布局通过混为上板识别效果。

保留 HDMI 1280×720、全部检测、9-bit ISP 余量、5×5 降噪、原有阈值与显示时序。资源优化只改内部 RAM 映射；没有降低帧率、抽样精度或关闭功能。

## 整数软件参考

`host/hand_fixed_classifier.py` 在原生 160×90 网格上使用整数距离、Q4 半径、半像素腕部、整数凸包与叉积；修正了指宽探针中半像素与像素 Q8 的两倍单位错误及相关定点系数。标签未改为迎合结果。

`python host/tests/test_hand_fixed_classifier.py --out tmp/hand_fixed_native_20261018 --stress`：

- 两段开发视频的稳定标注区分别 288/288、250/250，共 538/538；这只是整数软件参考。
- 自动颜色/亮度/噪声扰动仍未全部通过，新视频 dim90 为 227/250、bright110 为 230/250、warm5 为 214/250、cool5 为 246/250、noise4 为 247/250、dim90noise4 为 230/250。
- 总状态 `INTEGER_REFERENCE_BASELINE_PASS_STRESS_PENDING`。不能宣称暗场/背光泛化问题解决。
- 输入视频、组数据、标签和模型 SHA256 都在该目录的 `result.json` 中冻结。

## 新增 RTL 验证

| 核心 | 已完成的验证 | 独立 TD Optimize Gate：Slice / ERAM / DSP |
| --- | --- | --- |
| 单区域掩膜提取 | `tmp/hand_rtl/component_palm_native/result.json`，50 组；区域内夹杂其他物体、随机外部读延迟、输出暂停、清除和容量溢出；串接真实掌心 RTL | 429 / 4 / 0 |
| 掌心距离 | `tmp/hand_rtl/palm_distance_setup/result.json`，56 组、257,044 像素案例；随机、边界、全前景/空帧、真实掩膜；65536 个量化输入穷举 | 964 / 13 / 0 |
| 腕部中位数 | `tmp/hand_rtl/wrist_compact_hist/result.json`，118 组；Numpy 独立中位数、奇偶样本、空区域回退、最大半径、真实掩膜、输入间隙、畸形 last、清除与 RAM 复用 | 424 / 0 / 0 |
| 整数凸包 | `tmp/hand_rtl/hull_native/result.json`，100 组；与对所有前景点排序的独立单调链比较全部顶点及顺序，含稀疏/凹形/退化/空图、真实掩膜、暂停和清除 | 323 / 1 / 2 |
| 共享整数数学核 | `tmp/hand_rtl/integer_math/result.json`，73,121 组；穷举 0..65535 开方、32-bit 极值与随机输入、完全平方附近、除零、忙时启动及中途清除 | 189 / 0 / 0 |

腕部先前版本为 599 Slice，直方图缩为有界的 X=5 bit、Y=8 bit，并显式共享存储端口后降至 424 Slice，重新跑同样 118 组测试通过。列计数最多 18，行计数最多 160，未截断合法计数。

凸包先按每列最小/最大 Y 形成有序候选点，避免通用排序器。数学上与完整前景点凸包相同；不等于简化轮廓或减少手指特征。

微型综合未带板级 IO 约束，因此报告有未约束 IO 警告；不生成 bit、不凭这些报告宣称板级频率或时序闭合。模块资源不能机械求和当作最终整机占用。

## 保功能缓存压缩

### 运动参考缓存

原 65536×8 的显式宏改成 57600×8 的实际尺寸，读写保持同钟同步 old-data 行为。保留 `COMPACT_REFERENCE_RAM=0` 旧分支用于等价比较。

- `host/tests/test_motion_compact.py --out tmp/motion_compact_v42_checked`：1280×720 完整 8 帧和另三种采样/ROI/保持设置；每周期比较完整输出、采样及检测状态，全部通过。
- 旧宏的仿真使用独立功能契约模型；没有解密厂商模型，不能替代真实物理读写验证。
- 单模块 32→27 ERAM。整机 v42 布局 20,509 Slice、97 ERAM、22 DSP；receipt 为 `PLACED_RESOURCE_CHECK_PASS_NOT_ROUTED`。

### 去马赛克三个行缓存

原 IP 配置为 2048 字，生产读写地址只有 0..319。新增 `ua_demosaic_line_ram`；逻辑限制为实际行宽，物理深度补到原生 512 字，避免 TD 在读寄存器后插越界选择器而退回 LUT RAM。33/32-bit 数据与单周期 old-data 读取保持不变。

- 维护层 `line_buffer_demosaic.v`、`zhenghe.v` 加可选兼容分支；未编辑生成的 IP 产品。原 GBK 注释仅做 UTF-8 编码转换。
- `test_demosaic_compact.py --out tmp/demosaic_compact_v43_native`：1280×720、1920×1080、640×47、80×24 六轮帧输入，含中途复位、输入间隙、同址读写。全部逐周期输出一致，测试还检查全部合法地址始终小于实际深度。
- 每个缓存 4→1 ERAM；整机 v43 **88 ERAM、20,535 Slice、22 DSP**。
- v43 TD 完成综合/布局，但严格的“Slice 不高于 v42”门槛失败（增加 26）。保留 `tmp/v43_area_result.json` 的 FAILED 状态，没有篡改为通过。层次报告中三个新缓存均为 1 ERAM、0 LUT/FF；LUT 总数 20,058→20,050，但整体放置/打包的 FF、进位和占位有变化，不能将 Slice 增加称为解决。

### 有限 FIR 单银行历史

有限 FIR 路径第一历史行不必使用两个交替银行：同一拍先读旧字、再覆盖新字可获得相同上一行；递归反馈路径仍使用旧双银行。原 5×5 滤波、色调 LUT 和饱和度运算不变。`COMPACT_FINITE_HISTORY=0` 可用于比较。

- Icarus 完整对照因运行超过 900 秒而超时，不算通过。
- 使用 ModelSim 重跑 `test_photo_compact.py --out tmp/photo_compact_v44_msim --simulator modelsim`：5 个配置全部通过；其中实际 1280×720、9-bit、5×5、tone 开启，比较 1,121,381 周期、1,037,114 个输出组，包含背靠背帧、复位、随机通道、明暗边界和高光余量。
- 另覆盖 8-bit、3×3 路径、小宽度、tone 旁路及递归兼容路径；所有输出位和 sideband 均逐周期一致。
- v44 完成布局但资源验收失败：88 ERAM、20,690 Slice，没有取得预期 RAM 节省，Slice 也增加。保留 FAILED receipt；不作为烧录版本。
- 通过 `tools/inspect_v44_gate.tcl` 只读导出门级网表，确认第一历史行变为 `READBEFOREWRITE` 单端口，映射到 20-bit 原生字宽，512×104 仍用 6 个 ERAM；其余三行是 320×312 的宽 PDP，占 8 个 ERAM。失败原因不是功能仿真错，而是物理映射抵消了逻辑容量缩减。

### 四行历史打包与延迟写回（替代失败的同址单银行）

新维护实现将四行历史放在一个宽 PDP 中：`h_valid` 读取该列的全部历史，`p_valid` 延后一拍写回 `{上一组三行历史, 当前行数据}`。读写地址来自不同流水位置，当前 320 组行宽下不会发生同址读写；小宽度和递归路径仍使用兼容分支。无需倍频或降低吞吐率。

- `tmp/photo_compact_v45_ordered/result.json`：ModelSim 重新运行相同 5 个配置通过，包含完整 720p 逐周期对照，仍比较全部像素与 sideband，而不是只比较画面摘要。
- 独立包装 `photo_history_micro` 保留所有通道可观察性并折叠输出以避免超过器件 IO 上限；TD Optimize Gate 为 17 ERAM、0 DSP（原生产降噪模块 20 ERAM）。微型 Slice 数不能直接与整机层次打包后的数字比较。
- v45 整机完成综合、布局：**85 ERAM、20,537 Slice、22 DSP**。相对 v41 的 102 ERAM、20,549 Slice，节省 17 个 ERAM（16.7%），Slice 仅少 12 个，尚未解决逻辑紧张。
- 打包后的真实 AWB 行缓存→早标记对齐→降噪 RAM 测试重新通过：`tmp/v44_photo_contract/packed_alignment.log`，3 帧、15,360 像素、宽度 1280；软件暗噪声模型另有 8 项测试通过，后者不作为真实摄像头画质证明。
- 相对 v42 的 20,509 Slice 增加 28，仍未达到严格“不增加 Slice”的验收门槛；`tmp/v45_area_result.json` 保留 FAILED，不能当作最终构建通过。层次报告确认降噪模块为 17 ERAM、三个去马赛克缓存各 1 ERAM。未做最终布线/时序闭合，未烧录。

## 继续工作

1. 分析超紧的整机逻辑预算；不能仅凭 ERAM 足够就接入完整分类器。
2. 单区域的顺序凹陷、指尖筛选/去重、指宽/拇指排除与原始分类现已连通（见文末）；仍缺候选亮度置信度与多区域选择。
3. seed/grown 回退、NONE/拳头/单指/张手的时间投票与生产接口集成。
4. 两视频完整 RTL 回归和暗场/背光扰动回归；不能用 538 个软件标签或局部几何测试替代。
5. 全工程综合、最终 Routed SWNS/HWNS 非负、STNS/HTNS 为零、输入与 bit 哈希闭环后才按已授权流程烧录一次 SRAM；保留所有功能，不写 Flash，不开舵机。

## 后续本轮：共享存储子流水与逐边凹陷（已验证）

### 队列→距离图→凸包栈共享

新增 `ua_hand_geometry_shared.v`、`ua_hand_scratch_ram.v`，维护旧核心的 `EXTERNAL_MEMORY=0` 兼容分支。控制器按阶段复用一个 14400×16 scratch RAM：区域提取结束后队列不再使用，从第一个栅格输出开始转给距离图；掌心求完后转给凸包。选中区域位图单独保留，供腕部/凸包重放，避免框内其他物体混入。

组件新增仅在空闲时接受的同步位图 probe。清除时阻断新事务，若外部掩膜读取还有未返回响应，`O_start_ready` 会一直等待该响应排空，防止旧响应串入下一次任务。所有模块仍同一时钟域，没有新 CDC 或时序例外。

- `tmp/hand_rtl/geometry_shared_watchdog_fixed/result.json` 与 `geometry_private_reference/result.json`：共享/独立存储各 53 组通过，测试使用两视频 14 个选定掩膜的 seed/grown 区域，以及合成/随机区域、嵌套无关物体、四种中途清除、源读响应排空、输出暂停、非法起点、队列溢出、watchdog。
- 逐个比较区域面积、全部重放掩膜像素、掌心/半径、腕部中位数方向、全部凸包顶点及顺序。原版独立模块回归也重新通过：掌心私有/外部各 56 组（每组方案 257044 像素案例）、凸包私有/外部各 100 组、区域隔离串掌心 50 组。
- 测试确实发现并修正了一个控制错误：watchdog 达到阈值后反复覆盖 FAIL 状态，导致没有 done；现在 FAIL 可执行并退出。旧失败保存在 `tmp/hand_rtl/geometry_shared_checked/hand_1_9.log`；修复后的超时用例 202 周期结束，`fault=1`，没有无限等待。
- `host/tests/verify_hand_geometry_resources.py --out tmp/hand_rtl/geometry_memory_comparison.json` 验证源码哈希、测试记录、53 组相同的结果与周期数、测量报告及完成标记。

| 同口径 Optimize Gate 子流水 | Slice | ERAM | DSP | FF |
| --- | ---: | ---: | ---: | ---: |
| 独立缓存 | 2167 | 18 | 2 | 824 |
| 共享缓存 | 2182 | 14 | 2 | 817 |
| 变化 | +15 | -4 | 0 | -7 |

这是手势几何子流水的单模块综合，不是整机再减少 4 ERAM 的实测结果。原工程仍用旧手势模块，最近整机布局数据仍是 v45 的 85 ERAM / 20537 Slice。

### 逐边凹陷判断

`ua_hand_defect_edge.v` 消费一条凸包边和两端点之间按顺序提供的轮廓点，保留第一个最大叉积点，使用半像素单位与 Q4 半径比较 `160*cross >= 13*radius*length`，并检查凹谷夹角点积为正。通过两个时分复用乘法器计算叉积、边长平方、深度和夹角；整数开方沿用已验证核心。

- `tmp/hand_rtl/defect_edges/result.json`：828 组逐项精确比较，涵盖两视频真实轮廓的各凸包边、随机路径、正反方向、相同最大深度、空/退化边、整数阈值、最大半径、无效输入和三种中途清除；556 组合格凹陷。
- `tmp/hand_rtl/defect_gate.area` 与日志最终标记：515 Slice、0 ERAM、2 DSP，含独立数学核。尚未与整条轮廓遍历及指尖筛选控制器整合，不能据此称手势识别已经通过。
- 独立综合仍只有测试 IO，未约束 IO 警告不能作为板级时序验证；本轮没有最终布线、生成新手势 bit 或烧录。

## 本轮继续：共享轮廓、指宽与完整单区域分类

`ua_hand_defect_scan` 将轮廓点、凸包顶点和最后出现索引放在原 14400×16 scratch 的不同地址段；`ua_hand_tip_candidates` 的候选表使用剩余 9216..9855 地址，不额外增加 ERAM。多方访问由 `ua_hand_geometry_shared` / `ua_hand_defect_geometry` 仲裁；凸包输出期间只有其停止读栈的周期可写候选/凸包副本。区域位图继续单独保留供指宽读取。

- `defect_scan_external_final` / `defect_scan_private_final`：各 78 组，覆盖不规则凸包输入顺序、8192 点边界、重复轮廓点使用最后索引、首尾跨段、输出暂停、中途清除和缺失凸包点。
- `defect_geometry_client_final`：43 组真实共享链路，逐个比较完整凹陷结果，并在 scratch 被改写后探测全部保留区域像素。
- `geometry_shared_client_ports`：原几何回归 53 组重新通过。
- `tip_width_keyword_fixed`：311 组精确指宽；未将 probe 缺失视为零宽细指。两个截面、负坐标舍入、越界和旧响应排空均覆盖。
- `tip_candidates_initial` / `tip_candidates_private`：各 259 组；`tip_filter_serial_ab` / `tip_filter_parallel_ab`：各 255 组；`product_serial_parameterized`：2048 组。
- `shape_classifier_serial_final` / `shape_classifier_parallel_final`：各 66 组，RTL 从原掩膜读取开始自行计算全部几何和原始类别。对照两视频选定帧、合成/随机区域，且验证事务参数在 start 拍锁存、中途清除与超时退出。

当前 A/B 审计：`host/tests/verify_hand_classifier_resources.py --out tmp/hand_rtl/classifier_serial_resource_ab.json`。

| 同源码、同输入/结果的单区域分类 | Slice | ERAM | DSP | FF |
| --- | ---: | ---: | ---: | ---: |
| `PARALLEL_COMPARE=1` 参考 | 7171 | 14 | 10 | 2851 |
| 默认共享串行比较 | 6158 | 14 | 10 | 2852 |
| 变化 | -1013 | 0 | 0 | +1 |

宽位几何比例改为共享 42×21 串行乘法，仍执行完全相同整数比较；未降低分辨率、删功能或改变阈值。66 组测试的总周期差为 -154..+46，不能当作所有输入下性能不变的保证。

**仍然不是烧录就绪版本。** 单区域 6158 Slice 不含完整前端/连通域，当前整机逻辑紧张，必须继续复用运算和优化整机。原生产仍用旧手势模块，最新整机物理数据仍是 v45 的 20537 Slice、85 ERAM、22 DSP；上述单模块数据不能替代整机综合/布线，更不能直接相加宣称已适配器件。两视频完整候选选择、投票、暗灰/背光扰动回归尚未完成，本轮未生成/下载新手势 bit。

## 当前最新状态：帧级流水与全帧回归

维护的 `ua_hand_frame_classifier` 已联合几何、准确整数红均值/评分和时间投票。软件掩膜/候选关联输入下，ModelSim 通过两视频全部 1688 帧，另有 28 帧合成动作；538 个审定稳定标签均匹配。完整 RGB/seed-grown 关联与暗场扰动仍未通过，不能从这些结果推导已可上板。

当前 Gate 数据：帧级联合模块 **7025 Slice / 14 ERAM / 10 DSP**；policy **650 / 0 / 0**；投票 **39 / 0 / 0**；含红统计的 CCL 地址显式移位后 **849 / 0 / 0**（此前 897 Slice / 1 DSP）。单区域兼容声明顺序后的同源码 A/B 已重新测量、两分支各 66 组通过，为 **7155→6194 Slice，节省 961**；原 6158/7171 报告保留为历史。

详见 `HAND_FRAME_PIPELINE_20261018.md`、`tmp/hand_rtl/both_video_frame_regression_verified.json` 和 `classifier_decl_compatible_ab.json`。前端 native 红接口与整帧采集许可已验证，但尚未将 R 暂存真正复用到 geometry scratch。下一阶段仍需以共享数据通路为核心降低占用，完成关联与生产接入后再整机 P&R；本轮没有 bit 或硬件下载。
