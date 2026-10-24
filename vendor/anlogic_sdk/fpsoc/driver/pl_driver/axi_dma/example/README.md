# PL AXI DMA

## 概述

AXI DMA 示例工程展示了如何使用 PL AXI DMA 进行 stream 数据搬运。

## 硬件设置

### Direct Mode

#### Disable Micro：

1. 传输数据量 <= (1 << buffer length) - 1

#### Enable Micro：

1. (Memory map Data Width / 8) * Burst Size / (Memory map Data Width / Stream data width) <= (1 << buffer length) - 1
2. 传输数据量 <= (Memory map Data Width / 8) * Burst Size / (Memory map Data Width / Stream data width)

### Scatter/Gather (SG) Mode

#### Disabled Micro：

1. 单个描述符数据量 <= (1 << buffer length) - 1
2. 所有描述符数据量 <= (1 << buffer length) - 1

#### Enable Micro：

1. (Memory map Data Width / 8) * Burst Size / (Memory map Data Width / Stream data width) <= (1 << buffer length) - 1
2. 单个描述符数据量 <= (Memory map Data Width / 8) * Burst Size / (Memory map Data Width / Stream data width)
3. 所有描述符数据量 <= (1 << buffer length) - 1

### Hardware

burst size 最大设置为 16。

## 已知问题

无已知问题

## 运行说明

示例1: axidma_direct_mode.c
- 本示例演示如何使用 PL AXI DMA direct 模式进行数据搬运。
- 需烧录对应的 bit，该 bit 内置一个数据收发器，使能 direct mode。
- 通过：TRANSFER_METHOD 切换中断/轮询方式。

示例2: axidma_sg_mode.c
- 本示例演示如何使用 PL AXI DMA Scatter/Gather 模式进行数据搬运。
- 需烧录对应的 bit，该 bit 内置一个数据收发器，使能 sg mode。
- 通过：TRANSFER_METHOD 切换中断/轮询方式。

示例3: axidma_loopback.c
- 本示例演示如何使用 PL AXI DMA Scatter/Gather 模式进行环回数据搬运。
- 需烧录对应的 bit，该 bit 内部将 S2MM 与 MM2S 通道回环，使能 sg mode。
- 通过：TRANSFER_METHOD 切换中断/轮询方式。

示例4: axidma_loopback_cyclic.c
- 本示例演示如何使用 PL AXI DMA Scatter/Gather 模式进行 cyclic 数据环回搬运。
- 需烧录对应的 bit，该 bit 内部将 S2MM 与 MM2S 通道回环，使能 sg mode。
- 为观测到 cyclic 现象，示例使用的是中断驱动方式。
- 通过：DEFAULT_THRESHLOD 修改传输阈值。
- 通过：DEFAULT_CYCLIC_COUNT 修改cyclic次数。

## 注意事项

对于小数据量的 cyclic 传输场景，应避免采用中断驱动方式。
频繁的中断请求会引发中断风暴，导致CPU资源被大量占用，进而影响系统任务的实时响应与正常调度。