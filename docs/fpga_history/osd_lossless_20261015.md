# OSD 无损资源优化（v26）

## 行为约束

不删除或重画字体、Logo、状态文字、检测框，不改变相机/ISP/检测算法、按键和拨动开关、MCU 追踪控制。字体输出保持一拍；Logo presence 保持一拍、RGB 保持两拍。显示混合器源码未变，框线、字体坐标、像素优先级和视频同步不变。

基线：v25 第三轮布局 20029/21216 Slice、90 ERAM、15 DSP，尚未 routed。基线显示模块源码和报告保存在 `tmp/v26_osd/`。v24 自动烧录保持暂停；本轮不写 Flash、不启用舵机。

## 字库

`osd_char_lib.v` 同步分支原为 2048×16 ROM。改为 2048×8 双读 ROM：ASCII 仅存原始 8×8 点阵，读取后水平/垂直二倍展开；安/路两个字逐行保存完整 16 位，高低字节从同一 ROM 两端口并读。不更换字形，不丢弃 ASCII 字符，异步兼容分支不变。

独立门级综合：45 LUT、约 28 Slice、1 ERAM；全工程结果以新布局为准。

## Logo

原 indexed Logo 的颜色索引经推断成为大量逻辑。使用显式 PH1P_LOGIC_ERAM 保存索引低九位，最高位仅有 159 个非零地址，用精确稀疏译码保存，原 palette 颜色逐项不变。有效地址区间裁剪为 4096..20479，其他地址输出透明黑。

数据文件 `rtl/user/logo_index9.mif` 是必须随工程保留的资产。`tools/build.py setup` 将其同步到 TD 镜像，并在镜像 Verilog 中解析为绝对路径，避免 GUI run 工作目录改变导致初始化文件找不到。工程迁移后需再次 setup；verify 检查源码变换及 MIF 哈希一致。

独立门级综合：92 LUT、约 64 Slice、11 ERAM。此方案是用 RAM 换逻辑；不是同时降低所有资源。全工程 RAM 总量和 ArUco 缓存余量必须再次核验，不能只看 LUT 节省。

## 验证与边界

`tools/test_osd_lossless.ps1` 使用冻结的 v17 原始 Logo/字库参考：遍历 256×16 字形、4096 次随机字体读取；Logo 全部 32768 地址加 32768 次随机读取，比较颜色/透明度/时序；随后比较整个 1280×720 混合器，分别关闭/开启框线，逐周期比较 RGB、clean RGB、DE/HS/VS 和读使能。

Logo RAM 仿真使用单独的 SP/NOREG 契约模型，实际读入同一 MIF。该模型不是加密 vendor model，也不是门级或实板验证；TD 初始化读取、最终 routed 时序及 bitgen 仍需各自通过。

`host/tests/test_logo_asset_setup.py` 验证工程迁移路径解析、资产同步和初始化参数标记缺失时拒绝静默继续。

全工程布局、routed 时序和 bit 结果待完成后补充。本文件不把独立模块估算当作最终全工程节省量。

## 2026-10-15 本轮确认结果

- 字库参考逐项+随机比对、Logo 全地址+随机比对均通过。参考直接使用冻结源文件，不依赖临时导出 hex。
- 混合器无框/有框两轮各 921600 像素逐周期一致，`OSD_LOSSLESS_ASSET_PASS_CONTRACT_MODEL_NOT_HARDWARE_SIGNOFF`。日志 `tmp/v26_osd/lossless_full.log`，对应执行进程退出码 0。
- 初始化资产路径、同步和缺失拒绝 3 项 Python 单元测试通过。TD setup/verify 通过，镜像使用解析后的绝对 MIF 路径。
- 全工程布局：18946/21216 Slice（89.30%）、18448 LUT6、16567 REG、98/108 ERAM、15/40 DSP。相对本轮基线减少 1083 Slice（5.11 个占用百分点），ERAM 增加 8；剩余 2270 Slice、10 ERAM、25 DSP。未加入 ArUco 的 FPGA 图像前端。
- 布局源哈希 227 项复核不变（数量以 manifest 内容为准），checkpoint 导出时间 16:46:48，晚于输入 manifest 16:44:27；通过 v26 ResumePlacement 恢复路由，不重做综合/布局、不放宽约束。
- 当前仍未烧录。最终 routed 时序、DRC 和新 bit 待完成，不能用上述布局结果代替最终签核。

## 最终构建确认（16:51）

`tools/build_hdmi_v26.ps1 -ResumePlacement` 执行退出码 0，`HDMI_V26_BIT_FLOW_COMPLETE`，receipt 为 `ROUTED_VERIFIED_NOT_PROGRAMMED`。最后再次核验全部 227 项输入哈希不变，TD preflight 通过。

- 最终资源与布局一致：18946 Slice、18448 LUT6、16567 REG、98 ERAM、15 DSP。
- OSD 层级逻辑 LUT（包含子模块）从 1907 降到 887；Logo 从 1115 降到 30。字体最终层级为 180 LUT、1 ERAM，不能用独立门级的 45 LUT 代替最终层级值，也不能声称字体本身 LUT 下降。
- 最终报告 `Confidence: Routed`，SWNS +0.161ns、STNS 0、HWNS +0.020ns、HTNS 0；STA coverage 94.46%，不是所有外部接口全部受约束的保证。
- 原生 TD 完成 Routing DRC、hold 修复、最终 timing 与 bitgen；未放宽时序或引脚约束。TD 日志 `prj/td_project/td_20261015_164725.log`，构建记录 `tmp/v26_build_result.json`。
- bit：`deliverables/camera_hdmi_v26_osd_lossless.bit`，1789536 字节，SHA256 `BFFD74667DFAFB9C4121B9132CCA7F2DE45633247F47D796B548ADD692B96659`。

仍未烧录、未写 Flash、未开启舵机。功能等价性属于 RTL/契约模型验证，实际显示效果需实板验收。当前 ArUco 仅有独立 C 字典解码测试模块，尚未加入 FPGA 图像定位或完整板内位姿链路。

## 原生 SRAM 部署记录

用户重插烧录 USB 后，重新启动本任务拥有的官方 hwserver，BitWriter 原生流程识别 PH1P35MDG324 并完成 v26 SRAM 下载，退出码 0，日志 `tmp/v26_native_program_retry.log` 含 `SRAM_HDMI_V26_PROGRAM_COMMAND_COMPLETE`。下载前重新核验 bit SHA256 和全部 227 项构建输入哈希一致。此前失败尝试未进入 download。

随后仅恢复已校验 MCU TCM 程序，未重新配置 FPGA；串口确认 `armed=0`、`remaining=0`、`faults=0`，日志 `tmp/v26_mcu_load.log`。未写 Flash，未启动舵机。部署 receipt 为 `tmp/v26_native_deployment.json`；实际 HDMI 图像、字体、Logo 和检测框效果待用户确认。
