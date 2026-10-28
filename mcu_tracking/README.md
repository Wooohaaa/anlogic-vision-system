# 板内视觉协处理与双轴控制

本模块与FPGA视频工程配合运行。aruco_app完成灰度快照读取、标记候选处理、字典解码与方向轴投影；stepper_app完成目标坐标解析、双轴运动请求与控制调度；stepper_firmware保存应用构建入口。

FPGA负责视频取样、结果邮箱、HDMI绘图和步进脉冲输出。MCU在协作式任务中处理视觉结果、按键和串口命令。摄像头安装在双轴步进云台上，以画面中心和红色目标中心的偏差形成跟踪闭环。

KEY2开关云台追踪。电机默认关闭，采用独立12 V电源并与开发板共信号地，控制电平为3.3 V。接线和板上操作见仓库技术文档。

统一构建和部署入口为仓库根目录tools/repository.py。firmware/mcu_app.elf是配套MCU应用，firmware/camera_system_flash.bit是FPGA与MCU联合Flash镜像。
