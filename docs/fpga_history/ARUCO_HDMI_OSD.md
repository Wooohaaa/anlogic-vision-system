# ArUco HDMI 框与 ID 显示

当前部署为 FPGA v34＋MCU v34，显示透视四边形和 ID，见下方 v34 协议及 [v34 部署记录](ARUCO_V34_PERSPECTIVE_OUTLINE_SPEED.md)。以下矩形框内容保留为历史协议说明。

v29 增加了 MCU 检测结果到 HDMI OSD 的显示通路。MCU 从 160×90 快照检测 ArUco 后，将四角坐标乘 8 映射回 1280×720，取外接矩形，并把坐标和十进制 ID 写入 FPGA MMIO。OSD 在矩形周围画青色双像素边框，并在框上沿附近显示黄色 `ID:nnn`。

## 结果寄存器

寄存器偏移均相对于 MCU AHB 窗口 `0x80000000`。MCU 先写坐标，最后写 `0x110` 作为提交；提交翻转一个 toggle，HDMI 域在同步后一次性采样整组稳定数据。

| 偏移 | 写入内容 |
| --- | --- |
| `0x114` | `xmin`，像素坐标 |
| `0x118` | `xmax`，像素坐标 |
| `0x11C` | `ymin`，像素坐标 |
| `0x120` | `ymax`，像素坐标 |
| `0x110` | 最终提交：bit 31 为 valid；bits 11:8 百位 BCD、7:4 十位 BCD、3:0 个位 BCD |

无标记、采集错误、结果超时或 SW2 关闭时，MCU 提交 invalid，OSD 清除旧框。框和 ID 由现有 OSD 像素通路绘制，不分配额外帧缓存。

## 交付与验证状态

- FPGA：[`camera_hdmi_v29_aruco_osd.bit`](../deliverables/camera_hdmi_v29_aruco_osd.bit)，TD Routed/bitgen 成功，最终 setup WNS `+0.103 ns`、hold WNS `+0.020 ns`，TNS 均为 0。
- MCU：[`mcu_aruco_v33.elf`](../deliverables/mcu_aruco_v33.elf)，交叉编译成功，电机默认未使能。
- 上述 v29/v33 为历史交付组合；当前已配套加载 FPGA v34 与 MCU v34。
- 本版 FPGA 资源报告：LUT6 `18,708/21,216`，寄存器 `16,937`，ERAM `105/108`，DSP `15/40`，GCLK `9/32`。ERAM 余量只有 3 块，不宜再增加大帧缓存。

## v34 协议变更（已综合并部署）

上表是 v29–v33 的矩形框协议。v34 源码将 `0x114/0x118/0x11C/0x120` 改为四个打包角点 `{y[10:0],x[10:0]}`，并用 `0x124/0x128/0x12C/0x130` 传四条边的 26-bit 定点参数；MCU 最后仍写 `0x110` 提交 ID/valid。新显示链路画透视四边形，不再显示轴对齐矩形。详见 [ARUCO_V34_PERSPECTIVE_OUTLINE_SPEED.md](ARUCO_V34_PERSPECTIVE_OUTLINE_SPEED.md)。

**注意：** v34 FPGA 已通过 Routed 时序并完成 SRAM 下载，MCU v34 已加载到 TCM并校验运行；舵机关闭，Flash 未写。v29–v33 固件与 v34 新寄存器协议不兼容，部署时必须配套版本。未标定时只显示轮廓和 ID，当前不会显示 XYZ 坐标轴。
