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

## 当前交付

**FPGA 与板内 MCU 联合 Flash**，支持掉电保存与上电运行，已完成官方终端写入及校验。

| 项目 | 实现结果 |
| --- | --- |
| Slice | **19945 / 21216** |
| ERAM | **108 / 108** |
| DSP | **31 / 40** |
| 最终时序 | **Routed** |
| Setup / Hold 最差裕量 | **+0.137 ns / +0.020 ns** |
| Setup / Hold 总负裕量 | **0 / 0** |

当前固件位于 [`firmware/`](firmware/)，资源与时序报告位于 [`verification/`](verification/)。

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

烧录当前交付固件时，连接开发板电源和 AL-LINK-FT，启动本地官方调试服务 `127.0.0.1:5555` 后执行：

```powershell
python tools/repository.py program
```

构建输出写入 `build/` 和子工程的 `tmp/`、`deliverables/`。`firmware/` 保存本次交付镜像，文件校验信息见 `PACKAGE_MANIFEST.json`。

## 文档与演示

- [作品技术文档](docs/赛题二技术文档_实时图像处理与视觉交互系统.docx)
- [系统设计说明](docs/系统设计说明.md)
- [操作与部署](docs/操作与部署.md)
- [第三方代码与许可声明](THIRD_PARTY_NOTICES.md)
