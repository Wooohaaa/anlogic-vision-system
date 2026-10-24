# LWIP

## 概述

rtthread LWIP UDP client perf 例程提供如下功能：

- 测试 rtthread 下 LWIP UDP 的发送性能，使用 GBE driver
- 作为 iperf 的 UDP 客户端，向 PC 端 iperf server 持续发送 UDP 数据报

## 硬件设置

- 将fpsoc/driver/ps_driver/gbe/inc/al_gbe_dev.h 发送描述符数量改成512
  #define AL_GBE_TX_DESC_CNT    64 修改为
  #define AL_GBE_TX_DESC_CNT    512

## 已知问题

无已知问题

## 运行说明

示例:
- 当前文件夹下的lwipopts.txt是优化后的LWIP配置文件，使用该文件中的配置接收性能才能达到最优，
  将当前文件夹下的lwipopts.txt文件内容替换到3rdparty/lwip-2.1.3/ports/lwipopts.h中

- 运行code

- PC端运行iperf -s -i 5 -u
