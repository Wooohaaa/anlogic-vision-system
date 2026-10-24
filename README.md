# PH1P35 摄像头图像处理与视觉跟踪（v94）

本目录为可上传仓库的独立交付副本。器件PH1P35MDG324、摄像头SC500、视频1280×720；FPGA处理图像、检测与OSD，MCU v83承担ArUco及双步进云台。无网口、无舵机。

## 目录

| 目录 | 内容 |
| --- | --- |
| `contest2_hdmi_video/rtl` | FPGA维护源码、官方IP与ROM资产 |
| `contest2_hdmi_video/prj` | TD工程、引脚/时序约束及同步副本 |
| `contest2_hdmi_video/host/tests` | RTL与主机验证源码，历史测试不等于当前版本签收 |
| `mcu_tracking` | 当前ArUco/步进MCU源码、单元测试和串口工具 |
| `vendor/anlogic_sdk` | MCU构建必需SDK源码与原许可声明 |
| `tools` | 统一校验、构建、封装、显式烧录入口 |
| `firmware` | 已验证v94 FPGA/联合Flash镜像、原MCU v83、持久启动二进制 |
| `verification` | 当前最终资源、Routed时序与交付核验摘要 |
| `docs`、`examples` | 赛题/演示脚本、设计记录及数字卡 |

过程文件在原工作目录单独保留，见[PROCESS_FILES.md](PROCESS_FILES.md)。本包没有多轮缓存和旧固件。

## 环境与入口

Windows；Python 3.11+；TD 6.2.1 Engineer 6.2.168.116；FD Release 2026.2。RTL仿真用Icarus Verilog，安装后把iverilog/vvp加入PATH，或设置IVERILOG/VVP环境变量。Python算法/视频测试先运行`python -m pip install -r requirements.txt`。

复制`config.example.json`为`config.local.json`并填写本机TD/FD安装目录。也可设置ANLOGIC_TD_HOME/ANLOGIC_FD_HOME。MCU构建暂存路径必须为无空格ASCII路径，构建入口会从本包SDK和MCU源码复制到这个独立工作区；不依赖原电脑上的ph1p35_terminal_demo目录。

在本仓库根目录执行：

```powershell
python tools/repository.py verify       # 包文件哈希、工程预检查；不接触板卡
python tools/repository.py setup        # 换路径后同步TD副本
python tools/repository.py test         # 40组位置/亮度、30组倾斜及负例RTL回归
python tools/repository.py mcu          # 从本包源码构建MCU，检查TCM+栈预算
python tools/repository.py fpga         # 从源码综合/布局/布线/时序/bitgen，不自动烧录
python tools/repository.py flash-image  # 将新FPGA与新构建MCU封装；未构建MCU时用所附原v83
```

`verify`是交付快照完整性检查；主动修改源码或setup同步路径后，原哈希变化是正常的，不能把改过的副本仍称为原始快照。新构建输出在`build/`及子工程`tmp/`、`deliverables/`中，均已Git忽略。已验证的原始固件在根目录`firmware/`，不会被新构建覆盖。

交付副本的TD同步工具把工程目录及ROM资源引用改为相对路径，终端构建固定在`prj/td_project`工作目录运行。若自行从不同工作目录调用TD或仿真工具，请先切到上述工程目录；保持维护RTL/MCU代码不变。重新构建MCU的ELF包含新工作区的调试/来源信息，不保证与所附已烧录ELF逐字节一致，不能据此声称新构建固件已经上板验证。

可选真实视频回放：把原2026-10-24数字录像另存到本机，设置DIGIT_TEST_VIDEO后执行子工程tools/replay_digit_real_v94.py或replay_digit_sequence_v94.py；固定帧标签对应该段原录像，不适用于任意新视频。本仓库不包含个人实拍录像。

## 终端烧录

仅下面显式命令会访问硬件，它烧录的是根目录firmware内的已验证联合Flash镜像。开发板外部供电、AL-LINK-FT连接且官方hwserver服务在127.0.0.1:5555时执行：

```powershell
python tools/repository.py program
```

如需启动官方服务，在PowerShell中使用配置中的TD路径：

```powershell
Start-Process -FilePath '<TD目录>/bin/hwserver.exe' -ArgumentList '-r','-f','12','-I','123456789','-s','5555' -WindowStyle Hidden
```

不自动改USB驱动、不停止未知调试服务、不启动电机。Flash完成后断电重启以验证持久启动。自行重新构建的镜像须核验资源和时序后再选择部署；本入口不会把未验证构建自动烧录。

## 功能操作

| 控制 | 功能 |
| --- | --- |
| KEY1 | 图像模式切换：直通、灰度、边缘、浮雕、卡通等 |
| KEY2 | 双步进云台红球追踪开关 |
| KEY3 | 自动白平衡开关 |
| KEY4 | 自动曝光与亮度增益开关 |
| SW1 | 颜色/形状与运动检测 |
| SW2 | ArUco |
| SW3 | FPGA张掌/握拳手势 |
| SW4 | 任意位置单张数字卡；搜索显示---，确认后显示绿色笔画框 |

数码管固定显示整体增益index和使能0/1。MCU默认电机OFF。接线和操作见[步进专用引脚](docs/fpga_history/STEPPER_DEDICATED_PINS_20261022.md)、[KEY2控制](docs/fpga_history/KEY2_STEPPER_V83_20261022.md)。

## 当前交付证据与限制

最终Routed：19777/21216 Slice、108/108 ERAM、31/40 DSP；SWNS +0.112ns、HWNS +0.020ns、STNS/HTNS=0，覆盖率95.30%。2026-10-24 20:33:53官方终端联合Flash写入/校验成功；冷启动和最新实机数字效果仍待确认。

数字0～9的合成位置/倾斜/亮度、负例、撤卡，以及实际5/7/9静态/36个连续HDMI帧回放已通过，不是任意字体、手写、多数字自然场景OCR的保证。ArUco黑框120mm，未完成实机棋盘格标定，三维轴为估计。运动框可能合并多个目标；手势困难场景仍有局限。详细记录见[数字修复](docs/fpga_history/AUTO_DIGIT_REPAIR_V94_20261024.md)。

FPGA、MCU与附带SDK的维护源码从原工程逐字节复制。新交付构建/测试包装入口经过独立核验的情况见verification/package_validation.json；不把原工作区的综合成功冒充成在新目录又完整跑了一次综合。

## 上传仓库

已提供.gitignore和.gitattributes；不会跟踪后续生成的缓存。firmware内二进制为本次交付材料，可按仓库策略改为Release附件。第三方IP/SDK保留原声明，公开再分发范围见[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。未自动创建远程仓库或上传。
