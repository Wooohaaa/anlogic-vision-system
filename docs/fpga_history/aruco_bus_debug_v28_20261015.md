# v28 ArUco 实板总线排查

目标是查清 v27 MCU 首次签名读取的总线错误；不调整图像算法、不删除功能、不扩大舵机范围、不写 Flash。

## 起点与恢复基线

- 板上 v27 FPGA 已原生 SRAM 下载，用户确认摄像头 HDMI 正常。
- v27 ArUco MCU 在 `0x80000000` 读取发生 Load access fault（MDCAUSE=2）。原 MCU 控制 OFF 固件已恢复，串口正常、`armed=0 remaining=0 faults=0`。
- v27 接入前的 wrapper、构建脚本与最终报告已复制到 `tmp/v27_bus_baseline/`；原 v27 bit/ELF 没有被替换。

## 不改变功能的诊断记录

`rtl/user/ua_tracking_mcu.v` 中加入 `ua_aruco_bus_trace`，仅观察 AHB 首笔 HTRANS[1] 有效的地址/尺寸/方向，并保留完成、错误响应标记。不参与 ready/response 的生成，也不影响视频、RAM 或 PWM。

使用未外接 GPIO0 输出作为诊断移位步进，GPIO7 输入作为数据。只在 CPU 暂停、目标快照稳定后扫描，不能宣称这是通用实时 coherent CDC 接口。GPIO0 没有新外接引脚，GPIO1/2 PWM 输出和 GPIO6 目标使能保持低。原虚拟按键 GPIO3/4/5 不变。

64 位记录从 bit0 读起，每个 GPIO0 上升沿递增位置，64 位后回绕：

| 位 | 内容 |
|---|---|
| 63:56 | 0xA7 帧头 |
| 55 | 首笔事务已记录 |
| 54 | 记录后曾看到非零 HRESP |
| 53 | 记录后曾看到 HREADY |
| 52 | 固定 1，诊断格式校验位 |
| 51:50 | 首笔 HTRANS |
| 49 | 首笔 HWRITE |
| 48:46 | 首笔 HSIZE |
| 45:15 | 首笔 HADDR[30:0] |
| 14:0 | 固定 0x52A5 尾标记 |

`host/aruco_bus_trace.py` 只解码，不访问硬件；仿真 `host/tests/tb_aruco_bus_trace.sv` 覆盖首笔保留、错误/完成、64 位扫描回绕、复位。Python 单元测试覆盖解析、地址窗口/访问宽度/对齐、无效帧拒绝。

## 验证边界

v28 当前为诊断构建，不能视为 ArUco 已修复。必须重新查看最终 Routed 时序、零 STNS/HTNS、输入哈希、bitgen 成功日志与 bit 哈希后才可下载；板上读出记录后再决定修正地址规范化、访问宽度、总线时序还是时钟配置。不得把离线模型的假设当作硬 MCU 的实际输出。

GPIO 操作使用 PH1P35 的 gpio_n MODE0/MODE1/OVAL，不能误用其他系列 GPIO INPUT_EN 寄存器。扫描后恢复原 MCU OFF 程序；未授权启动舵机。

## 2026-10-16 续跑与时序修正

昨晚构建中断在 route，当前进程已停止。核对 231 项输入一致后，从 SHA256 为 `E1ADBA449C4A9BFA67F3B077604EB9C96968D568C08B76D4004D56172695421F` 的 placement 检查点续跑。首个最终结果 SWNS +0.155ns、STNS 0，但 HWNS/HTNS 均为 -0.754ns，唯一负裕量路径是 trace address 寄存器到 MCU gpio7_in。工具跳过 1 条 abnormal path，交付检查正确拒绝此 bit；保存在 `tmp/v28_rejected_hold/NOT_FOR_PROGRAMMING.bit`，未下载。

诊断 GPIO7 输出改为 sys_clk 下降沿寄存，首笔 AHB 捕获逻辑、GPIO0 扫描协议、视频与控制信号不变。新增仿真检查返回位不会在 MCU 上升沿发生变化。由于 RTL 改变，不再复用旧 placement，重新执行完整构建；不修改时钟约束或屏蔽该路径。

08:44 原生只读 JTAG 检查确认器件为 PH1P35MDG324（`tmp/v28_read_id.log`），未执行 download 或 FPGA reset。当前 v28 重构建仍在进行，不能把旧失败 bit 用于后续硬件访问。MCU v28 ELF SHA256 为 `BB1BC60E94322DBBBA0B706237E5BDB50F471E7A2364574C602CFD4C8EFDBFC2`，在第一次 Fabric 访问前将 SDK AHB 分频寄存器 `0x18000104` 写为 0 并执行 fence，以保持 50MHz；目前未据此宣称原访问异常已修复。

用户随后确认开发板运行电源尚未开启或 USB 未连接。本轮只继续离线构建，不进行 SRAM/MCU 加载；关闭本轮自行启动的只读 hwserver。读到 JTAG ID 不足以证明摄像头/MCU 运行供电已就绪，须等用户准备好实际供电后再验证。

## 2026-10-16 最终离线结果

完整重构建通过：Slice 19428/21216（91.57%）、ERAM 105/108、DSP 15/40；Routed SWNS +0.105ns、HWNS +0.020ns、STNS/HTNS 均零，STA coverage 94.55%。最终日志 `td_20261016_084309.log` 无 abnormal timing path、无多驱动。231 项 FPGA 输入、15 项 MCU 维护输入与记录相符。

可验证 bit 为 `deliverables/camera_hdmi_v28_aruco_bus_trace.bit`，SHA256 `730B6DF08D4AC9963DAAFB133A7B6358858C2307D753D69A757FA19B3ED8AF9B`。v28 MCU SHA 不变。**均未上板，本轮没有 download、没有写 Flash。**

扩展仿真及演示放在 `deliverables/aruco_simulation/`：61 个合成场景（60 个常规＋1 个压力），本次均正确；其中 9 种场景在 50MHz/25MHz 总线下分别经过完整 720p→快照→AHB读出→实际嵌入式 C，共18帧，每帧14400像素逐点一致。50MHz/25MHz 各512笔压力访问与8次中途复位均通过，PWM保持OFF。基础270图像、3200单比特解码、冻结/释放/超时/复位和PWM回归继续通过。

一键复跑 `tools/test_aruco_extended.ps1`；只读交付审计 `tools/verify_v28_simulation.ps1`。完整范围、效果图、离线移动MP4和上板验收门槛见 `deliverables/aruco_simulation/README.md`。叠加框为离线可视化，不是新增 HDMI OSD；协议主机不是硬 MCU 指令模型。因未复测硅上接口，不能宣布 v27 的 MMIO 异常已消失，或保证真实暗光识别率。

08:59 一键全套复跑及独立交付审计再次通过（`tmp/aruco/v28_extended_all.log`、`tmp/v28_simulation_delivery_audit.json`）。MP4 解码检查为28帧、640×402、离线编码5fps。MCU 构建入口默认固定为当前 v28，避免误覆盖历史 v27；重新链接后的 ELF SHA 保持不变。
