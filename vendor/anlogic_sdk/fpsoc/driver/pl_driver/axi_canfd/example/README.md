# AXI-CANFD

## 概述

axi-canfd example 例程提供如下测试功能：

- 中断/轮询测试
- can 帧 loopback 收发测试

## 硬件设置

所提供 example均为 loopback模式，无需外接 can收发器。
如需接入 canfd网络，需调用 AlAxiCanFd_Hal_IoCtl将 axi-canfd配置为 Normal模式。

## 已知问题

无已知问题

## 运行说明

示例1: al_axi_canfd_loopback_intr.c
- 中断模式下loopback模式帧的发送与接收，默认发送与接收 100帧。

示例2: al_axi_canfd_loopback_polled.c
- 轮询模式下loopback模式帧的发送与接收，默认发送与接收 20帧。
