# v63：三色候选槽共享更新单元

## 当前状态与限制

v62专用MUX映射选项确实生效，但实际布局仍19393 Slice，未改善，因此没有路由。v63不继续换映射参数，而对颜色/形状观察支路作结构性共享。

仅维护源 `rtl/user/ua_track_detect.v` 改动；曝光修复仍为v59，降噪恢复原v59，OSD/手势/数字/ArUco/MCU/SDC/管脚均不改，不关闭功能。

v63已验证真实整机节省154 Slice，但未达到本轮更严格的19120布局门槛，所以没有进入布线。当前v64进一步比较候选库的物理存储实现；尚无可烧录新版本。

## 原理与可观察行为

原先红/绿/蓝各实例化一个 `ua_blob_select2`，每个模块独立更新两个候选。每个输入组只可能命中一种颜色：红色含R>=G且R>B，绿色含G>R且G>=B，蓝色含B>R且B>G；不依赖DOMINANCE_MIN才能互斥。原条件与阈值不变。

v63保留每色两个槽、各自有效标记/面积/坐标/旋转投影极值，以一个 `ua_blob_bank3` 共享命中槽的匹配选择和描述符更新运算。六个候选依旧独立，不把三色目标混到同一槽；帧末仍同拍发布三色，原流水中的快照、尺寸过滤、分类、稳定逻辑都保持。

- 同一颜色优先match0、match1，再分配空槽；两槽满时回收较小槽，平局仍回收槽0。
- 最大候选平局仍选槽0，面积18位行为不变。
- 存储描述符不批量复位；有效位复位。任何候选在有效前必先初始化，未命中时对外仍输出全零。
- EOF最后命中仍计入结果；EOF后的发布周期不变。连续帧SOF与旧帧发布同拍时，发布仍读旧状态。
- 不新增时钟或CDC，不插入空拍，不改四像素/拍显示通路。
- 模块独立接口要求I_hit one-hot或零；若未来更改判色使其可多命中，必须先重构本共享接口，不可直接接入。

旧 `ua_blob_select2` 保留用于回归与微综合对照；产品顶层只实例化共享模块。原型文件 `addons/resource_opt/ua_blob_bank3.v` 是同算法试验副本，不额外加入TD源清单以避免重复定义。

## 验证证据

1. `tb_blob_bank3`：59958周期与三个旧选择器输出逐周期一致。输入覆盖三色、两槽匹配和回收、无命中、随机坐标/投影极值、有效空拍、SOF/EOF相邻或同拍、中途复位。
2. `tools/test_track_v63.py` 完整检测输出对照已通过：4×1、16×2、32×2、40×2、64×48各24帧，及1280×720连续8帧。全分辨率共2345917周期，312位输出（像素、流标记、目标数、三色坐标/框/形状）零差异。对照为此前已验证的v40语义参考，同时每拍断言实际颜色掩码不多命中。
3. 回归receipt `tmp/v63_track/result.json` 为 `TRACK_V63_CYCLE_EXACT_PASS_NOT_ROUTED`，包含当前RTL、测试与参考的hash。不能用旧v60回归替代本版。
4. 新曝光8组回归另见 `tmp/v63_regression/result.json`，确认共享观察支路未改变曝光及显示亮度实现。

## 独立资源估算，非整机结果

同器件PH1P35MDG324、相同118IO包装、相同输出折叠、相同`adder_mux_unsharing off`/`opt_area high`/`pack_effort high`设置：

| 项目 | 三路旧选择器 | 共享候选库 |
|---|---:|---:|
| Gate估算Slice | 1805 | 1517 |
| 寄存器 | 1373 | 1313 |
| ERAM | 0 | 0 |
| DSP | 0 | 0 |

估算减少288 Slice，不能直接当整机减少288。新估算中含176 DRAM LUT，最终需关注整体打包与局部拥塞，不能只看组合逻辑LUT下降。

报告 `tmp/blob_bank3_old.area`、`tmp/blob_bank3_new.area`；日志中各有MICRO_COMPLETE标记。先测原型资源再合入，未把未综合原型直接上板。

## 整机流程

独立隐藏窗口流水线 `tools/run_hdmi_v63_pipeline.ps1` 于2026-10-20 15:41（Asia/Shanghai）启动；记录 `tmp/v63_process.json`。先完整检测回归与曝光回归，再同步工程、全量综合布局，**Slice≤19120**且ERAM≤108、DSP≤40才启动默认路由、hold修复、最终时序和联合镜像封装。

结果为 `tmp/v63_area_result.json`、`tmp/v63_build_result.json`、`tmp/v63_flash_build_result.json`、`tmp/v63_pipeline_result.json`。任何失败即停止，不放宽门槛、不自动重试、不关闭功能。联合镜像仍使用原v55 MCU，不访问JTAG/COM，不写SRAM或Flash，不启用舵机/步进电机。

自动跟进已转到v63，仅完成、实际失败或需用户操作时通知；旧版不恢复。真实曝光与颜色画质仍须未来上板确认。

## v63 最终布局：真实降低，但仍未达本轮目标

实际 **19239/21216 Slice（90.68%）、97/108 ERAM、25/40 DSP**，比v59/v62的19393减少154。LUT19116（旧19242）、寄存器17475（旧17483）；DRAM LUT从472增加到648。

该占用符合用户此前92%硬上限，但不符合本轮主动设定的19120更严格布线门槛，因此 `tmp/v63_area_result.json` 和 `tmp/v63_pipeline_result.json` 按本轮目标记录失败并停止。不是功能回归失败、器件超限，也不能说已路由/烧录。当前v63有真实整机节省，不再引用288微估算代替实测。

原维护源快照 `tmp/v63_track/ua_track_detect.frozen.v` 保留。v63没有默认路由的最终时序或实际布线耗时数据。

## v64：显式寄存器存储候选库

仅调整 `ua_blob_bank3` 内部的三项浅数组：以generate分离每bank的两组寄存器，再以相同共享更新单元写入。移除数组RAM推断，试用器件剩余FF空间而非新增DRAM LUT。不使用未核实的RAM映射属性，不修改时钟、复位有效位、阈值、槽规则、像素或发布时序。

独立流水线 `tools/run_hdmi_v64_pipeline.ps1` 于15:58启动，16:00进入综合布局。当前v64的随机blob对照、六尺寸含1280×720连续8帧检测逐周期对照与8组曝光回归均通过，receipt分别 `tmp/v64_track/result.json`、`tmp/v64_regression/result.json`，hash指向当前v64源码。测试bench名称和输出标签保留v63，是共享测试夹具，不用它代替本版独立receipt和源码hash。

当前v64资源和时序仍未完成，不能预先称比v63更省。若未达19120则自动停止，保留v63作为已验证的最佳资源候选。自动跟进已转v64；不得自动烧录或启用外设。

## v64结论与v65：按用户原92%上限实测最佳布局

v64实际布局19306 Slice、97 ERAM、25 DSP，比v63的19239多67，已被门槛停止，没有布线。该写法已撤回；维护源和部署副本恢复v63快照，**tmp/v63_area_source_hashes.json全部输入逐项匹配**，不是仅恢复一份未同步的RTL。

本轮试验90.12%/19120是助手后来增加的内部目标，用户此前实际接受的是92%/19518。v63真实90.68%已满足用户上限并减少154 Slice；继续叠加小改动没有更好结果，因此明确向用户说明改用最佳v63布局做一次路由实测。**没有达到19120，不改写旧FAILED为通过，也不再换参数反复重跑同一旧布局。**

新版本v65不改变v63任何RTL、阈值或时序，而是独立接纳与路由试验：

- `tools/accept_v63_user92_for_v65.ps1`核对原失败只来自自设资源门槛、原完整综合成功标记、两组回归及全部源码hash；独立重新导入旧布局并报告实际19239/97/25，记录 `tmp/v65_imported_placed.area` 和 `tmp/v65_verify_placed.log`。
- 验证原布局DB哈希不变后复制为v65独立DB：SHA256 `04E4F3E0D85BF61E1836E1E5DF464219BACE52C4D5C381245D8E7C4F22AB0F8F`。
- 新接纳receipt `tmp/v65_area_result.json` 为 `PLACED_RESOURCE_ACCEPTED_USER92_TRIAL_NOT_ROUTED`，明确 `experimental_19120_goal_met=false`、实际节省154，不能当作19120门槛通过。
- `tools/run_hdmi_v65_pipeline.ps1`于16:16独立后台启动，以 `tmp/v65_process.json`核对。当前默认路由运行中，后续hold修复、全部Routed时序、最终Slice≤19518/ERAM108/DSP40及哈希核验后才封装镜像，不重新做已经验证的综合。
- 日志 `tmp/v65_route.log`；最终receipt分别 `tmp/v65_build_result.json`、`tmp/v65_flash_build_result.json`、`tmp/v65_pipeline_result.json`。真实布线耗时与时序仍待完成，不提前宣称比旧版快。

当前聊天自动跟进已转v65。失败不自动重试，不修改源/约束/用户上限，不关闭功能；不访问JTAG/COM、不烧录SRAM或Flash、不启用舵机/电机。实际曝光画质仍待用户上板验证。

## v65 最终完成：Routed和联合镜像独立复核通过

2026-10-20 16:22（Asia/Shanghai），`tmp/v65_pipeline_result.json` 为 `BUILD_AND_PACKAGE_VERIFIED_NOT_PROGRAMMED`；独立审计 `tools/verify_v65_delivery.py` 通过，记录 `tmp/v65_delivery_verified.json`。

- 最终 **19239/21216 Slice（90.68%）、97/108 ERAM、25/40 DSP**。比原19393减少154 Slice，功能全部保留，MCU仍为原v55。
- Confidence=Routed，Both slow/fast corners；**SWNS +0.101ns、HWNS +0.020ns、STNS=0、HTNS=0**。STA coverage=95.10%；这不代表未约束路径或板卡电气/CDC均已被本次STA证明。
- 实际`route`命令 **361.737213秒（约6分2秒）**，`fix_hold`9.377366秒。从启动路由包装到联合封装约6分36秒，不含之前的仿真和综合布局。此前v59默认路由约44分钟后报拥塞失败，不能将失败旧轮当作成功运行基准计算“加速倍数”；本次至少证实新布局能结束并通过约束检查。
- FPGA bit：`deliverables/camera_hdmi_v65_brightness_fpga.bit`，SHA256 `ED22B51B5A47938BE4725581F8C568C204A4BAC7AE7E407468FA0990137CCFBC`。
- FPGA+MCU联合Flash镜像：`deliverables/camera_hdmi_v65_fpga_mcu_flash.bit`，SHA256 `7F75FF53546114269F188C39B834D808D9E8DBB3ADCB6DD96A89ECAF7CA7A019`。
- 独立再次核验所有冻结输入/回归源码hash、完整FPGA配置区一致、0xE00000原bootloader、0xE10000 v55 MCU payload、头与CRC32，v55 ELF仍为 `1A37280AB34199A31E6923E090D5C8E2066535BF7BA2E0E38FCD448790958B45`。
- route日志无ERROR/CRITICAL-WARNING/未匹配cell/net，完成标记存在。两组回归源码与实际交付源码一致。

**没有烧录SRAM或Flash，也没有启用舵机/电机。** 真实曝光反光容忍效果、上板画面、冷启动均尚待验证。19120/90.12%内部目标仍未达到，最终符合用户原92%上限，不更改历史失败记录。当前跟进完成后暂停，不重复构建或写板。
