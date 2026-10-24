# 新手势算法移植进度：掩膜、连通域及整数几何

## 当前结论

截至 2026-10-18，已经实现并验证掩膜/连通域/整数几何核心，并串起共享 RAM 的区域提取→掌心→腕部/凸包子流水；新增了逐边凸包凹陷 RTL。**尚未实现完整定点手势分类器，也未替换生产工程的 `ua_hand_profile`**。没有生成或烧录冒充新算法的旧 bit；没有写 Flash、启用舵机。生产视频支路仅做了缓存映射优化，像素算法、位宽和延迟不变，另有逐周期等价测试。

2026-10-18 的新增测试、整数参考修正、资源检查及未完成项详见 `HAND_RESOURCE_AND_GEOMETRY_20261018.md`。下文早期三模块的测试仍保留为独立证据。

软件版开发视频通过不等于 FPGA 版通过。先前冻结软件原型的颜色/亮度扰动回归仍有失败，本轮没有把这些失败标记为解决。

## 已实现

1. `rtl/user/ua_hand_mask_frame.v`：160×90 检测采样、严格肤色种子、受限区域扩张、形态学处理。只处理检测支路，不降低 HDMI 显示分辨率。
2. `rtl/user/ua_hand_blob_scan.v`：串行 RLE 八连通域统计。输出面积、种子数量、包含端点的包围框、真正属于该连通域的首个栅格像素。
3. `rtl/user/ua_hand_contour_trace.v`：Moore 八邻域外轮廓跟踪，使用有向边闭合判据，保留细桥处重复经过的顶点。边界外当背景，不读越界地址。
4. `rtl/user/ua_hand_component_mask.v`：从真正的起点提取单个八连通区域，框内其他物体不会混入掌心/手指计算。
5. `rtl/user/ua_hand_palm_distance.v`：955/1369 权重的两遍整数距离变换、Q4 量化与第一主掌心波峰选择。
6. `rtl/user/ua_hand_wrist_median.v`：腕部区域的独立 X/Y 中位数，以半像素坐标处理偶数点，并生成腕部方向。
7. `rtl/user/ua_hand_convex_hull.v`：列极值桶排序加整数单调链凸包，保留与所有前景点直接建凸包完全一致的顶点及顺序。
8. `rtl/user/ua_hand_integer_math.v`：共享减法器的 32-bit 无符号整数开方/除法，分别 16/32 个迭代周期，除零明确报错。
9. `rtl/user/ua_hand_geometry_shared.v`、`ua_hand_scratch_ram.v`：区域提取→掌心→腕部/凸包的互斥存储控制、掩膜重放和源读请求清空；同口径综合 18→14 ERAM，增加 15 Slice。
10. `rtl/user/ua_hand_defect_edge.v`：逐边凹陷的最远点、深度和夹角判断，复用两个乘法器与整数开方，不包含指尖筛选/去重。
11. `rtl/user/ua_hand_defect_scan.v`、`ua_hand_defect_geometry.v`：按每个凸包点在轮廓中的最后出现位置排序，连接所有逐边凹陷；与区域/掌心/凸包共享同一 scratch。
12. `rtl/user/ua_hand_tip_candidates.v`：腕部方向与距离门限、无凹陷回退、距离/坐标稳定排序、近邻去重和七指饱和。
13. `rtl/user/ua_hand_tip_width.v`、`ua_hand_tip_filter.v`、`ua_hand_product_serial.v`：两个横截面指宽、轴向过滤、拇指排除、最终单指方向与原始分类；共享串行乘法做宽位比例比较。
14. `rtl/user/ua_hand_shape_classifier.v`：将以上连接成真实掩膜读取→单区域原始分类的完整 RTL；不包含多候选选择、时间投票或生产顶层替换。

### 缓存与接口约定

- 掩膜每个 18 bit 字存六个检测像素，各像素三位 `{working, loose, seed}`。160 像素一行占 27 字，行末填充位为零。
- 两帧独立所有权。计算/消费者占用的帧不可覆盖；无空闲帧时丢弃整帧检测输入，不反压 HDMI。
- 连通域和轮廓读接口一次仅一个未完成请求，允许响应延迟。消费者必须持有掩膜银行直到分析结束。
- 连通域每行最多 16 段、最多 15 个同时存活标签。行末先压缩当前标签，再回收失效标签，避免误用已复用的别名。
- 连通域输出在本帧 `done && !overflow` 前是暂定统计。若溢出，调用者必须丢弃整帧暂存结果。
- 分类前需使用连通域真实起点，而不是包围框左上角；后者可能落在背景或框内另一个物体上。
- 轮廓超过 8192 步或起点非法时明确返回 fault，不永久卡住。完整控制器还需加入整体 watchdog 和检测结果时效管理。
- 三个模块同一检测时钟域，未引入新 CDC 或时序例外。

## 验证证据

使用 Icarus Verilog、独立 OpenCV 组件/轮廓参考及 TD PH1P35MDG324 单模块综合。

| 检查 | 结果/证据 |
| --- | --- |
| 连通域随机与构造测试 | `tmp/hand_rtl/ccl_shared_port/result.json`：248 组模式检查通过；其中 6 组故意超限，均正确报 overflow，其余比较全部连通域统计和起点 |
| 外轮廓测试 | `tmp/hand_rtl/contour_ordered/result.json`：466 组通过，比较顶点出现次数和环形遍历顺序（允许反向），最大测试轮廓 1452 点 |
| 轮廓异常退出 | `tmp/hand_rtl/contour_faults/result.json`：背景起点、越界起点、有限步数溢出均明确报 fault |
| 缓存所有权及实际读握手 | `tmp/hand_rtl/mask_ownership.log`：双银行并发、忙时整帧丢弃、内容不被覆盖、畸形帧不发布、处理中 clear、reset 后恢复；使用真实 frontend→CCL 同步 RAM 接口 |
| 完整视频容量模型检查 | `tmp/hand_rtl/ccl_full_capacity/result.json`：870 + 818 = 1688 帧，seed/grown 均未超限；两视频最大每行段数分别 11/12、14/11。此项是模型容量审计，不是全视频 RTL 分类回归 |
| 真实 RGB 组串联 RTL | `tmp/hand_rtl/chain_ordered/result.json`：两视频共 14 个选定帧，原 RGB 组驱动前端，逐字比较全部 2430 掩膜字，再比较全部 grown 连通域和最大区域的有序外轮廓。最大区域选择仅用于连线验证，不宣称它就是手 |

新增/维护的测试入口位于 `host/tests/`：

- `test_hand_blob_scan.py`、`tb_hand_blob_scan.sv`
- `test_hand_contour_trace.py`、`tb_hand_contour_trace.sv`
- `test_hand_contour_faults.py`
- `test_hand_mask_chain.py`、`tb_hand_mask_frame.sv` 的 `HAND_CHAIN` 测试开关
- `audit_hand_ccl_capacity.py`、`tb_hand_mask_ownership.sv`

重新运行时使用新的 `--out` 目录，保留已存在的正负证据。测试不修改标签区间。

## 单模块资源估算

以下是 Optimize Gate 的估算，**不是整体工程放置/布线结果，也不能直接相加预测最终占用**。

| 模块 | Slice 估算 | LUT 总数 | FF | ERAM | DSP |
| --- | ---: | ---: | ---: | ---: | ---: |
| 掩膜前端微型包装 | 905 | 1178 | 314 | 6 | 2 |
| 连通域（含真实轮廓起点） | 668 | 846 | 326 | 0 | 0 |
| 外轮廓跟踪 | 155 | 203 | 98 | 0 | 2 |

资源报告分别为 `tmp/hand_rtl/mask_gate.area`、`blob_gate.area`、`contour_gate.area`；日志末尾必须有对应 `*_MICRO_SYNTH_COMPLETE` 标记。

资源优化：查阅本机 TD 官方 HDL 模板，使用有效的 `ram_style="dram"` 约束小表，避免占用分类器预留 ERAM；将互斥状态的统计表读取显式共享为单端口。加入真实起点后，连通域从 794 Slice 的多读端口版本降至 668 Slice，功能测试重跑通过。此前不含真实起点的 609 Slice 版本不是当前功能等价基线。

微型综合没有板级管脚约束，其 IO 未约束警告是该测量环境的限制，不是生产约束已经通过。未使用该报告的默认时序数字宣称 100 MHz 时序闭合。

## 仍未完成，烧录前必须完成

1. **单个已选连通域的分类流水现已连接并通过 RTL 回归**，见下方本轮记录。仍需将其接入多候选/逐帧控制器；不能把单区域测试称为两段完整视频识别通过。
2. CCL 红总和、候选亮度/评分和时间投票已实现并通过单模块及帧级回归；仍须连接 native 红采样与 scratch 生命周期，不能删除亮度筛选后宣称完整输入链路等价。
3. seed/grown 关联、去重与混合回退、生产时效控制及顶层接口仍需集成。几何和帧级控制器已含超时/故障退出，保持后续 OSD 坐标正确。
4. 将新实现接入维护源清单/生产顶层，确认生成 `.prj` 真实包含所有新模块，再移除旧手势模块。
5. 软件掩膜/候选输入条件下，两段全部视频的几何/评分/投票 RTL 回归已通过；完整 RGB/候选关联 RTL 和暗灰、背光、噪声扰动仍需完成。报告错误帧，不以正常素材通过替代扰动效果。
6. 全工程综合、放置、布线，核验最终 Routed SWNS/HWNS 非负、STNS/HTNS 为零，核验资源上限与源/bit 哈希。
7. 以上通过后，使用官方终端 BitWriter 流程 SRAM 烧录；不写 Flash，不启用舵机。板上实际识别效果仍需验证。

## 2026-10-18：单区域完整分类已连通

完整维护实现为 `ua_hand_shape_classifier.v`。由测试台提供只读 seed/grown 掩膜、CCL 包围框与真实起点；RTL 自行提取选中区域、计算掌心/腕部/凸包、遍历轮廓、判断凹陷、筛选去重指尖、探测指宽并输出原始 ID。没有注入软件掌心或轮廓，也不使用首帧参考。

- 原始 ID：0=无有效掌心或两指歧义，1=拳头，2=单指，3=张手。生产旧接口的 ID/显示映射尚未替换，不能直接将这些数字接到现有 H/T 显示。
- `tmp/hand_rtl/shape_classifier_serial_final/result.json`、`shape_classifier_parallel_final/result.json`：两种算术实现**各 66 组通过**，均对照 `hand_fixed_classifier.features` 的原始类别、指尖数、掌心位置、半径和区域面积。包含两视频 14 个选定掩膜的 seed/grown 输入、合成手、随机区域、孔洞/嵌套无关物体、四种中断重启、独立 watchdog；不是逐帧候选和时间投票测试。
- `tmp/hand_rtl/contour_exact_cv/result.json`：306 组精确轮廓顺序通过。旧版测试只验证“允许反向”的环形遍历；完整分类依赖最大凹陷点的先后顺序和重复坐标的最后位置，所以新增 `OPENCV_ORDER=1`，旧默认分支保持兼容。
- 联调曾发现并修复：清除后响应没有传给内部控制器、最后一条合格边仍在计算时结束脉冲丢失。保留失败日志 `defect_geometry_cv_order/fingers3_1_abort1.log`、`shape_classifier_initial/fingers4_0_abort0.log`，没有将失败目录改为通过。
- 指宽 311 组；候选门限/回退/排序去重 259 组，独立/共享内存均通过；最终指宽/轴向/拇指分类 255 组，两种比较实现均通过；串行乘法全宽、忙时 start 和 clear 2048 组通过。

同一源码、相同 IO 可观察性、相同 66 组结果的 Optimize Gate A/B：

| 单区域分类子流水 | Slice | ERAM | DSP | FF |
| --- | ---: | ---: | ---: | ---: |
| 并行比例比较参考 | 7171 | 14 | 10 | 2851 |
| 默认共享串行比例比较 | 6158 | 14 | 10 | 2852 |

`tmp/hand_rtl/classifier_serial_resource_ab.json` 核对两套回归当前源码哈希、相同结果、报告新鲜度、TD 最终标记、器件与 IO 数；节省 **1013 Slice（14.1%）**。这些案例的总周期变化为 -154..+46；不能据此保证整机吞吐率或 Routed 时序。最初接线版本的 6932、第一次优化的 6178 是历史测量，不与当前 A/B 混用。

当前 6158 Slice **不含**掩膜前端、连通域、多候选亮度统计及投票，也不是整机占用；原生产顶层仍使用 `ua_hand_profile`，维护源清单尚未接入新分类器。还必须进一步降低逻辑开销，完成两视频完整 RTL/扰动回归和整机布线。本轮没有新手势 bit、没有烧录、没有写 Flash 或开启舵机。

## 后续本轮：全帧几何/评分/投票已通过

详见 `docs/HAND_FRAME_PIPELINE_20261018.md`。维护实现新增 `ua_hand_frame_policy`、`ua_hand_temporal_vote`、`ua_hand_frame_classifier`，CCL 增加默认关闭的 `RGB_STATS`；前端增加原始 native 红/亮像素 sideband 和可选整帧采集许可。

- ModelSim 全部 1688 个视频帧通过几何、原始类别、评分、投票和结果坐标断言；稳定标签 538/538。**输入掩膜、seed/grown 关联和区域红总和由参考前端提供**，不是完整 RGB→手势或板上效果证明。
- `tmp/hand_rtl/both_video_frame_regression_verified.json` 对旧视频已完成前缀、新视频独立冷启动回归及当前源码逐项审计。合并任务旧帧完成后拆分，原合并任务的超时/停止没有改成 PASS。
- native 红采样在 14 个真实 RGB 选定帧中每帧 14400 点核验；CCL 红总和 178 组、旧模式 248 组；候选评分 2338 帧/用例，投票 535976 组，帧级故障恢复 18 帧/四个清除阶段均通过。
- 声明顺序兼容修复后的最新同源码 A/B 为 **7155→6194 Slice，节省 961（13.4%）**，两分支各 66 组回归；之前 7171→6158 是历史测量。当前帧级联合模块为 **7025 Slice、14 ERAM、10 DSP**，还不包含完整前端/关联。
- 暗场/偏色扰动缓存仍有失败；整机 Slice 预算未收敛，源清单仍用旧手势模块。本轮未生成新 bit，未烧录。
