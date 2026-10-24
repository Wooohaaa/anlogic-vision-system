# 步进驱动一脚一线接线修订

本说明替代旧文档中 SLP、RST 共用一根线的接法。新增 RST 输出已纳入 v77 联合 Flash 并完成原生写入校验；旧 v76r1 不支持。断电接线后重新上电加载新版。MCU 固件不变，默认电机关闭。

依据 HX1P35B_FT 原理图第2页 BANK32=3.3V、第7页 J2 GPIOB 排针。按板上 pin1 标志编号，不凭照片方向数针。

| FPGA J2 | FPGA 球脚 | 驱动端子 |
|---|---|---|
| 3 | E12 | 第一路 PWM/STEP |
| 4 | E16 | 第一路 DIR |
| 5 | E17 | 第一路 SLP |
| 6 | F13 | 第二路 PWM/STEP |
| 7 | F14 | 第二路 DIR |
| 8 | F18 | 第二路 SLP |
| 9 | G17 | 第一路 RST |
| 10 | H17 | 第二路 RST |
| 12 | GND | 第一路 GND |
| 28 | GND | 第二路 GND |

SLP 和 RST 的物理引脚独立，逻辑仍同步跟随原有 AWAKE，保留默认关闭、停止尾部保护、50ms 唤醒及看门狗关闭时序。不要短接两个 FPGA 输出，也不要将使能端固定拉高。

接线必须断电；12V 正负极只接驱动电源端，电机电流直接回独立电源，FPGA 与驱动共信号地，12V 不得接 GPIO。DCY 暂不接。电机线序、相电流和驱动限流仍须核验，禁止带电拔插绕组。本次修改不授权电机运动。

## 验证与部署记录

- 顶层独立引脚仿真通过：实际 design_top_user 的四种 AWAKE 状态、关闭恢复与两轴对应关系均正确；其他厂商模块在该测试中黑盒处理，不是整机仿真。原步进、ArUco 共享总线、MCU 五组回归通过。
- 与已部署 v76r1 的硬件源码对照，仅增加 RST 顶层端口、安全使能别名及对应引脚约束；没有改变视频算法或 MCU。引脚校验工具增加唯一性检查。
- 最终 Confidence Routed；Slice 19465/21216（91.75%），ERAM 97/108，DSP 32/40。SWNS +0.009ns，HWNS +0.020ns，STNS/HTNS 均为零。最终 I/O 报告确认 RST0=G17、RST1=H17、LVCMOS33。
- FPGA：`deliverables/camera_hdmi_v77_color_fpga.bit`，SHA256 `8DB924B86DDAD65C5F2A646E956C3A8EED74F0CD26C8DCA9716C5E364A819CD8`。
- FPGA+MCU 联合 Flash：`deliverables/camera_hdmi_v77_fpga_mcu_flash.bit`，SHA256 `57E916C4ACB5C415A5B85257FDE4F93B0B267EE84D6D861D5BC5D45E95EFE9A9`。MCU 仍为步进+ArUco v69，ELF SHA256 `048EEE52253F9B7E456D4B666484B8EC93698E93FDF5FAF95CC5BC7D4F860F78`。
- 初次烧录服务未能启动，用户随后确认之前未开机并已开机。未重新综合，重新核对既有文件后仅一次实际 Flash 下载；官方 BitWriter 芯片验证、Page program and verify、最终通过标记均成功，耗时约102秒。见 `tmp/v77_flash_programmed.json`、`tmp/v77_flash_program.log`。
- 没有发送运动或串口调试命令，没有改 USB 驱动。断电重启、排针实际电平、电机线序/限流和机械运动仍待实物验收，未宣称已验证。
