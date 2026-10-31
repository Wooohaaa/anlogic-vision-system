# 基于安路 PH1P35 的实时图像处理与视觉交互系统

本作品面向 FPGA 图像处理赛题，基于 **PH1P35MDG324 + SC500 摄像头**构建集图像采集、画质增强、多模式视觉处理、目标识别和云台跟踪于一体的嵌入式视觉系统。系统以 **1280×720** 视频为输入，通过 FPGA 流水线并行处理、DDR 帧缓存和 HDMI 实时输出，将视觉分析结果直接叠加到画面中，并通过板内 MCU 实现 ArUco 处理及双步进云台控制。

## 作品特色

- **实时视频与画质增强**：MIPI/CSI 视频接入，自动白平衡、自动曝光与亮度增益、5×5 降噪，适应不同光照场景。
- **七种图像模式**：直通、灰度、Sobel 边缘、二值、素描、浮雕和卡通化，可通过按键切换。
- **颜色与几何形状识别**：提取红、绿、蓝目标，识别圆形、三角形、矩形和长条形，实时叠加位置框及类别。
- **运动区域提示与计数**：结合帧间变化和网格统计，显示运动区域与运动统计信息。
- **手势与数字交互**：纯 FPGA 张掌/握拳识别，以及任意位置单张数字卡 0～9 的定位与识别。
- **ArUco 标记识别**：FPGA 与 MCU 协作完成标记识别、ID 显示、四边形描边和三维坐标轴可视化。
- **双步进云台跟踪**：视觉目标坐标传给 MCU，驱动双轴步进云台跟踪红色球形物体。
- **一体化 OSD**：叠加 Logo、模式、帧计数、延迟、IN/OUT 输入输出帧率，方便现场操作与演示。

## 系统架构

```mermaid
flowchart LR
    A[SC500 摄像头] --> B[MIPI / CSI 接收]
    B --> C[ISP 画质增强与图像处理]
    C --> D[DDR 帧缓存]
    D --> E[OSD 叠加]
    E --> F[HDMI 显示]
    C --> G[颜色 / 形状 / 运动 / 手势 / 数字]
    G --> E
    C --> H[ArUco FPGA 前端]
    H --> I[板内 MCU]
    I --> E
    G --> I
    I --> J[双步进云台]
```

## 板上操作

| 控制 | 功能 |
| --- | --- |
| KEY1 | 循环切换七种图像模式 |
| KEY2 | 开启或关闭双步进云台跟踪 |
| KEY3 | 开启或关闭自动白平衡 |
| KEY4 | 开启或关闭自动曝光与亮度增益 |
| SW1 | 颜色、形状与运动检测 |
| SW2 | ArUco 标记检测 |
| SW3 | 张掌 / 握拳手势识别 |
| SW4 | 单张数字卡识别 |

数码管显示整体增益 index 及使能状态。电机上电默认关闭，通过 KEY2 或串口命令开启。

帧率行显示 `IN / OUT`，分别统计输入与输出的有效视频帧。数字识别采用实际宽度网格分配和闭环字形质量检查，配合同类确认稳定发布结果。

## 当前交付：R6 areaopt4 + MCU r18（2026-10-31）

联合镜像已通过 FutureDynasty 官方命令行写入外部 SPI Flash，并完成厂商页校验。Flash ID 为 0xC8，镜像大小 14,775,152 字节，SHA-256 为 a8d67ccbd731a3e29d6dc075faf06dfb548774e9fedae09505a914512facb9c3。

| 项目 | 结果 |
| --- | ---: |
| Slice | **20,091 / 21,216** |
| ERAM | **103 / 108** |
| DSP | **30 / 40** |
| Routed SWNS / HWNS | **+0.132 ns / +0.020 ns** |
| Routed STNS / HTNS | **0 / 0** |

17 段视频套件仍未全部通过：倾斜 3 误识为 2、手机 0 与部分远距离数字漏检、倾斜 ArUco 漏检。冷启动尚未验证；本次烧录期间没有回放视频。R6 bitstream 使用的形状源码候选已单独存档，未合入维护 RTL。详见 [部署与验收边界](docs/FPGA_MCU_FLASH_DEPLOYMENT_20261031.md) 和 [17 段视频回归记录](docs/VIDEO_SUITE_VALIDATION_20261029.md)。

固件位于 [firmware/](firmware/)，版本和校验信息见 [verification/release_evidence.json](verification/release_evidence.json) 与 [PACKAGE_MANIFEST.json](PACKAGE_MANIFEST.json)。

## 工程目录

| 目录 | 内容 |
| --- | --- |
| `contest2_hdmi_video/rtl/` | FPGA 维护源码、IP 和 ROM 资源 |
| `contest2_hdmi_video/prj/` | TD 工程、引脚与时序约束 |
| `contest2_hdmi_video/host/tests/` | RTL 与算法测试 |
| `mcu_tracking/` | ArUco、步进控制与串口工具 |
| `vendor/anlogic_sdk/` | MCU 构建依赖及许可声明 |
| `tools/` | 工程校验、构建、封装与终端烧录入口 |
| `firmware/` | 当前 FPGA、MCU 和联合 Flash 固件 |
| `verification/` | 资源、时序与镜像校验信息 |
| `docs/`、`examples/` | 技术文档、演示材料与测试卡 |

## 构建与部署

环境：Windows、Python 3.11+、TD 工程师版与 FD 开发工具；RTL 仿真使用 Icarus Verilog。

复制 `config.example.json` 为 `config.local.json`，填写 TD、FD 安装目录和 MCU 编译暂存目录。也可通过 `ANLOGIC_TD_HOME`、`ANLOGIC_FD_HOME` 设置工具路径。

```powershell
python -m pip install -r requirements.txt
python tools/repository.py setup
python tools/repository.py verify
python tools/repository.py test
python tools/repository.py mcu
python tools/repository.py fpga
python tools/repository.py flash-image
```

通过 FutureDynasty 命令行烧录当前交付固件时，连接开发板和 AL-LINK-FT，启动本地 FutureDynasty 调试服务 `127.0.0.1:5555`，配置 fd_home 或 ANLOGIC_FD_HOME 后执行：

```powershell
python tools/repository.py program
```

构建输出写入 `build/` 和子工程的 `tmp/`、`deliverables/`。`firmware/` 保存本次交付镜像，文件校验信息见 `PACKAGE_MANIFEST.json`。

## 文档与演示

- [作品技术文档](docs/赛题二技术文档_实时图像处理与视觉交互系统.docx)
- [系统设计说明](docs/系统设计说明.md)
- [操作与部署](docs/操作与部署.md)
- [第三方代码与许可声明](THIRD_PARTY_NOTICES.md)
