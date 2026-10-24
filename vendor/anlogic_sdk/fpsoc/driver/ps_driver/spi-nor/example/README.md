# SPI-NOR
- SPI-NOR 是一套纯软件代码框架, 方便兼容各 SPI/QSPI 控制器及 flash, 统一接口, 方便用户使用.
- 对于在 al_spi_nor_ids.c 中未列出的 flash, 该框架会尝试使用1线及3byte模式对flash进行访问.
- 用户可根据flash手册, 在 al_spi_nor_ids.c 中添加所需的 flash 信息.

## 概述

该示例工程演示了如何使用这套代码对flash进行读写擦除.

## 硬件设置

无特殊设置

## 已知问题

对于 PS QSPI 控制器, 当IO频率较高时, 且由于制板差异, 电路间的延时容易影响控制器对RX的采样时机,
用户可在函数 AlSpiController_PsQspiInit 中调整控制器的 Sample delay 参数.

## 运行说明

示例1: al_spi_nor_example.c
- 该示例演示了 Init, Erase, Write, Read api 的调用, 便于用户将代码应用到其他 application 中.
示例2: al_spi_nor_user_params_example.c
- 该示例演示了如何使用用户自定义参数进行初始化
