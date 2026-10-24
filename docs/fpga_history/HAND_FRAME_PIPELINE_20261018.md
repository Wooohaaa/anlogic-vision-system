# 手势帧级流水：算法验证与上板边界

## 本轮实现

`ua_hand_frame_classifier.v` 连接了以下真实 RTL：

```
候选表（区域、起点、红通道总和）
  → 几何前置过滤/背光亮度门槛
  → ua_hand_shape_classifier：掌心/腕部/凸包/轮廓/凹陷/指宽/原始类别
  → ua_hand_frame_policy：例外形状门槛、整数均值、评分、优胜候选
  → ua_hand_temporal_vote：五帧投票、五帧撤手、结果一次性提交
```

不是仅根据面积选最大块，也没有用首帧图像学习背景。几何原始类别 0/1/2/3 分别为无有效掌心或歧义、拳头、单指、张手；生产旧接口尚未替换。

### 候选与时序规则

- 每个候选使用**真实选中连通域**的 10-bit 红通道样本总和，不是包围框均值或只统计种子部分。
- `floor(red_sum/area)` 必须至少为 96；上一帧判为背光时至少为 160。前置判断改写为 `red_sum>=area*threshold`，数学上保留整除门槛，没有把除法误改成近似均值。
- 评分为 `area*min(mean_r*100,38400)`，分数相同保留候选表先出现的项。原始类别为 0 的合格候选仍可能赢，不能直接丢掉改变软件行为。
- 亮像素数在帧末达到 450 时启用下一帧背光门槛；低于 225 关闭，中间保持。使用本帧亮像素直接影响本帧候选会错一帧，本实现避免了这个错误。
- 最近五帧类别投票。票数并列时取当前窗口最早出现的类别，不是取数值最小；初始至少两票、已有稳定类别时至少三票才切换。
- 五个连续无效原始结果会清空旧类别。候选不存在时立即撤掉框，不因为短时保留类别就继续画旧框。
- 帧结果寄存器只在 `O_done` 一次性提交；处理中间值不会直接进入 OSD。CCL 面积与几何提取面积不一致会使整帧 fault，而不是静默显示。

## 证据

| 范围 | 当前证据 |
| --- | --- |
| 候选评分/过滤 | `tmp/hand_rtl/frame_policy_both_videos/result.json`：2338 帧/用例，含两视频全部 1688 帧的候选几何元数据；此项几何是软件输入，只证明 policy |
| 时间投票 | `tmp/hand_rtl/temporal_vote_initial/result.json`：535976 组，包括全部长度 8 的四类别历史、随机清除和两个视频原始类别序列；不是视频识别本身 |
| 红通道组件统计 | `tmp/hand_rtl/ccl_red_sum_address_shift/result.json`：178 组模式，逐个比较所有组件的面积、种子数、框、真实起点及红通道总和；含合并/退役/标签复用、全前景最大总和和中途清除 |
| 旧 CCL 兼容 | `tmp/hand_rtl/ccl_rgb_shift_compat/result.json`：248 模式，含 6 组预期溢出，保持旧接口默认关闭 RGB 统计时的输出 |
| 真实 RGB/native 红采样 | `tmp/hand_rtl/chain_native_red_tap/result.json`：14 个选定帧，每帧 14400 个红样本逐点检查相位、地址、亮像素判定与银行；再比较全部掩膜、连通域与轮廓 |
| 采集银行/许可 | `tmp/hand_rtl/native_capture_gate/result.json`：整帧拒收、帧中许可变化不截断、原双银行所有权、畸形帧、clear/reset 和真实 CCL 握手 |
| 帧级故障恢复 | `tmp/hand_rtl/frame_classifier_faults_real_probe/result.json`：18 个完成帧、四个中断点，含真实指宽读响应取消、面积不一致、撤手和连续帧恢复 |

### 完整视频的验证口径

帧级回归由 RTL 计算全部几何、原始类别、评分与时间投票，**但输入掩膜、seed/grown 候选关联和红总和仍由独立软件前端提供**。不能把它称为“RGB→全部手势逻辑已接入 FPGA”或板上已验证。

旧合并任务 `frame_classifier_both_videos_decl_fixed` 先跑 28 帧合成动作，再跑旧视频 870 帧。全部旧视频已完成逐帧断言；通过 `hand_frame_replay.py prefix` 保存为 `tmp/hand_rtl/old_video_prefix_verified.json`，没有将后续未完成的合并任务伪标为全通过。为免新视频受合并任务超时窗口影响，已在独立硬件 clear 边界冷启动 `tmp/hand_rtl/new_video_independent_replay`，不注入旧类别、背景或软件状态。

新视频独立回归已完成：818 帧、69820323 周期、ModelSim 752 秒，零编译/仿真错误和警告，所有帧断言通过。旧 870 帧与新 818 帧合计 **1688 帧**，另有 28 帧合成动作。汇总审计已成功运行：

```
python host/tests/verify_hand_frame_regression.py --out tmp/hand_rtl/both_video_frame_regression_verified.json
```

汇总状态为 `BOTH_VIDEO_FRAME_CLASSIFIER_RTL_PASS_SOFTWARE_MASK_ASSOCIATION_INPUT_NOT_BOARD_SIGNOFF`。人工审定稳定区间：旧视频 **288/288**，新视频 **250/250**；这是 538 个稳定标签的结果，不是所有任意手势/光照均有 100% 准确率。输入关联、原始视频、标签和源码证据保留在各 receipt；两视频都从硬件 clear 开始，没有注入软件投票历史。

## 资源：不是整机已适配

以下均为 PH1P35MDG324 的 TD Optimize Gate，**不是整机放置/布线**。

| 同一维护版本的子模块 | Slice | ERAM | DSP |
| --- | ---: | ---: | ---: |
| 候选过滤/评分 | 650 | 0 | 0 |
| 时间投票 | 39 | 0 | 0 |
| 带红总和的 CCL，显式移位地址 | 849 | 0 | 0 |
| 几何＋评分＋投票帧级联合模块 | 7025 | 14 | 10 |

CCL 首次含红统计测得 897 Slice、1 DSP；将 `160*y+x` 明确写成移位相加后为 849 Slice、0 DSP，178 组红统计和 248 组旧模式重新通过。报告为 `blob_rgb_gate.area`，对应新日志为 `blob_rgb_shift_gate.log`。

跨仿真器修复了 ModelSim 不允许在过程块引用后才声明 `primary/secondary` 的编译问题，仅移动声明后，两种比较分支各 66 组回归再次通过。当前单区域同源码 A/B 为 **7155→6194 Slice，节省 961（13.4%）**，14 ERAM/10 DSP 不增加；审计为 `classifier_decl_compatible_ab.json`。原 7171/6158 是之前报告，不能混作当前测量。

当前联合模块 7025 Slice 还**不包含**掩膜前端、上述 CCL、候选关联、红采集暂存与顶层适配。它不能简单替代原约 2300 LUT/进位口径的手势模块就宣称装得下。最近整机布局仍为 v45：20537 Slice、85 ERAM、22 DSP；原工程源清单仍使用旧手势模块，所有其他功能未关闭。

## 尚需完成

1. `ua_hand_mask_frame` 已提供 native 红/亮像素采样端口及可选整帧采集许可。分类器现已增加空闲期 scratch 访问端口（详见 `HAND_ASSOCIATION_CAPACITY_20261018.md`）；完整顶层的“采样→两种 CCL 红统计→候选关联→几何”所有权还未接入生产工程。
2. 完整实现软件前端的 seed 面积排序前 16、grown 重叠关联、相同 grown 去重和 seed 回退。不能用最大块或包围框相交冒充这一步。
3. 用更强的共享运算/存储微架构降低新分类器逻辑。当前原型用于锁定算法，资源仍明显紧张；不是只差几十个 Slice。
4. 缓存扰动诊断 `cached_stress_failure_audit.json` 仍有真实失败：新视频 dim90 23 帧、warm5 36 帧等，涉及候选失效和原始分类变化；不能把正常视频通过称为暗场问题完全解决。
5. 完整 RGB RTL 回归、暗灰/背光扰动、生产源清单接入、整机资源与 Routed 时序闭合、bit 哈希验证全部通过后才生成并 SRAM 烧录。不写 Flash，不启用舵机。

### 本轮增量证据：空闲期 RAM 复用

`idle_scratch_reuse_verified.json` 校验当前源码哈希、66 组启用接口的单区域测试、18 帧故障恢复和 36 帧 ModelSim 默认兼容回归。同期微综合启用接口 6213 Slice/14 ERAM/10 DSP，禁用 6172/14/10；增加 41 Slice，避免独立 native 红帧缓存，但未解决分类器整体资源缺口。

两段视频的关联容量审计涵盖 1688 帧，seed 生命周期临时标签最多 89，6 位标签方案不能采用。重叠并列、重复 grown、seed 回退均真实存在，不能以最大块/框相交替代。审计报告 `association_capacity_both_videos.json` 是软件容量证据，不是完整 RGB 识别 RTL 通过。

真实 RGB→native 红采样→实际分类器 scratch→grown CCL 红总和的 14 选定帧回归已通过，`chain_actual_rgb_shared_red/result.json`；逐区域红总和、2430 字掩膜和轮廓全部精确比较。该子链路不调用 shape 分类且未实现候选关联，不能称为完整视频识别。合并源码审计 `idle_scratch_reuse_rgb_verified.json`。
