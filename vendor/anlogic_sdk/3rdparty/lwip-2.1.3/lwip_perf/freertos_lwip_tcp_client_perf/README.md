# LWIP

## 概述

FreeRTOS LWIP TCP client perf 例程提供如下功能：

- 测试FreeRTOS下LWIP的发送性能，使用GBE driver

## 硬件设置

无特殊设置

## 已知问题

无已知问题

## 运行说明

示例:
- 当前文件夹下的lwipopts.txt是优化后的LWIP配置文件，使用该文件中的配置发送性能才能达到最优，
  将当前文件夹下的lwipopts.txt文件内容替换到3rdparty/lwip-2.1.3/ports/lwipopts.h中

- PC端运行iperf -s -i 5 -w 2M 命令

- 运行code