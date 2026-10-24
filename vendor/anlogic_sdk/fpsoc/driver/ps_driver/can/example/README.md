# CAN

## 概述

### CAN 波特率计算
    bitrate * tq * tseg = 1
    tseg = sync_seg + tseg1 + tseg2
    tq * clock = presc

    sync_seg + tseg1 + tseg2 = clock / (bitrate * presc)

### 常用波特率及参数
| bitrate[Mbit/s] | sample-point | prescaler | seg1 | seg2 | sjw |
|:---------------:|:------------:|:---------:|:----:|:----:|:---:|
| 0.25 | 0.8  | 4 | 64 | 16 | 16 |
| 0.5  | 0.8  | 2 | 64 | 16 | 16 |
| 1    | 0.8  | 2 | 32 | 8  | 8  |
| 2    | 0.8  | 2 | 16 | 4  | 4  |
| 4    | 0.8  | 1 | 16 | 4  | 4  |
| 5    | 0.75 | 1 | 12 | 4  | 4  |

### CAN example 例程提供如下测试功能：

- CAN 外设的内/外回环测试
- CANFD 相关测试
- CAN-DMA 相关测试

## 硬件设置

无特殊设置

## 已知问题

无已知问题

## 运行说明

示例1:al_can_ex_loopback_blocked.c
- CAN 外回环测试: ptb 传输模式，中断模式，CAN2.0标准。

示例2:al_can_fd_dma_llp_nonblock.c
- CAN 正常模式:ptb 传输模式，dma中断llp测试，CANFD标准。

示例3:al_can_fd_dma_nonblock.c
- CAN 正常模式:ptb 传输模式，dma中断，CANFD标准。

示例4:al_can_fd_stb_fifo_blocked.c
- CAN 正常模式: stb 传输模式，buffer slot采用fifo策略，中断模式，CANFD标准。

示例4:al_can_fd_stb_priority_blocked.c
- CAN 正常模式: stb 传输模式，buffer slot采用priority策略，中断模式，CANFD标准。

示例5:al_can_in_loopback_blocked.c
- CAN 内回环测试: ptb 传输模式，中断模式，CAN2.0标准。

示例6:al_can_std_ptb_blocked.c
-CAN 正常模式: ptb 传输模式，中断模式，CAN2.0标准。
