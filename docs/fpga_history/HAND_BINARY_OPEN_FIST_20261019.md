# 纯 FPGA 张掌／握拳：v47 实现与验证边界

**v46 已撤回，不可烧录。** 新增连续 RGB 压力测试发现它在 mask 预处理期间错误允许第二帧写共享 R scratch，实际记录到 `STREAM_NATIVE_OWNER_COLLISION state=2 address=9280`。旧版只逐帧等待后端就绪的 28 次测试未覆盖此并发情况。已停止其布线，未生成 bit、未烧录。

v47 增加整个捕获→预处理→CCL→分类事务的颜色缓存所有权锁；前端错误进入安全撤框路径并清理 sticky fault，避免所有权无法释放。单区域分类规则不变。下表同时保留 v46 历史与 v47 最新布局，均不能代替最终 Routed 时序。

## 范围

按用户确认，仅支持 OPEN（张开手掌，ID=3）、FIST（握拳，ID=1）；无候选/不确定为 0。撤销手势移至 MCU 的路线。**手势所有计算在 FPGA 内完成**，已有 ArUco MCU 固件仍独立保留，不新增 MCU 手势负担。保留摄像头、降噪、图像模式、数字、颜色/形状、motion、ArUco、OSD、AE/AWB 等功能。

这是新的两类简化算法，不是原三分类凸包/缺陷算法的等价优化。单指不再是支持的手势，不能把单指误判算作通过。

## 数据流

1280×720 四像素 RGB 总线 → 160×90 方形采样网格 → 种子/宽松肤色与形态处理 → seed/grown 两遍连通域 → 实际隔离连通分量 → 行投影分叉支持与占框面积 → RGB 置信度择优 → 5 帧投票 → HDMI 框和 H/T。

- 不保存/依赖首帧背景。
- 不使用凸包、掌心距离、手腕中值、缺陷几何、指尖宽度、seed/grown 重叠关联矩阵。
- 每行只计长度至少 2 个网格像素、间隔至少 2 个网格像素的前景段；累计至少 3 个有效段的行。
- 张掌综合判断分叉行数、占框比例、宽高比；握拳判断实心程度、宽高比及分叉稀少。
- 面积/R 均值在连通域内实际累加，不使用框内混合背景均值。
- 面积×限幅均值择优；同分取靠前实际 anchor，同 anchor 先 seed。
- 同步 RAM、队列与乘法器分时复用；实际手势核使用 4 DSP。
- 视频不反压。后端忙时丢弃整个检测帧，不读取正在改写的掩膜。
- 128 个候选槽，每个 6×16 位；溢出明确撤销检测，不悄悄覆盖。
- 内部 ID=1 表示握拳、3 表示张掌；现有 HDMI 字库将它们显示为 H:F（FIST）、H:O（OPEN），不是显示 ID 数字。T=3 表示分叉达到“至少 3”的分类支持，不是精确数出 3 根手指。

## 实测资源（PH1P35MDG324，TD 6.2.1）

| 版本 | 阶段 | Slice | ERAM | DSP |
| --- | --- | ---: | ---: | ---: |
| 完整三分类新原型 | 实际打包失败 | 26,524/21,216 | 108/108 | 36/40 |
| 两类手势核单独测试顶层 | Optimize Gate，非整机 | 2,852 | 20 | 4 |
| 两类整机 v46 | Optimize Gate，非最终面积 | 23,880 | 104 | 25 |
| 两类整机 v46 | 实际布局 | 20,716/21,216（97.64%） | 104/108 | 25/40 |
| 修复连续输入所有权的 v47 | Optimize Gate，非最终面积 | 23,897 | 104 | 25 |
| 修复连续输入所有权的 v47 | 实际布局 | 20,592/21,216（97.06%） | 104/108 | 25/40 |

最新 v47 相比装不下的三分类原型，布局减少 5,932 Slice，省 4 ERAM、11 DSP；相比旧 v45 生产版（20537 Slice/85 ERAM/22 DSP），增加 55 Slice、19 ERAM、3 DSP。逻辑还剩 624 Slice，仍很紧张；不能据此称资源宽裕。Gate 数字不能代替布局打包数字。

布局证据：`tmp/binary_hand_capacity_placed.area`、`tmp/binary_hand_capacity_place.log`。冻结 Gate 检查点 SHA256：`F98C744CF6614DEC81D52955BAF72104240889B8C23E5393D36E3F3EF5E3389E`。

## 仿真与录像回放

1. 实际隔离分量与两类规则：61 组 RTL 用例通过，包含真实录像掩膜、随机/合成形状、可变响应延迟、恶意忙时写入、clear、watchdog。证据 `tmp/hand_rtl/binary_shape_initial/result.json`。
2. 真正 RGB 输入完整链路：两段录像挑选 14 个场景，每个硬复位后回放两次，28 次输出/框/投票与独立参考一致。无注入掩膜、描述符或分类结果。证据 `tmp/hand_rtl/binary_native_rgb_final14/result.json`。这是代表场景 RTL 回归，**不是全部 1688 帧的 RTL 仿真**。
3. 队列白盒协议测试：128 槽全部记录核验、129 溢出、与最后一次写入重叠的入队、半写 clear、重新启动、空帧撤框通过。证据 `tmp/hand_rtl/binary_queue_boundary_v1/result.json`。注入 CCL 描述符只用于边界协议测试，不充当真实图像效果证据。
4. 原始两段视频全部 1688 帧的软件回放，稳定标注范围：无手 197/197、握拳 153/153、张掌 132/132，共 482/482。证据 `tmp/hand_rtl/binary_rules_anchor_final/result.json`。两段视频用于开发规则，**不是独立留出集**。
5. 不支持的单指：56 帧中 41 帧拒识、15 帧会变为握拳，保留失败记录。

v47 修复后已重跑代表场景 28 次 RTL（`binary_native_rgb_locked14`）、队列（`binary_queue_locked_v1`）。新增连续真实 RGB 输入 96 帧，不等待分类器：实际接受并完成 14 帧，明确丢弃其余 82 个**检测**帧，图像显示不反压；包含握拳→张掌→无手的独立投票/框坐标逐结果核验，0 Errors/0 Warnings（`binary_continuous_rgb_locked_v1`）。此源比真实 60fps 更紧凑，丢帧比不代表开发板显示帧率。

新增实际输入故障恢复（`binary_input_recovery_locked_v1`）：缺失像素对、截断帧、刚获取颜色缓存所有权时 clear 均安全释放；随后完整真实 RGB 无手帧成功输出。测试没有注入 mask/分类结果。

## 特殊条件压力测试：尚未全部解决

对完整两段录像施加可复现数值扰动，不改标签或阈值。以下是软件模型，不代表拍摄了新的暗场，也不代替 RTL/板上核验。

| 条件 | 支持类别和无手的正确帧 / 482 |
| --- | ---: |
| 原视频 | 482 |
| 像素亮度降至 65% | 398 |
| 像素亮度降至 40% | 329 |
| 低对比度（0.65×输入+24DN） | 408 |
| 偏绿扰动 | 368 |
| 约 2DN 亮度噪声 | 463 |

证据 `tmp/hand_rtl/binary_condition_characterization_v1/result.json`。握拳仍对暗化、灰化、肤色变化敏感，偏绿时有无手误触发；不宣称“完美”或任何光线均可靠。当前行投影也没有任意旋转不变性证据。下一轮应先收集独立新素材并评估肤色定位，而非只调分类阈值。

## 构建、烧录状态

维护源通过 `tools/build.py setup --binary-hand` 选择 ENABLE_HAND=3；ENABLE_HAND=2 是旧的过大三分类实验，1 为旧生产手势核。实际交付以有独立 receipt/hash 的 bit 为准，不要只按工程名称选旧 bit。

v46 两次布线日志保留，最终 receipt 为 FAILED，未烧录。v47 的冻结 Gate 检查点 SHA256 为 `6F4EE8268C5C7024310DA96F72344F03F551C39053E4614841B157E4C0C685B1`，布局已经通过，当前正在布线，还不能声称有最终 Routed 时序/bit/烧录成功。v47 见 `tmp/native_hand_binary_locked_gate_v2_result.json`、`tmp/binary_hand_locked_capacity_place.log`、`tmp/binary_hand_locked_capacity_placed.area`、`tmp/v47_binary_build_result.json`、`tmp/v47_binary_route.log`。

2026-10-19 烧录预检最初按旧双 TAP 链读取不到 ID（`tmp/v47_read_only_probe.log`）。用户确认供电后，独立只读扫描证实当前固件为**单 config TAP**：ID=`4808f0e7`、状态=`a9c0131d`，DONE 为高（`tmp/v47_cfg_only_read_only.log`）。官方 CLI 正确参数为 `read_device_id -level 1 -total 1`，已返回 PH1P35MDG324（`tmp/v47_single_tap_level1_read_only.log`）。未改驱动。一次 `-level 0` 读取触发了厂商工具崩溃，保留失败日志，不作为任何成功证据。

v47 SRAM 脚本会先重新确认当前单 TAP，然后使用官方标准单器件下载命令；新镜像启用 MCU 后，应有 MCU+config 两个 TAP，必须独立验证新链和 DONE，才能记录烧录成功。仅当厂商工具出现历史已知的单一最终 DONE 读取不匹配、且完整下载进度与目标核验均完成时，允许采用独立只读新链/DONE 核验；USB、ID 或其他下载失败一律停止，不重试。

用户已明确允许后台完成并烧录。原 `v47` 跟进曾为 ACTIVE；用户随后要求先降低资源再布线，已暂停该旧跟进，并主动停止旧 v47 布线。不得继续烧录旧 v47。后续资源优化记录见 `RESOURCE_COMPACT_V48_20261019.md`，只有新版本完整验证通过才允许一次 SRAM 下载及恢复原 ArUco MCU 到 OFF；不写 Flash、不启舵机、不归档聊天。

只有最终 Routed SWNS/HWNS 非负、STNS/HTNS 为零、输入/bit SHA256 一致，才允许一次官方命令行 SRAM 下载。禁止 Flash、禁止启用舵机。烧录后若需恢复 ArUco MCU，恢复原已校验 v39 固件到 OFF，不向其加入手势任务。

## v52 当前实际部署（2026-10-19）

用户批准 Slice <=92%，资源版 v52 最终 Routed 为 19516/21216 Slice（91.99%）、97 ERAM、25 DSP，SWNS 0.134 ns、HWNS 0.020 ns、STNS/HTNS 零。全部功能和纯 FPGA 两类手势保留，约 7 分钟完成 route。

官方 CLI 已仅一次 SRAM 下载；bit SHA256 `3C27EFB17F1C09DDAA50B88C6DB188446C77B0F1846D3A250CE8A30CEDC2EB0A`。原包装验收的 CRLF 匹配缺陷经完整成功日志和独立新双 TAP/DONE 检查补齐，未重复下载。原 ArUco MCU v39 已恢复，四节 TCM 校验一致、舵机 OFF、faults=0；未写 Flash，未添加 MCU 手势任务。

正式记录为 `tmp/v52_fpga_sram_programmed.json`、`tmp/v52_aruco_v39_restored.json`，详见 `docs/RESOURCE_90_PERCENT_V51_20261019.md`。后台已暂停防重复；真实画面和识别效果待用户验证。
