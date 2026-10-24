# Slice 90% 目标：v51

**最新验收调整：用户随后明确 92% 以内均可接受。新上限为 19518/21216 Slice；仍争取 90%，但达到新上限即可进入布线。** v52 在用户改目标前已冻结了 90% 检查脚本，因此不篡改运行中脚本或旧 receipt。完成后由 `tools/accept_area_v52_92.ps1` 独立核验同一布局、源码、资产、仿真及面积参数，另记 `tmp/v52_92_area_result.json`，保留旧 90% 判定。

用户要求整机 Slice 约 90%。按器件 PH1P35MDG324 的 21216 Slice，严格门槛设为 **19094**（不超过 90%）。不是将 LUT 数或小模块 Gate 估算当最终占用；实际布局达标才允许布线。保留全部功能、5×5 降噪和纯 FPGA 张掌/握拳，不给 MCU 增加手势任务，不放宽时序约束。

## 停止旧布线

按用户新要求，仅停止已核实的 v49 布线 PID 22492，原自动跟进 id v47 设为 PAUSED。不烧录 v49，不将主动停止后的 FAILED 当作工具证明不可布线。v49 布局 20491/21216 Slice、97/108 ERAM、25/40 DSP。

## 已实现与独立验证

1. 颜色检测的 18 路坐标 IIR 运算，复用为 3 路，安排在原帧末流水的 6 个空闲拍中。仍在原 fe_d[8] 同拍发布所有颜色坐标，不增加检测周期。很小的参数帧（小于 32 组）保留原并行处理，避免重叠帧改变历史语义。
2. 三色归一化面积运算在原分类前一拍依次进行，公用三组归一化寄存器与算术，取代三色各一套。分类和发布时刻不变。
3. 同一组 English/digit/安/路 字模直接映射 PH1P_LOGIC_ERAM。原同步 ROM 被工具部分拆成逻辑；显式封装保持 1024×16、一个时钟读。初始化使用厂商功能模型支持的 **.dath**，维护源和部署资产均纳入 build.py 校验。异步接口分支仍保留。

同一 134 IO、全输出校验和封装下，颜色检测 Gate 估算从 4147 降到 3355 Slice；这不是整机布局节省承诺。字库原整机层次约 221 logic LUT，新的独立综合为 7 Slice、1 ERAM。不能简单把 Gate 估算相加当实际结果。

`tmp/v51_regression/result.json` 为 `RESOURCE_V51_CYCLE_FONT_ARITHMETIC_PASS_NOT_ROUTED`：

- 4×1、16×2、32×2、40×2、64×48，以及 1280×720 连续 8 帧，所有输出逐周期与冻结旧版一致。覆盖空拍、零帧间隔和复位。
- 4096 组归一化和 100000 组随机分类算术通过。
- 厂商 ModelSim RAM/GSR 模型下全部 4096 字符行与旧字库一致，零错误。
- 生成脚本 --check 通过，字模和 .dath 初始化内容一致，包含全部 1024 个字。
- 原纯 FPGA 手势六组仿真源码哈希仍匹配；手势 RTL、ISP 图像数据链路和 MCU 接口未改。

## 工具策略核验

v50 试验提前设置的面积选项被官方 DefaultFlow 的 load_run_param 覆盖，实际布局仍 20491。其参数报告内 `multi_drive | error` 被原日志扫描误判为错误，故 receipt 为 FAILED；原始报告另存 `tmp/v50_placed_observed.area`。既不能说 v50 面积参数有效，也不把它算成功。

v51 使用官方 DefaultFlow 的 **synWildParams** 入口，在每次载入工程参数后施加：`rtl adder_mux_unsharing off`、`gate opt_area high`、`gate pack_effort high`。完整流程结束后另存实际参数表，并检查生效值。不更改 SDC、引脚或时钟。

当前已启动 `tools/check_area_hdmi_v51.ps1` 做整机综合和布局，冻结源码、资产、脚本及约束。未达 <=19094 Slice 或器件容量要求就拦截，不启动布线；尚未宣称整机达标、时序闭合或烧录。

## v52 构建修复

v51 首次整机综合发现 font_compact.dath 部署路径没有经过转换，立即失败，未进入布局或烧录。已修复 build.py 的复制和核验分派条件，让 osd_char_lib.v 与 Logo 一样使用工程内绝对资产路径；不修改生成副本冒充修复。

相同 RTL 在 `tmp/v52_regression/result.json` 重新通过全部六尺寸、算术和厂商字库模型回归（status 沿用 RESOURCE_V51_CYCLE_FONT_ARITHMETIC_PASS_NOT_ROUTED），新 manifest 含修复后的 build.py。实际部署副本字库的 .dath 也单独经过 TD 综合验证。

现在运行 `tools/check_area_hdmi_v52.ps1`，仍为 Slice <=19094 的严格门槛，不达标不布线。旧版本失败证据保留；没有烧录任何新版本。

## 最新实际布局：通过用户更新后的 92% 上限

2026-10-19 12:23，v52 完整布局为 **19516/21216 Slice（91.99%）、97/108 ERAM、25/40 DSP**。比 v49 减少 **975 Slice**，比 v47 减少 1076 Slice、7 ERAM。全部功能保留。

旧 90% receipt 按冻结门槛记为 FAILED，不能改写成达到 90%。按用户后来批准的 <=92% 上限，`tools/accept_area_v52_92.ps1` 重新独立核验原布局、全部输入、实际生效面积参数、功能回归及新上限，通过 `tmp/v52_92_area_result.json`。冻结布局 SHA256：`0210D568D65D5630CEF76524DB26BF30FA58F9B8741FEA9A7D9EB4F50801F426`。

已启动 `tools/build_hdmi_v52_binary.ps1` 从同一布局重新布线，不再重复综合。最终 Routed 时序仍需 SWNS/HWNS 非负、STNS/HTNS 为零，且最终 Slice <=19518、ERAM <=108、DSP <=40；输入/bit SHA256 必须一致。当前尚未宣称布线通过或烧录完成。

`host/tests/tb_line_threshold_v53.v` 另做了 16777216 个 24 位残差的穷举算术试验，未合入 v52 RTL，也不属于 v52 资源节省或当前烧录范围。

后台沿用原 automation id v47，已更新为“v52 92% 资源版布线及一次 SRAM 部署”，仅跟进新 v52（启动 TD PID 22104）。保持每十分钟静默检查；只在成功、实际失败或需人工操作时通知。通过最终资源、时序和哈希核验后才按原授权一次 SRAM 下载并恢复原 ArUco MCU OFF，不写 Flash、不开舵机。

## 最终 Routed 与 SRAM 部署完成

2026-10-19 12:31，完整布线、hold 修复和 bitgen 结束：

- 最终 **19516/21216 Slice（91.99%）、97/108 ERAM、25/40 DSP**，满足用户 <=92% 上限。
- Confidence=Routed、Both corners；SWNS=0.134 ns、HWNS=0.020 ns、STNS=0、HTNS=0。STA coverage=94.83%，不能据此声称所有未约束路径均已证明安全。
- route 命令 420.767627 秒（约 7 分钟），fix_hold 11.959946 秒。整套恢复布局、布线、报告和 bitgen 流程约 7 分 37 秒；不包含之前综合布局。
- bit：`deliverables/camera_hdmi_v52_binary_hand.bit`；SHA256：`3C27EFB17F1C09DDAA50B88C6DB188446C77B0F1846D3A250CE8A30CEDC2EB0A`。
- 独立复核最终面积、全部时序指标、完成标记、bit/source/字体资产哈希及全部七组回归源码一致后，于 12:34 用官方 BitWriter CLI **仅下载一次 SRAM**，未写 Flash。

### 下载后的验收解析修复

官方下载进度 100%、目标 PH1P35MDG324 核验成功，工具正常打印 `SRAM_HDMI_V52_PROGRAM_COMMAND_COMPLETE`，日志没有 ERROR。但原包装脚本对原始 CRLF 字符串使用 `(?m)^...$`，没有允许末尾 `\r`，因而没有生成成功 receipt。实测旧匹配 False、新 `\r?$` 匹配 True，完整原始日志保留。已修复此解析，不重跑下载。

`tools/verify_v52_existing_download.ps1` 仅用于该已完成下载的精确 CRLF 条件：重新核验 bit/source、完整原下载流、零下载错误，并独立只读检查新的 MCU+config 两 TAP、ID=4808f0e7、配置状态=a9c0125d、DONE 高。没有 BitWriter 或下载命令。补齐 `tmp/v52_fpga_sram_programmed.json`；明确记录原包装检查未通过、原进程退出码未保留、以完整成功日志和独立硬件验证确认，不虚构原包装脚本成功。

这次额外只读核验先用 Windows PowerShell 5.1 遇到 stderr/Stop 兼容问题，未进行任何重下载；改用 PowerShell 7 后完成。保留错误记录。

12:46，`tools/restore_aruco_v39_after_v52.ps1` 恢复原 v39 MCU 固件：ELF SHA256 `D952A80FEE124DDB1B76CCB10783A4C487F13DF9A8B6C9B608504B7992BBF178`；TCM 的 .init/.config_settings/.text/.data 四节全部 matched，串口验证身份和 armed=0、remaining=0、faults=0。`tmp/v52_aruco_v39_restored.json` 为 MCU_ARUCO_V39_RESTORED_OFF。未给 MCU 增加手势，不开启舵机、不写 Flash。

后台跟进已 PAUSED，避免重复下载；未归档聊天。FPGA 配置和 MCU 加载已通过硬件验证，但 HDMI 画面、真实手势与 ArUco 实景识别效果仍需用户观察确认，不称完美。
