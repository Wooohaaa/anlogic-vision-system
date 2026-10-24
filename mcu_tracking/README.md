# MCU：ArUco与双步进云台

当前源代码为原v83；默认电机OFF。统一构建入口为根目录`python tools/repository.py mcu`。

SDK源码在`vendor/anlogic_sdk`，编译器来自另行安装的FD。`motor.ps1`支持通过`-Port`指定串口，仅显式on才启动电机。接线与KEY2操作见根目录README链接。
